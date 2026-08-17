import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../utils/app_storage.dart';

/// Cross-platform desktop primary-instance lock and authenticated loopback
/// argument forwarding. The lock is acquired before any profile registry is
/// opened and remains held for the process lifetime.
class DesktopSingleInstance {
  DesktopSingleInstance._();

  static RandomAccessFile? _lockHandle;
  static ServerSocket? _server;
  static final StreamController<List<String>> _forwarded =
      StreamController<List<String>>.broadcast();
  static final List<List<String>> _pending = <List<String>>[];
  static final Set<String> _acceptedForwardIds = <String>{};
  static final List<String> _acceptedForwardOrder = <String>[];

  static Stream<List<String>> get forwardedArguments => _forwarded.stream;

  /// Exposed for diagnostics/tests; reading it also makes the lifetime-held
  /// lock an explicit part of this service's state rather than dead storage.
  static bool get holdsPrimaryLock => _lockHandle != null;

  static List<List<String>> takePendingArguments() {
    final result = List<List<String>>.unmodifiable(_pending);
    _pending.clear();
    return result;
  }

  /// Returns false only in the secondary process, after best-effort forwarding
  /// to the authenticated primary endpoint.
  static Future<bool> acquire(List<String> launchArguments) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return true;
    }
    final support = await AppStorage.support();
    await support.create(recursive: true);
    final lockFile = File(p.join(support.path, '.debrify-primary.lock'));
    final endpointFile = File(
      p.join(support.path, '.debrify-primary-endpoint-v1.json'),
    );
    final handle = await lockFile.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      _lockHandle = handle;
    } on FileSystemException {
      await handle.close();
      final delivered = await _forwardToPrimary(endpointFile, launchArguments);
      if (!delivered) {
        throw StateError(
          'Could not deliver launch request to primary instance',
        );
      }
      return false;
    }

    final secret = base64UrlEncode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final temp = File('${endpointFile.path}.tmp');
    await temp.writeAsString(
      jsonEncode(<String, Object>{
        'version': 1,
        'port': _server!.port,
        'secret': secret,
      }),
      flush: true,
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', temp.path]);
    }
    // The lock proves there is no live primary. Windows rename does not
    // replace a stale destination, so remove only this exact endpoint after
    // the new endpoint has been fully flushed.
    if (Platform.isWindows && await endpointFile.exists()) {
      await endpointFile.delete();
    }
    await temp.rename(endpointFile.path);

    _server!.listen((socket) => _accept(socket, secret));
    if (launchArguments.isNotEmpty) {
      _pending.add(launchArguments.take(32).toList(growable: false));
    }
    return true;
  }

  static Future<void> _accept(Socket socket, String secret) async {
    try {
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2));
      final value = jsonDecode(line);
      if (value is! Map || value['secret'] != secret) return;
      final requestId = value['requestId'];
      if (requestId is! String ||
          requestId.length < 16 ||
          requestId.length > 128) {
        return;
      }
      final raw = value['arguments'];
      if (raw is! List || raw.length > 32) return;
      final arguments = raw
          .whereType<String>()
          .where((item) => item.length <= 16 * 1024)
          .toList(growable: false);
      if (_acceptedForwardIds.add(requestId)) {
        _acceptedForwardOrder.add(requestId);
        while (_acceptedForwardOrder.length > 256) {
          _acceptedForwardIds.remove(_acceptedForwardOrder.removeAt(0));
        }
        if (arguments.isNotEmpty) {
          if (_forwarded.hasListener) {
            _forwarded.add(arguments);
          } else if (_pending.length < 32) {
            _pending.add(arguments);
          }
        }
      }
      socket.write('ok:$requestId\n');
      await socket.flush();
    } catch (_) {
      // Invalid/local races are intentionally ignored.
    } finally {
      await socket.close();
    }
  }

  static Future<bool> _forwardToPrimary(
    File endpointFile,
    List<String> arguments,
  ) async {
    final requestId = base64UrlEncode(
      List<int>.generate(24, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      Socket? socket;
      try {
        final decoded = jsonDecode(await endpointFile.readAsString());
        if (decoded is! Map || decoded['version'] != 1) {
          throw const FormatException('Invalid primary endpoint');
        }
        final port = decoded['port'];
        final secret = decoded['secret'];
        if (port is! int || secret is! String) {
          throw const FormatException('Invalid primary endpoint');
        }
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 750),
        );
        socket.writeln(
          jsonEncode(<String, Object>{
            'secret': secret,
            'requestId': requestId,
            'arguments': arguments.take(32).toList(growable: false),
          }),
        );
        await socket.flush();
        final acknowledgement = await socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(milliseconds: 750));
        if (acknowledgement == 'ok:$requestId') return true;
      } catch (_) {
        // The primary may hold its lock just before publishing the endpoint.
      } finally {
        await socket?.close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }
}
