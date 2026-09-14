import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

/// A file, rather than a base64 string, is the unit of bulk transport. HTTP
/// provides backpressure and packet recovery; independently authenticated
/// blocks bound the encryption working set even on low-memory receivers.
class RemoteTransferFile {
  const RemoteTransferFile({
    required this.file,
    required this.metadata,
    required this.sessionId,
    required this.sourceIp,
    required this.reportResult,
  });
  final File file;
  final Map<String, dynamic> metadata;
  final String sessionId;
  final String sourceIp;
  final void Function(Map<String, dynamic>) reportResult;
}

class RemoteTransferException implements Exception {
  const RemoteTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef RemoteTransferProgress = void Function(int completed, int total);

/// Receipt IDs survive connection retries. A dropped response never executes
/// the same request twice during a live receiving session. Receipt polling is
/// separate from import, so a slow disk or confirmation dialog is not mistaken
/// for a dead socket. Files are removed after their handler finishes.
class RemoteReliableTransfer {
  RemoteReliableTransfer({
    required this.directory,
    required this.receiveKey,
    required this.onReceive,
    this.runInRequestScope,
    this.onActivity,
    this.onReceiveProgress,
    this.onEvent,
    this.receiptMemoryLimit = 256,
    this.maxFileBytes = 16 * 1024 * 1024 * 1024,
    this.ioTimeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 250),
    this.receiptLifetime = const Duration(hours: 1),
    this.cleanupInterval = const Duration(minutes: 5),
  });

  static const int defaultPort = 5557;
  static const int blockBytes = 256 * 1024;
  static const int _maxHeaderBytes = 8192;
  static final AesGcm _aes = AesGcm.with256bits();
  final Directory directory;
  final Future<List<int>?> Function(String sessionId, String sourceIp)
  receiveKey;
  final Future<void> Function(RemoteTransferFile transfer) onReceive;
  final Future<void> Function(Future<void> Function() action)?
  runInRequestScope;
  final void Function(String id, bool active)? onActivity;
  final RemoteTransferProgress? onReceiveProgress;
  final void Function(String event, Map<String, Object?> fields)? onEvent;
  final int maxFileBytes;
  final int receiptMemoryLimit;
  final Duration ioTimeout;
  final Duration pollInterval;
  final Duration receiptLifetime;
  final Duration cleanupInterval;
  final Map<String, _Receipt> _receipts = {};
  final Set<Future<void>> _work = {};
  final Set<Future<void>> _requests = {};
  HttpServer? _server;
  final HttpClient _client = HttpClient();
  bool _closed = false;
  Timer? _cleanupTimer;
  Future<void>? _cleanupPending;

  int get port => _server!.port;

