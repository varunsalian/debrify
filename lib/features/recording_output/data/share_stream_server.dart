// Plays recordings that live on the SMB share. Players read HTTP, not SMB,
// so a loopback-only server streams the file through dart_smb2, with byte
// ranges for seeking. A URL is stable for one profile and file (the port and
// a secret are kept per install), so the player's resume position survives
// restarts, and the HMAC token keeps other apps on the device from guessing
// their way onto the user's share.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/foundation.dart';

import '../application/smb_contracts.dart';
import '../models/share_recording.dart';
import '../models/smb_target.dart';
import 'active_recording_profile.dart';
import 'dart_smb2_connector.dart';
import 'smb_settings_store.dart';

final class ShareStreamServer {
  ShareStreamServer({
    required SmbConnector connector,
    required SmbUploadSettings store,
    required String Function() activeProfile,
    required Future<File> Function() stateFile,
  }) : _connector = connector,
       _store = store,
       _activeProfile = activeProfile,
       _stateFile = stateFile;

  static final instance = ShareStreamServer(
    connector: const DartSmb2Connector(),
    store: SmbSettingsStore(),
    activeProfile: activeRecordingProfileId,
    stateFile: () async =>
        File('${(await AppStorage.support()).path}/share_stream_v1.json'),
  );

  /// Bytes read from the share per network round trip.
  static const chunkBytes = 1024 * 1024;

  /// Files kept ready to play; older ones are closed and forgotten.
  static const _maxSources = 16;

  final SmbConnector _connector;
  final SmbUploadSettings _store;
  final String Function() _activeProfile;
  final Future<File> Function() _stateFile;

  Future<HttpServer>? _server;
  late List<int> _secret;
  final _sources = <String, _Source>{};

  /// A URL the player can stream [recording] from, for the active profile.
  /// Throws [StateError] when no share is set up.
  Future<Uri> urlFor(ShareRecording recording) async {
    final owner = _activeProfile();
    final target = await _store.readTarget();
    if (!target.enabled || !target.isComplete) {
      throw StateError('no share is set up');
    }
    final password = await _store.readPassword();
    final starting = _server ??= _start();
    final HttpServer server;
    try {
      server = await starting;
    } catch (_) {
      // Let the next play try to start again instead of failing for good.
      if (identical(_server, starting)) _server = null;
      rethrow;
    }
    // Another profile's sessions have no business staying open.
    for (final stale in [
      for (final entry in _sources.entries)
        if (entry.value.owner != owner) entry.key,
    ]) {
      await _sources.remove(stale)?.close();
    }
    final token = _tokenFor(owner, target.displayAddress, recording.path);
    _sources.remove(token)?.close();
    _sources[token] = _Source(owner, target, password, recording);
    while (_sources.length > _maxSources) {
      _sources.remove(_sources.keys.first)?.close();
    }
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['r', token, recording.name],
    );
  }

  /// Closes every open share session (the server itself keeps listening).
  Future<void> closeSessions() async {
    final sources = List.of(_sources.values);
    _sources.clear();
    for (final source in sources) {
      await source.close();
    }
  }

  /// Stops listening as well; the next [urlFor] starts again.
  Future<void> close() async {
    await closeSessions();
    final server = _server;
    _server = null;
    if (server != null) await (await server).close(force: true);
  }

  Future<HttpServer> _start() async {
    final file = await _stateFile();
    var port = 0;
    List<int>? secret;
    try {
      final saved = jsonDecode(await file.readAsString());
      if (saved is Map) {
        port = saved['port'] is int ? saved['port'] as int : 0;
        if (saved['secret'] is String) {
          secret = base64Decode(saved['secret'] as String);
        }
      }
    } catch (_) {
      // First start, or an unreadable file: pick new values.
    }
    _secret =
        secret ?? List<int>.generate(32, (_) => Random.secure().nextInt(256));
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      // The remembered port is taken: URLs (and resume points) change once.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'port': server.port, 'secret': base64Encode(_secret)}),
      );
    } catch (error) {
      debugPrint('Share stream: settings not saved (${error.runtimeType})');
    }
    final started = Future.value(server);
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object error) =>
          debugPrint('Share stream: server error (${error.runtimeType})'),
      // The OS can close a listening socket under the app; start afresh.
      onDone: () {
        if (identical(_server, started)) _server = null;
      },
    );
    _server = started;
    return server;
  }

  String _tokenFor(String owner, String address, String path) {
    final mac = Hmac(
      sha256,
      _secret,
    ).convert(utf8.encode('$owner\n$address\n$path'));
    return mac.toString().substring(0, 32);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    final source = segments.length >= 2 && segments[0] == 'r'
        ? _sources[segments[1]]
        : null;
    if (source == null) return _reply(response, HttpStatus.notFound);
    // Another profile took over since the URL was made.
    if (source.owner != _activeProfile()) {
      return _reply(response, HttpStatus.forbidden);
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      return _reply(response, HttpStatus.methodNotAllowed);
    }
    final SmbReader reader;
    try {
      reader = await source.acquire(_connector);
    } catch (error) {
      debugPrint('Share stream: open failed (${error.runtimeType})');
      return _reply(response, HttpStatus.badGateway);
    }
    try {
      await _send(request, response, reader, source.recording.name);
    } catch (error) {
      // Seeking players drop requests mid-body all the time; nothing to do.
      try {
        await response.close();
      } catch (_) {}
    } finally {
      source.release();
    }
  }

  Future<void> _send(
    HttpRequest request,
    HttpResponse response,
    SmbReader reader,
    String name,
  ) async {
    final size = reader.size;
    final range = parseByteRange(
      request.headers.value(HttpHeaders.rangeHeader),
      size,
    );
    response.headers
      ..contentType = ContentType.parse(_mimeType(name))
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (range == null &&
        request.headers.value(HttpHeaders.rangeHeader) != null &&
        size > 0) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
      return response.close();
    }
    final (start, end) = range ?? (0, size - 1);
    if (range != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }
    response.contentLength = size == 0 ? 0 : end - start + 1;
    if (request.method == 'HEAD' || size == 0) return response.close();
    var offset = start;
    while (offset <= end) {
      final data = await reader.read(offset, min(chunkBytes, end - offset + 1));
      if (data.isEmpty) break;
      response.add(data);
      await response.flush();
      offset += data.length;
    }
    await response.close();
  }

  static Future<void> _reply(HttpResponse response, int status) async {
    response.statusCode = status;
    await response.close();
  }

  static String _mimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp2t';
  }
}

