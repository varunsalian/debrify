import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as digest;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:debrify/services/remote_control/remote_reliable_transfer.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  final key = List<int>.generate(32, (i) => i);
  final services = <RemoteReliableTransfer>[];

  Future<RemoteReliableTransfer> service(
    Future<void> Function(RemoteTransferFile) receive, {
    Duration timeout = const Duration(seconds: 5),
    int receiptLimit = 256,
  }) async {
    final instance = RemoteReliableTransfer(
      directory: Directory('${root.path}/service-${services.length}'),
      receiveKey: (sid, ip) async => sid == 'paired' ? key : null,
      onReceive: receive,
      ioTimeout: timeout,
      receiptMemoryLimit: receiptLimit,
      pollInterval: const Duration(milliseconds: 10),
    );
    services.add(instance);
    await instance.start(port: 0);
    return instance;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('remote-reliable-test-');
  });
  tearDown(() async {
    for (final s in services) {
      await s.close();
    }
    services.clear();
    if (await root.exists()) await root.delete(recursive: true);
  });

  for (final expires in [false, true]) {
    test(
      expires
          ? 'active uploads still enforce maximum session age'
          : 'authenticated blocks keep a receiving session alive beyond idle timeout',
      () async {
        var now = DateTime.utc(2026);
        final manager = RemoteSessionManager(
          loadStaticKeyPair: RemoteSessionCrypto.x25519.newKeyPair,
          deviceName: () => 'Receiver',
          now: () => now,
        );
        final session = RemoteSession(
          sid: Uint8List(8),
          role: RemoteSessionRole.receiver,
          keys: SessionKeys(c2s: key, s2c: key, conf: key, sas: key),
          peerStaticKey: key,
          peerFingerprint: 'sender',
          peerName: 'Sender',
          sasCode: '123456',
          establishedAt: now,
        );
        manager.sessions[session.sidB64] = session;
        if (expires) {
          now = now.add(kSessionMaxAge - const Duration(minutes: 3));
          session.lastUsed = now;
        }
        var imports = 0;
        final receiver = RemoteReliableTransfer(
          directory: Directory('${root.path}/long-upload'),
          receiveKey: (sid, _) async {
            manager.tick();
            final active = manager.sessionBySid(sid);
            if (active == null) return null;
            active.lastUsed = now;
            return active.recvKey;
          },
          onReceive: (_) async {
            imports++;
          },
          onReceiveProgress: (_, _) {
            now = now.add(const Duration(minutes: 6));
            manager.tick();
          },
        );
        services.add(receiver);
        await receiver.start(port: 0);
        final sender = await service((_) async {});
        final file = await File('${root.path}/long-file').writeAsBytes(
          List<int>.filled(4 * RemoteReliableTransfer.blockBytes, 42),
        );
        final sending = sender.send(
          host: '127.0.0.1',
          port: receiver.port,
          sessionId: session.sidB64,
          key: key,
          file: file,
          metadata: {},
        );
        if (expires) {
          await expectLater(sending, throwsA(isA<RemoteTransferException>()));
          expect(imports, 0);
        } else {
          await sending;
          expect(imports, 1);
          expect(
            now.difference(session.establishedAt),
            greaterThan(kSessionIdleTimeout),
          );
        }
      },
    );
  }

  test(
    'a busy receiver queues a second large transfer without uploading it repeatedly',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var imports = 0;
      final receiver = await service((transfer) async {
        imports++;
        if (imports == 1) {
          entered.complete();
          await release.future;
        }
      });
      final sender = await service((_) async {});
      final source = await File(
        '${root.path}/large-queued',
      ).writeAsBytes(List<int>.filled(2 * 1024 * 1024, 42));
      final first = sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: source,
        metadata: {},
      );
      await entered.future;
      var progressEvents = 0;
      final second = sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: source,
        metadata: {},
        onProgress: (_, _) => progressEvents++,
      );
      final both = Future.wait([first, second]);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(progressEvents, 0);
        expect(imports, 1);
      } finally {
        release.complete();
        await both;
      }
      expect(imports, 2);
    },
  );

  test(
    'expired transport files are pruned without touching active imports',
    () async {
      final directory = await Directory('${root.path}/expiry').create();
      final stale = File('${directory.path}/${'a' * 32}.part');
      await stale.writeAsString('abandoned');
      await stale.setLastModified(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final unrelated = await File(
        '${directory.path}/unrelated',
      ).writeAsString('keep');
      final entered = Completer<File>();
      final release = Completer<void>();
      final receiver = RemoteReliableTransfer(
        directory: directory,
        receiveKey: (_, _) async => key,
        onReceive: (transfer) async {
          entered.complete(transfer.file);
          await release.future;
        },
        receiptLifetime: const Duration(milliseconds: 100),
        cleanupInterval: const Duration(milliseconds: 20),
      );
      services.add(receiver);
      await receiver.start(port: 0);
      expect(await stale.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
      final sender = await service((_) async {});
      final source = await File('${root.path}/source').writeAsString('payload');
      final sending = sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: source,
        metadata: {},
      );
      try {
        final activeFile = await entered.future;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(await activeFile.readAsString(), 'payload');
      } finally {
        release.complete();
      }
      await sending;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(await directory.list().toList(), hasLength(1));
      expect(await unrelated.exists(), isTrue);
    },
  );

  test(
    'large binary file arrives intact with bounded progress blocks',
    () async {
      final random = Random(7);
      final block = List<int>.generate(64 * 1024, (_) => random.nextInt(256));
      final source = File('${root.path}/large');
      final sink = source.openWrite();
      for (var i = 0; i < 128; i++) {
        sink.add(block);
      }
      await sink.close();
      var received = 0;
      final receiver = await service((transfer) async {
        expect(transfer.metadata, {'kind': 'large-channel-set'});
        expect(await transfer.file.length(), 8 * 1024 * 1024);
        var length = 0;
        await for (final bytes in transfer.file.openRead()) {
          for (var i = 0; i < bytes.length; i++) {
            if (bytes[i] != block[(length + i) % block.length]) {
              fail('Corrupt byte');
            }
          }
          length += bytes.length;
        }
        received++;
      });
      final sender = await service((_) async {});
      var previous = 0;
      await sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: source,
        metadata: {'kind': 'large-channel-set'},
        onProgress: (done, total) {
          expect(
            done - previous,
            lessThanOrEqualTo(RemoteReliableTransfer.blockBytes),
          );
          expect(total, 8 * 1024 * 1024);
          previous = done;
        },
      );
      expect(received, 1);
      expect(previous, 8 * 1024 * 1024);
      expect(
        (await receiver.directory.list().toList()).where(
          (f) => f.path.endsWith('.part'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'completed result remains readable after profile handoff retires pairing',
    () async {
      var paired = true;
      var imports = 0;
      final receiver = RemoteReliableTransfer(
        directory: Directory('${root.path}/handoff'),
        receiveKey: (_, _) async => paired ? key : null,
        onReceive: (transfer) async {
          imports++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          transfer.reportResult({'ok': true, 'profiles': 2});
          paired = false;
        },
      );
      services.add(receiver);
      await receiver.start(port: 0);
      final sender = await service((_) async {});
      final source = await File(
        '${root.path}/graph',
      ).writeAsString('synthetic graph');
      final result = await sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: source,
        metadata: {},
      );
      expect(result, {'ok': true, 'profiles': 2});
      expect(imports, 1);
      await expectLater(
        sender.send(
          host: '127.0.0.1',
          port: receiver.port,
          sessionId: 'paired',
          key: key,
          file: source,
          metadata: {},
        ),
        throwsA(isA<RemoteTransferException>()),
      );
      expect(imports, 1);
    },
  );

  for (final conflicting in [false, true]) {
    test(
      conflicting
          ? 'concurrent transfer ID with different metadata is rejected'
          : 'concurrent replay is admitted once while the import is active',
      () async {
        final bothAuthenticating = Completer<void>();
        final finishImport = Completer<void>();
        var admissions = 0;
        var imports = 0;
        final receiver = RemoteReliableTransfer(
          directory: Directory('${root.path}/concurrent-receiver'),
          receiveKey: (sid, ip) async {
            // Hold both requests after their asynchronous receipt lookup.
            // Neither may register its receipt until both captured a miss.
            if (++admissions <= 2) {
              if (admissions == 2) bothAuthenticating.complete();
              await bothAuthenticating.future;
            }
            return key;
          },
          onReceive: (transfer) async {
            imports++;
            expect(await transfer.file.readAsBytes(), isEmpty);
            await finishImport.future;
          },
        );
        services.add(receiver);
        await receiver.start(port: 0);
        final client = HttpClient();
        const id = '0123456789abcdef0123456789abcdef';
        Future<int> upload(int index) async {
          final header = base64Url.encode(
            utf8.encode(
              jsonEncode({
                'sid': 'paired',
                'bytes': 0,
                'sha256': digest.sha256.convert([]).toString(),
                'metadata': {'variant': conflicting ? index : 0},
              }),
            ),
          );
          final request = await client.putUrl(
            Uri.parse('http://127.0.0.1:${receiver.port}/remote/v1/$id'),
          );
          request.headers.set('x-debrify-meta', header);
          request.headers.set(
            'x-debrify-auth',
            digest.Hmac(
              digest.sha256,
              key,
            ).convert(utf8.encode('PUT:0:$id:$header')).toString(),
          );
          request.contentLength = 0;
          final response = await request.close();
          await response.drain<void>();
          return response.statusCode;
        }

        try {
          final statuses = await Future.wait([
            upload(0),
            upload(1),
          ]).timeout(const Duration(seconds: 5));
          expect(
            statuses,
            unorderedEquals([
              HttpStatus.accepted,
              conflicting ? HttpStatus.conflict : HttpStatus.ok,
            ]),
          );
          expect(imports, 1);
        } finally {
          finishImport.complete();
          client.close(force: true);
        }
      },
    );
  }

  test('lost upload response polls receipt without importing twice', () async {
    var imports = 0;
    final receiver = await service((_) async {
      imports++;
    });
    final sender = await service((_) async {});
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await proxy.close(force: true);
    });
    var dropped = false;
    proxy.listen((request) async {
      final upstream = await client.openUrl(
        request.method,
        Uri.parse('http://127.0.0.1:${receiver.port}${request.uri.path}'),
      );
      request.headers.forEach((name, values) {
        if (name != HttpHeaders.hostHeader) upstream.headers.set(name, values);
      });
      await upstream.addStream(request);
      final response = await upstream.close();
      if (request.method == 'PUT' && !dropped) {
        dropped = true;
        await response.drain<void>();
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
      } else {
        request.response.statusCode = response.statusCode;
        final stamp = response.headers.value('x-debrify-receipt');
        if (stamp != null) {
          request.response.headers.set('x-debrify-receipt', stamp);
        }
        await request.response.addStream(response);
        await request.response.close();
      }
    });
    final source = await File('${root.path}/small').writeAsString('transfer');
    await sender.send(
      host: '127.0.0.1',
      port: proxy.port,
      sessionId: 'paired',
      key: key,
      file: source,
      metadata: {},
    );
    expect(dropped, isTrue);
    expect(imports, 1);
  });

  test(
    'slow import remains pending across many successful receipt polls',
    () async {
      var finished = false;
      final receiver = await service((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        finished = true;
      });
      final sender = await service(
        (_) async {},
        timeout: const Duration(milliseconds: 150),
      );
      final source = await File('${root.path}/small').writeAsString('transfer');
      await sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: source,
        metadata: {},
      );
      expect(finished, isTrue);
    },
  );

  test('connection loss during upload resumes verified blocks', () async {
    var imports = 0;
    final payload = List<int>.generate(2 * 1024 * 1024, (i) => i % 251);
    final receiver = await service((transfer) async {
      expect(await transfer.file.readAsBytes(), payload);
      imports++;
    });
    final sender = await service((_) async {});
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await proxy.close(force: true);
    });
    var dropped = false;
    var resumed = false;
    proxy.listen((request) async {
      final upstream = await client.openUrl(
        request.method,
        Uri.parse('http://127.0.0.1:${receiver.port}${request.uri.path}'),
      );
      request.headers.forEach((name, values) {
        if (name != HttpHeaders.hostHeader) upstream.headers.set(name, values);
      });
      if (request.method == 'PUT' && !dropped) {
        dropped = true;
        var forwarded = 0;
        try {
          await for (final chunk in request) {
            upstream.add(chunk);
            await upstream.flush();
            forwarded += chunk.length;
            if (forwarded >= 768 * 1024) break;
          }
        } finally {
          upstream.abort();
          try {
            final socket = await request.response.detachSocket(
              writeHeaders: false,
            );
            socket.destroy();
          } catch (_) {
            /* Cancelling the partial request may already close it. */
          }
        }
      } else {
        if (request.method == 'PUT' &&
            int.parse(request.headers.value('x-debrify-offset') ?? '0') > 0) {
          resumed = true;
        }
        await upstream.addStream(request);
        final response = await upstream.close();
        request.response.statusCode = response.statusCode;
        final stamp = response.headers.value('x-debrify-receipt');
        if (stamp != null) {
          request.response.headers.set('x-debrify-receipt', stamp);
        }
        await request.response.addStream(response);
        await request.response.close();
      }
    });
    final source = await File('${root.path}/large').writeAsBytes(payload);
    await sender.send(
      host: '127.0.0.1',
      port: proxy.port,
      sessionId: 'paired',
      key: key,
      file: source,
      metadata: {},
    );
    expect(resumed, isTrue);
    expect(imports, 1);
  });

  test('receiver application failure never returns success', () async {
    final receiver = await service((_) async {
      throw StateError('disk failure');
    });
    final sender = await service((_) async {});
    final source = await File('${root.path}/small').writeAsString('transfer');
    await expectLater(
      sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: source,
        metadata: {},
      ),
      throwsA(isA<RemoteTransferException>()),
    );
  });

  test('channel selections can exceed the in-memory receipt limit', () async {
    var imports = 0;
    final receiver = await service((_) async {
      imports++;
    }, receiptLimit: 2);
    final sender = await service((_) async {});
    final source = await File('${root.path}/small').writeAsString('transfer');
    for (var i = 0; i < 8; i++) {
      await sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: source,
        metadata: {'item': i},
      );
    }
    expect(imports, 8);
  });

  test('application outcome is returned through the receipt', () async {
    final receiver = await service((transfer) async {
      transfer.reportResult({'ok': true, 'profiles': 4});
    });
    final sender = await service((_) async {});
    final source = await File('${root.path}/small').writeAsString('transfer');
    expect(
      await sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: source,
        metadata: {},
      ),
      {'ok': true, 'profiles': 4},
    );
  });

  test('receiver revocation stops the next authenticated block', () async {
    var allowed = true;
    var blocks = 0;
    var imports = 0;
    final receiver = RemoteReliableTransfer(
      directory: Directory('${root.path}/revoked-receiver'),
      receiveKey: (_, _) async => allowed ? key : null,
      onReceive: (_) async {
        imports++;
      },
      onReceiveProgress: (_, _) {
        blocks++;
        allowed = false;
      },
    );
    services.add(receiver);
    await receiver.start(port: 0);
    final sender = await service((_) async {});
    final file = await File(
      '${root.path}/revoked-file',
    ).writeAsBytes(List<int>.filled(4 * RemoteReliableTransfer.blockBytes, 42));
    await expectLater(
      sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'paired',
        key: key,
        file: file,
        metadata: {},
      ),
      throwsA(isA<RemoteTransferException>()),
    );
    expect(blocks, 1);
    expect(imports, 0);
  });

  test('unpaired session never delivers data to the importer', () async {
    var imports = 0;
    final receiver = await service((_) async {
      imports++;
    });
    final sender = await service((_) async {});
    final source = await File('${root.path}/small').writeAsString('transfer');
    await expectLater(
      sender.send(
        host: '127.0.0.1',
        port: receiver.port,
        sessionId: 'unknown',
        key: key,
        file: source,
        metadata: {},
      ),
      throwsA(isA<RemoteTransferException>()),
    );
    expect(imports, 0);
  });

  test(
    'authorization revoked during a large send stops further blocks',
    () async {
      var imports = 0;
      final receiver = await service((_) async {
        imports++;
      });
      final sender = await service((_) async {});
      final source = await File(
        '${root.path}/large',
      ).writeAsBytes(List<int>.filled(1024 * 1024, 42));
      var sent = 0;
      await expectLater(
        sender.send(
          host: '127.0.0.1',
          port: receiver.port,
          sessionId: 'paired',
          key: key,
          file: source,
          metadata: {},
          onProgress: (done, _) {
            sent = done;
          },
          authorizationBarrier: () async {
            if (sent > 0) throw StateError('revoked');
          },
        ),
        throwsStateError,
      );
      expect(sent, RemoteReliableTransfer.blockBytes);
      expect(imports, 0);
    },
  );
}