  Future<void> start({int port = defaultPort}) async {
    if (_server != null) return;
    await directory.create(recursive: true);
    await _cleanupExpiredFiles();
    _client.connectionTimeout = ioTimeout;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen((request) {
      late Future<void> pending;
      pending =
          (runInRequestScope == null
                  ? _handle(request)
                  : runInRequestScope!(() => _handle(request)))
              .whenComplete(() => _requests.remove(pending));
      _requests.add(pending);
    });
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) {
      // Do not race an admitted request between its credential check and file
      // open. New requests wait for this sweep before looking up receipts.
      if (_requests.isEmpty && _cleanupPending == null) {
        _cleanupPending = _cleanupExpiredFiles().whenComplete(
          () => _cleanupPending = null,
        );
      }
    });
  }

  Future<void> close() async {
    _closed = true;
    _cleanupTimer?.cancel();
    await _cleanupPending;
    _client.close(force: true);
    await _server?.close(force: true);
    _server = null;
    await Future.wait(_requests.toList());
    await Future.wait(_work.toList());
    // An admitted import owns its file until completion. Do not delete it
    // underneath a profile restore when roles change as part of that restore.
  }

  static String newId() {
    final random = Random.secure();
    return base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  Future<Map<String, dynamic>?> send({
    required String host,
    int port = defaultPort,
    required String sessionId,
    required List<int> key,
    required File file,
    required Map<String, dynamic> metadata,
    Future<void> Function()? authorizationBarrier,
    RemoteTransferProgress? onProgress,
    bool waitForProcessing = true,
    Duration completionTimeout = const Duration(minutes: 30),
  }) async {
    if (_closed) {
      throw const RemoteTransferException('Transfer service stopped');
    }
    final length = await file.length();
    if (length > maxFileBytes) {
      throw const RemoteTransferException(
        'Transfer exceeds the disk size limit',
      );
    }
    final hash = (await digest.sha256.bind(file.openRead()).first).toString();
    final id = newId();
    final elapsed = Stopwatch()..start();
    _event('send_start', id, {'bytes': length});
    final header = base64UrlEncode(
      utf8.encode(
        jsonEncode({
          'sid': sessionId,
          'bytes': length,
          'sha256': hash,
          'metadata': metadata,
        }),
      ),
    );
    if (header.length > _maxHeaderBytes) {
      throw const RemoteTransferException('Transfer metadata is too large');
    }
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: '/remote/v1/$id',
    );
    final transferKey = _key(key, id);
    final deadline = DateTime.now().add(completionTimeout);
    var failures = 0;
    // Probe receiver capacity before committing a potentially large body.
    var uploaded = true;
    var resumeAt = 0;
    while (!_closed && DateTime.now().isBefore(deadline)) {
      await authorizationBarrier?.call();
      HttpClientRequest? pendingRequest;
      try {
        final method = uploaded ? 'GET' : 'PUT';
        final request = await _client.openUrl(method, uri).timeout(ioTimeout);
        pendingRequest = request;
        request.headers.set('x-debrify-meta', header);
        request.headers.set('x-debrify-offset', resumeAt.toString());
        request.headers.set(
          'x-debrify-auth',
          _auth(key, '$method:$resumeAt', id, header),
        );
        if (!uploaded) {
          request.contentLength =
              (length - resumeAt) +
              (((length - resumeAt) + blockBytes - 1) ~/ blockBytes) * 20;
          final source = await file.open();
          await source.setPosition(resumeAt);
          try {
            var sent = resumeAt;
            var index = resumeAt ~/ blockBytes;
            while (sent < length) {
              if (_closed) {
                throw const RemoteTransferException('Transfer stopped');
              }
              await authorizationBarrier?.call();
              final bytes = await source.read(min(blockBytes, length - sent));
              if (bytes.isEmpty) {
                throw const RemoteTransferException('Source file changed');
              }
              final box = await _aes.encrypt(
                bytes,
                secretKey: SecretKey(transferKey),
                nonce: _nonce(index++),
              );
              request.add(
                (ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List(),
              );
              request.add(box.cipherText);
              request.add(box.mac.bytes);
              await request.flush().timeout(ioTimeout);
              sent += bytes.length;
              onProgress?.call(sent, length);
            }
          } finally {
            await source.close();
          }
        }
        final response = await request.close().timeout(ioTimeout);
        final body = await _smallResponse(response);
        pendingRequest = null;
        if (response.statusCode == HttpStatus.unauthorized) {
          throw const RemoteTransferException(
            'Pairing expired. Reconnect and retry.',
          );
        }
        if (response.statusCode == HttpStatus.notFound) {
          uploaded = false;
          resumeAt = 0;
          failures = 0;
          continue;
        } else if (response.statusCode == HttpStatus.conflict ||
            response.statusCode == HttpStatus.serviceUnavailable) {
          // Another admitted operation owns the receiver. Keep this request
          // unchanged; retrying it cannot duplicate an earlier application.
          uploaded = true;
          failures = 0;
        } else if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.accepted) {
          throw const RemoteTransferException(
            'Receiving device rejected the transfer',
          );
        } else {
          if (!_equal(
            response.headers.value('x-debrify-receipt') ?? '',
            _auth(key, 'reply:${response.statusCode}', id, body),
          )) {
            throw const RemoteTransferException(
              'Could not verify the receiving device response',
            );
          }
          final state = jsonDecode(body) as Map<String, dynamic>;
          if (state['phase'] == 'complete' ||
              (!waitForProcessing && state['phase'] == 'processing')) {
            _event('send_complete', id, {
              'bytes': length,
              'elapsedMs': elapsed.elapsedMilliseconds,
            });
            return state['result'] as Map<String, dynamic>?;
          }
          if (state['phase'] == 'failed') {
            throw const RemoteTransferException(
              'The receiving device could not apply the transfer',
            );
          }
          if (state['phase'] == 'partial') {
            final offset = state['received'];
            if (offset is! int ||
                offset < 0 ||
                offset > length ||
                (offset != length && offset % blockBytes != 0)) {
              throw const RemoteTransferException('Invalid resume receipt');
            }
            resumeAt = offset;
            uploaded = false;
            _event('send_resume', id, {'offset': offset, 'bytes': length});
          } else {
            uploaded = true;
          }
          failures = 0;
        }
      } on RemoteTransferException {
        rethrow;
      } on IOException {
        _event('send_retry', id, {
          'attempt': failures + 1,
          'reason': 'network',
        });
        if (++failures > 5) rethrow;
        // Probe the receipt before resending a body whose reply may have been
        // lost. A missing receipt triggers a fresh upload with the SAME ID.
        uploaded = true;
      } on TimeoutException {
        _event('send_retry', id, {
          'attempt': failures + 1,
          'reason': 'timeout',
        });
        if (++failures > 5) rethrow;
        uploaded = true;
      } finally {
        pendingRequest?.abort();
      }
      await Future<void>.delayed(
        failures == 0 ? pollInterval : const Duration(seconds: 1),
      );
    }
    throw const RemoteTransferException(
      'Transfer interrupted. Reconnect and retry.',
    );
  }

  Future<String> _smallResponse(HttpClientResponse response) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(ioTimeout)) {
      if (bytes.length + chunk.length > _maxHeaderBytes) {
        throw const RemoteTransferException('Invalid transfer receipt');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  Future<void> _handle(HttpRequest request) async {
    File? partial;
    _Receipt? admitted;
    String? admittedId;
    try {
      await _cleanupPending;
      final segments = request.uri.pathSegments;
      if (_closed ||
          segments.length != 3 ||
          segments[0] != 'remote' ||
          segments[1] != 'v1' ||
          !RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(segments[2]) ||
          (request.method != 'PUT' && request.method != 'GET')) {
        await _reply(request, HttpStatus.notFound);
        return;
      }
      final id = segments[2];
      final header = request.headers.value('x-debrify-meta') ?? '';
      if (header.isEmpty || header.length > _maxHeaderBytes) {
        await _reply(request, HttpStatus.badRequest);
        return;
      }
      final parsed =
          jsonDecode(utf8.decode(base64Url.decode(header)))
              as Map<String, dynamic>;
      final offset = int.tryParse(
        request.headers.value('x-debrify-offset') ?? '0',
      );
      if (offset == null || offset < 0) {
        await _reply(request, HttpStatus.badRequest);
        return;
      }
      final sid = parsed['sid'] as String;
      final sourceIp = request.connectionInfo!.remoteAddress.address;
      // A completed receipt remains readable after an import switches the
      // active profile and retires its session. Only its original signed
      // request can read it; no new command can use this retained key.
      _prune();
      final cached = _receipts[id] ?? await _loadReceipt(id);
      final key =
          cached != null &&
              cached.header == header &&
              cached.phase == 'complete'
          ? cached.key
          : await receiveKey(sid, sourceIp);
      if (key == null ||
          !_equal(
            request.headers.value('x-debrify-auth') ?? '',
            _auth(key, '${request.method}:$offset', id, header),
          )) {
        await _reply(request, HttpStatus.unauthorized);
        return;
      }
      // Receipt loading and authentication both yield. Another request may
      // have claimed this ID while they ran. Recheck the live receipt here;
      // keep the new-upload path synchronous through _receipts[id] assignment
      // so only one request can own the partial file and invoke the importer.
      final existing = _receipts[id] ?? cached;
      if (existing != null &&
          !(existing.phase == 'partial' &&
              request.method == 'PUT' &&
              existing.header == header)) {
        if (existing.header != header) {
          await _reply(request, HttpStatus.conflict);
        } else {
          // Discard a replayed upload in bounded chunks, never buffer it.
          if (request.method == 'PUT') {
            await request.drain<void>().timeout(ioTimeout);
          }
          await _reply(
            request,
            HttpStatus.ok,
            existing.phase,
            existing.result,
            existing.received,
          );
        }
        return;
      }
      if (request.method == 'GET') {
        final length = parsed['bytes'];
        if (length is! int || length < 0 || length > maxFileBytes) {
          await _reply(request, HttpStatus.badRequest);
          return;
        }
        await _reply(
          request,
          _capacityHeld(length)
              ? HttpStatus.serviceUnavailable
              : HttpStatus.notFound,
        );
        return;
      }
      final length = parsed['bytes'] as int;
      final expectedHash = parsed['sha256'] as String;
      final metadata = parsed['metadata'] as Map<String, dynamic>;
      if (length < 0 ||
          length > maxFileBytes ||
          offset != (existing?.received ?? 0) ||
          offset > length ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash) ||
          request.contentLength !=
              (length - offset) +
                  (((length - offset) + blockBytes - 1) ~/ blockBytes) * 20) {
        await _reply(request, HttpStatus.badRequest);
        return;
      }
      // Only one large file/import at a time. Tiny outcome messages can still
      // arrive while this device is itself sending or importing a package.
      if (_capacityHeld(length, known: existing != null)) {
        await _reply(request, HttpStatus.serviceUnavailable);
        return;
      }
      final receipt = existing ?? _Receipt(header, key);
      receipt.phase = 'receiving';
      receipt.total = length;
      receipt.active = true;
      _receipts[id] = receipt;
      admitted = receipt;
      admittedId = id;
      onActivity?.call(id, true);
      _event('receive_start', id, {'bytes': length});
      partial = File('${directory.path}/$id.part');
      if (offset > 0) {
        final prefix = await partial.open(mode: FileMode.append);
        try {
          await prefix.truncate(offset);
        } finally {
          await prefix.close();
        }
      }
      final sink = partial.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      final reader = _BlockReader(request.timeout(ioTimeout));
      var received = offset;
      var index = offset ~/ blockBytes;
      final transferKey = _key(key, id);
      try {
        while (received < length) {
          final size = ByteData.sublistView(await reader.read(4)).getUint32(0);
          if (size != min(blockBytes, length - received)) {
            throw const FormatException('Invalid transfer block');
          }
          final bytes = await reader.read(size + 16);
          final plaintext = await _aes.decrypt(
            SecretBox(
              Uint8List.sublistView(bytes, 0, size),
              nonce: _nonce(index++),
              mac: Mac(Uint8List.sublistView(bytes, size)),
            ),
            secretKey: SecretKey(transferKey),
          );
          // Refresh only after authenticating a block. This also rechecks
          // revocation and absolute session age throughout long uploads.
          final currentKey = await receiveKey(sid, sourceIp);
          if (currentKey == null ||
              !_equal(base64Encode(currentKey), base64Encode(key))) {
            throw const RemoteTransferException('Pairing expired');
          }
          sink.add(plaintext);
          await sink.flush();
          received += plaintext.length;
          receipt.received = received;
          onReceiveProgress?.call(received, length);
        }
        await reader.finish();
      } finally {
        await sink.close();
        await reader.close();
      }
      if ((await digest.sha256.bind(partial.openRead()).first).toString() !=
          expectedHash) {
        throw const FormatException('Transfer checksum mismatch');
      }
      if (await receiveKey(sid, sourceIp) == null) {
        throw const RemoteTransferException('Pairing expired');
      }
      receipt.phase = 'processing';
      _event('receive_complete', id, {'bytes': length});
      final file = partial;
      partial = null;
      late Future<void> work;
      work = () async {
        try {
          await onReceive(
            RemoteTransferFile(
              file: file,
              metadata: metadata,
              sessionId: sid,
              sourceIp: sourceIp,
              reportResult: (result) {
                receipt.result ??= result;
                receipt.phase = 'complete';
              },
            ),
          );
          receipt.phase = 'complete';
        } catch (_) {
          if (receipt.result == null) receipt.phase = 'failed';
        } finally {
          receipt.finishedAt = DateTime.now();
          // Keep completed receipts on disk when the small memory cache turns
          // over. Large channel selections must neither fill a fixed receipt
          // limit nor lose deduplication for a delayed retry.
          try {
            await File('${directory.path}/$id.receipt').writeAsString(
              jsonEncode({
                'header': receipt.header,
                'key': base64Encode(receipt.key),
                'phase': receipt.phase,
                'result': receipt.result,
                'finishedAt': receipt.finishedAt!.toUtc().toIso8601String(),
              }),
              flush: true,
            );
            receipt.journaled = true;
          } catch (_) {
            // Keep this receipt in memory if its journal could not be written.
            receipt.journaled = false;
          }
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
          receipt.active = false;
          onActivity?.call(id, false);
          _event('apply_finished', id, {'phase': receipt.phase});
        }
      }().whenComplete(() => _work.remove(work));
      _work.add(work);
      await _reply(request, HttpStatus.accepted, receipt.phase, receipt.result);
    } catch (_) {
      final canResume =
          partial != null &&
          admitted != null &&
          admitted.received > 0 &&
          admitted.received < admitted.total;
      if (partial != null && !canResume) {
        try {
          if (await partial.exists()) await partial.delete();
        } catch (_) {}
      }
      if (admitted?.phase == 'receiving') {
        if (canResume) {
          admitted.phase = 'partial';
          admitted.active = false;
          admitted.finishedAt = DateTime.now();
        } else {
          _receipts.remove(admittedId);
        }
        if (admittedId != null) {
          onActivity?.call(admittedId, false);
          _event('receive_failed', admittedId, {});
        }
      }
      try {
        await _reply(
          request,
          canResume ? HttpStatus.accepted : HttpStatus.badRequest,
          canResume ? 'partial' : null,
          null,
          admitted?.received,
        );
      } catch (_) {}
    }
  }

  Future<_Receipt?> _loadReceipt(String id) async {
    final file = File('${directory.path}/$id.receipt');
    if (!await file.exists()) return null;
    try {
      if (await file.length() > 32 * 1024) return null;
      final value =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final finished = DateTime.parse(value['finishedAt'] as String);
      if (DateTime.now().difference(finished) > receiptLifetime) {
        await file.delete();
        return null;
      }
      return _Receipt(
          value['header'] as String,
          base64Decode(value['key'] as String),
        )
        ..phase = value['phase'] as String
        ..result = value['result'] as Map<String, dynamic>?
        ..active = false
        ..journaled = true
        ..finishedAt = finished;
    } catch (_) {
      return null;
    }
  }

  bool _capacityHeld(int length, {bool known = false}) {
    final active = _receipts.values.where((r) => r.active).length;
    return (length > 64 * 1024 && active > 0) ||
        active >= 8 ||
        (!known && _receipts.length >= receiptMemoryLimit);
  }

  void _event(String event, String id, Map<String, Object?> fields) {
    final trace = digest.sha256
        .convert(utf8.encode(id))
        .toString()
        .substring(0, 12);
    onEvent?.call('reliable_$event', {'trace': trace, ...fields});
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(receiptLifetime);
    _receipts.removeWhere(
      (_, receipt) =>
          !receipt.active && (receipt.finishedAt?.isBefore(cutoff) ?? false),
    );
    while (_receipts.length >= receiptMemoryLimit) {
      String? removable;
      for (final entry in _receipts.entries) {
        if (!entry.value.active && entry.value.journaled) {
          removable = entry.key;
          break;
        }
      }
      if (removable == null) break;
      _receipts.remove(removable);
    }
  }

  Future<void> _cleanupExpiredFiles() async {
    final cutoff = DateTime.now().subtract(receiptLifetime);
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final match = RegExp(
          r'^([A-Za-z0-9_-]{32})\.(part|receipt)$',
        ).firstMatch(name);
        if (match == null) continue;
        final id = match[1]!;
        final receipt = _receipts[id];
        if (receipt?.active ?? false) continue;
        final modified = receipt?.finishedAt ?? (await entity.stat()).modified;
        if (!modified.isBefore(cutoff)) continue;
        await entity.delete();
        _receipts.remove(id);
      }
    } on FileSystemException {
      // A best-effort sweep must not prevent pairing or interrupt transfers.
    }
  }

  Future<void> _reply(
    HttpRequest request,
    int status, [
    String? phase,
    Map<String, dynamic>? result,
    int? received,
  ]) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    final body = jsonEncode({
      'phase': phase,
      if (result != null) 'result': result,
      if (received != null) 'received': received,
    });
    if (status == HttpStatus.ok || status == HttpStatus.accepted) {
      final id = request.uri.pathSegments.last;
      final receipt = _receipts[id] ?? await _loadReceipt(id);
      if (receipt != null) {
        request.response.headers.set(
          'x-debrify-receipt',
          _auth(receipt.key, 'reply:$status', id, body),
        );
      }
    }
    request.response.write(body);
    await request.response.close();
  }

  static List<int> _key(List<int> key, String id) => digest.Hmac(
    digest.sha256,
    key,
  ).convert(utf8.encode('debrify-file-v1:$id')).bytes;
  static String _auth(List<int> key, String method, String id, String header) =>
      digest.Hmac(
        digest.sha256,
        key,
      ).convert(utf8.encode('$method:$id:$header')).toString();
  static Uint8List _nonce(int index) =>
      (ByteData(12)..setUint32(8, index)).buffer.asUint8List();
  static bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class _Receipt {
  _Receipt(this.header, this.key);
  final String header;
  final List<int> key;
  Map<String, dynamic>? result;
  bool active = true;
  bool journaled = false;
  int received = 0;
  int total = 0;
  String phase = 'receiving';
  DateTime? finishedAt;
}

/// StreamIterator pauses its upstream subscription between reads. Never join
/// the socket or hold all encrypted blocks while waiting for slow TV storage.
class _BlockReader {
  _BlockReader(Stream<List<int>> stream) : iterator = StreamIterator(stream);
  final StreamIterator<List<int>> iterator;
  List<int> current = const [];
  int offset = 0;
  Future<Uint8List> read(int count) async {
    final result = Uint8List(count);
    var written = 0;
    while (written < count) {
      if (offset == current.length) {
        if (!await iterator.moveNext()) {
          throw const FormatException('Truncated transfer');
        }
        current = iterator.current;
        offset = 0;
      }
      final available = min(count - written, current.length - offset);
      result.setRange(written, written + available, current, offset);
      written += available;
      offset += available;
    }
    return result;
  }

  Future<void> finish() async {
    if (offset != current.length || await iterator.moveNext()) {
      throw const FormatException('Trailing transfer data');
    }
  }

  Future<void> close() => iterator.cancel();
}