/// `(start, end)` (inclusive) for a single `bytes=` range within [size];
/// null for no header, an unsatisfiable range or a multi-range request
/// (callers then send the whole file or 416).
@visibleForTesting
(int, int)? parseByteRange(String? header, int size) {
  if (header == null || size <= 0) return null;
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (match == null) return null;
  final first = match.group(1)!;
  final last = match.group(2)!;
  if (first.isEmpty) {
    // Suffix: the last N bytes.
    final count = int.tryParse(last);
    if (count == null || count == 0) return null;
    return (max(0, size - count), size - 1);
  }
  final start = int.parse(first);
  if (start >= size) return null;
  final end = last.isEmpty ? size - 1 : min(int.parse(last), size - 1);
  if (end < start) return null;
  return (start, end);
}

/// One playable share file: a session opened on first request and closed
/// after two idle minutes, shared by the player's concurrent range requests.
final class _Source {
  _Source(this.owner, this.target, this.password, this.recording);

  final String owner;
  final SmbTarget target;
  final String? password;
  final ShareRecording recording;

  Future<(SmbConnection, SmbReader)>? _open;
  int _users = 0;
  Timer? _idle;

  Future<SmbReader> acquire(SmbConnector connector) async {
    _idle?.cancel();
    // Counted before waiting: a request finishing meanwhile must not arm the
    // idle close under this one.
    _users++;
    final opening = _open ??= _connect(connector);
    try {
      final (_, reader) = await opening;
      return reader;
    } catch (_) {
      if (identical(_open, opening)) _open = null; // let the next try reconnect
      release();
      rethrow;
    }
  }

  void release() {
    _users--;
    _scheduleIdle();
  }

  void _scheduleIdle() {
    if (_users > 0) return;
    _idle?.cancel();
    _idle = Timer(const Duration(minutes: 2), () => unawaited(close()));
  }

  Future<(SmbConnection, SmbReader)> _connect(SmbConnector connector) async {
    final connection = await connector.connect(target, password);
    try {
      return (connection, await connection.openRead(recording.path));
    } catch (_) {
      await _quietly(connection.close);
      rethrow;
    }
  }

  Future<void> close() async {
    _idle?.cancel();
    final opening = _open;
    _open = null;
    if (opening == null) return;
    try {
      final (connection, reader) = await opening;
      await _quietly(reader.close);
      await _quietly(connection.close);
    } catch (_) {
      // It never opened: nothing to close.
    }
  }

  static Future<void> _quietly(Future<void> Function() body) async {
    try {
      await body();
    } catch (_) {}
  }
}
