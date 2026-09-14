// Opt-in Linux AOT stress worker. Imports production implementations unchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/services/profiles/local_backup/local_backup_zip.dart';
import 'package:debrify/services/transfer/streaming_encrypted_file.dart';
import 'package:debrify/services/transfer/transfer_io.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_collection_sections.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';

const mib = 1024 * 1024;
final key = SecretKey(List.generate(32, (i) => i));
final stageTimes = <String, int>{};

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Map<String, Object?> memory() {
  String? read(String name) {
    final file = File('/sys/fs/cgroup/$name');
    return file.existsSync() ? file.readAsStringSync().trim() : null;
  }

  return {
    'rssBytes': ProcessInfo.currentRss,
    'peakRssBytes': ProcessInfo.maxRss,
    'cgroupLimit': read('memory.max'),
    'cgroupSwapLimit': read('memory.swap.max'),
    'cgroupCurrent': read('memory.current'),
    'cgroupPeak': read('memory.peak'),
    'cgroupEvents': read('memory.events'),
  };
}

void emit(String event, [Map<String, Object?> data = const {}]) =>
    stdout.writeln(jsonEncode({'event': event, ...data, ...memory()}));

Future<T> stage<T>(String name, Future<T> Function() work) async {
  emit('stage-start', {'stage': name});
  final watch = Stopwatch()..start();
  final result = await work();
  stageTimes[name] = watch.elapsedMilliseconds;
  emit('stage-end', {'stage': name, 'elapsedMs': watch.elapsedMilliseconds});
  return result;
}

Future<void> generate(File file, int bytes, String pattern) async {
  final output = await file.open(mode: FileMode.writeOnly);
  var state = 0x35718642;
  final chunk = Uint8List(TransferIo.bufferBytes);
  try {
    for (var offset = 0; offset < bytes; offset += chunk.length) {
      for (var i = 0; i < chunk.length; i++) {
        state ^= (state << 13) & 0xffffffff;
        state ^= state >> 17;
        state ^= (state << 5) & 0xffffffff;
        chunk[i] = pattern == 'zeros'
            ? 0
            : pattern == 'random' || i % 1024 >= 900
            ? state & 255
            : 0;
      }
      final remaining = bytes - offset;
      await output.writeFrom(
        chunk,
        0,
        remaining < chunk.length ? remaining : chunk.length,
      );
    }
  } finally {
    await output.close();
  }
}

// Real loopback HTTP with streamed disk storage, inside the same RAM budget as
// the client. This fixture does not buffer request or response bodies in RAM.
final class TestServer {
  TestServer(this.server, this.object);
  final HttpServer server;
  final File object;
  final errors = <Object>[];
  bool interruptNext = false;
  int? lastRange;
  int lastSentBytes = 0;

  static Future<TestServer> start(File object) async {
    final instance = TestServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      object,
    );
    instance.server.listen((request) async {
      try {
        await instance.handle(request);
      } on SocketException {
        // Expected when a cancellation closes the client's socket.
      } on HttpException {
        // Expected when a cancellation closes the client's response.
      } catch (error) {
        instance.errors.add(error);
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
    });
    return instance;
  }

  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    if (request.method == 'PUT') {
      final sink = object.openWrite();
      try {
        await sink.addStream(request);
      } finally {
        await sink.close();
      }
      response.statusCode = HttpStatus.created;
      await response.close();
      return;
    }
    check(request.method == 'GET', 'Unexpected method ${request.method}');
    final length = await object.length();
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final start = range == null
        ? 0
        : int.parse(RegExp(r'^bytes=(\d+)-$').firstMatch(range)!.group(1)!);
    lastRange = range == null ? null : start;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (range != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${length - 1}/$length',
      );
    }
    response.contentLength = length - start;
    if (interruptNext) {
      interruptNext = false;
      final socket = await response.detachSocket(writeHeaders: true);
      await socket.addStream(object.openRead(start, start + mib));
      await socket.flush();
      socket.destroy();
    } else {
      lastSentBytes = length - start;
      await response.addStream(object.openRead(start));
      await response.close();
    }
  }
}

Future<void> expectFailure(
  Future<void> Function() action,
  File partial, {
  bool cancelled = false,
}) async {
  Object? failure;
  try {
    await action();
  } catch (error) {
    failure = error;
  }
  check(failure != null, 'Expected failure did not occur');
  if (cancelled) {
    check(failure is LocalBackupCancelledException, 'Wrong failure: $failure');
  }
  check(!await partial.exists(), 'Failed operation left a partial file');
}

Future<void> pipeline(
  Directory directory,
  int sizeMiB,
  String pattern,
  String mode,
  int repeats,
) async {
  final source = File('${directory.path}/source');
  await stage('generate', () => generate(source, sizeMiB * mib, pattern));
  final expectedHash = await TransferIo.hashFile(source);
  final remote = File('${directory.path}/remote');
  final server = await TestServer.start(remote);
  final client = WebDavProtocolClient(
    endpoint: Uri.parse('http://127.0.0.1:${server.server.port}/'),
    credentials: const WebDavCredentials(username: 'test', password: 'test'),
  );
  final password = mode == 'password' ? 'stress-test-password' : null;
  var selectedKey = password == null ? key : null;
  try {
    if (mode == 'sync') {
      final codec = WebDavSyncCodec();
      final marker = await stage(
        'sync-create-root',
        () => codec.sealRoot(
          passphrase: 'stress-test-sync-passphrase',
          circleId: 'stress-circle',
          createdAt: DateTime.utc(2026),
          runInBackground: true,
        ),
      );
      // Model a fresh device unlocking the root, without a cache hit. This
      // covers actual default KDF settings before the archive transfer starts.
      WebDavSyncCodec.clearRootKeyCache();
      final opened = await stage(
        'sync-unlock-root',
        () => codec.openRoot(
          marker,
          'stress-test-sync-passphrase',
          runInBackground: true,
        ),
      );
      selectedKey = opened.key.secretKey;
    }
    for (var iteration = 0; iteration < repeats; iteration++) {
      final work = await Directory(
        '${directory.path}/round-$iteration',
      ).create();
      final zip = File('${work.path}/backup.zip');
      final encrypted = File('${work.path}/backup.enc');
      final downloaded = File('${work.path}/download.enc');
      final decrypted = File('${work.path}/decrypted.zip');
      final restored = File('${work.path}/restored');
      await stage(
        '$iteration/zip',
        () => LocalBackupZip.write(
          output: zip,
          sources: [
            LocalBackupZipSource(
              name: 'databases/profile.sqlite',
              file: source,
              bytes: sizeMiB * mib,
            ),
          ],
          modified: DateTime.utc(2026),
        ),
      );
      final sealed = await stage(
        '$iteration/encrypt',
        () => StreamingEncryptedFile.encrypt(
          source: zip,
          destination: encrypted,
          context: 'memory-stress',
          key: selectedKey,
          passphrase: password,
          compress: true,
        ),
      );
      await stage(
        '$iteration/upload',
        () => client.uploadFile(
          path: 'object.enc',
          file: encrypted,
          maxBytes: sealed.bytes,
          createParents: false,
        ),
      );
      check(
        await TransferIo.hashFile(remote) == sealed.sha256Hex,
        'Upload hash',
      );

      Future<WebDavFileResult> download({void Function()? checkCancelled}) =>
          client.downloadToFile(
            path: 'object.enc',
            destination: downloaded,
            maxBytes: sealed.bytes,
            resumeExpectedSha256: sealed.sha256Hex,
            checkCancelled: checkCancelled,
          );

      if (mode == 'faults') {
        await stage('interrupted-download', () async {
          server.interruptNext = true;
          var interrupted = false;
          try {
            await download();
          } on WebDavException catch (error) {
            check(error.kind == WebDavErrorKind.network, '$error');
            interrupted = true;
          }
          check(interrupted, 'Expected interrupted response');
          final prefix = await downloaded.length();
          check(prefix > 0 && prefix < sealed.bytes, 'Missing retained prefix');
          await download();
          check(server.lastRange == prefix, 'Retry did not resume the prefix');
          check(
            server.lastSentBytes == sealed.bytes - prefix,
            'Wrong range size',
          );
          await downloaded.delete();
        });
        await stage('cancel-download', () async {
          var callbacks = 0;
          await expectFailure(
            () async {
              await download(
                checkCancelled: () {
                  if (++callbacks == 8) {
                    throw const LocalBackupCancelledException();
                  }
                },
              );
            },
            downloaded,
            cancelled: true,
          );
          check(callbacks == 8, 'Cancellation callback was not called in body');
        });
        await stage('cancel-encrypt', () async {
          final cancellation = LocalBackupCancellation();
          final partial = File('${work.path}/cancelled.enc');
          await expectFailure(
            () async {
              await StreamingEncryptedFile.encrypt(
                source: zip,
                destination: partial,
                context: 'memory-stress',
                key: key,
                cancellation: cancellation,
                onProgress: (done, total) {
                  if (done > 0) cancellation.cancel();
                },
              );
            },
            partial,
            cancelled: true,
          );
        });
      }
      final fetched = await stage('$iteration/download', download);
      check(fetched.sha256Hex == sealed.sha256Hex, 'Download hash');
      await stage(
        '$iteration/decrypt',
        () => StreamingEncryptedFile.decrypt(
          source: downloaded,
          destination: decrypted,
          context: 'memory-stress',
          key: selectedKey,
          passphrase: password,
        ),
      );
      await stage('$iteration/extract', () async {
        final reader = await LocalBackupZipReader.open(decrypted);
        try {
          check(reader.entries.length == 1, 'Archive inventory changed');
          await reader.extract(
            reader.find('databases/profile.sqlite')!,
            restored,
          );
        } finally {
          await reader.close();
        }
        check(await restored.length() == sizeMiB * mib, 'Restored length');
        check(
          await TransferIo.hashFile(restored) == expectedHash,
          'Restored hash',
        );
      });
      if (mode == 'faults') {
        await stage('corrupt-ciphertext', () async {
          final handle = await downloaded.open(mode: FileMode.append);
          try {
            final position = (await handle.length()) ~/ 2;
            await handle.setPosition(position);
            final byte = await handle.readByte();
            await handle.setPosition(position);
            await handle.writeByte(byte ^ 1);
          } finally {
            await handle.close();
          }
          final partial = File('${work.path}/corrupt.zip');
          await expectFailure(() async {
            await StreamingEncryptedFile.decrypt(
              source: downloaded,
              destination: partial,
              context: 'memory-stress',
              key: key,
            );
          }, partial);
        });
      }
      emit('iteration', {
        'iteration': iteration,
        'encryptedBytes': sealed.bytes,
      });
      await work.delete(recursive: true);
      await remote.delete();
    }
    check(server.errors.isEmpty, 'Server errors: ${server.errors}');
  } finally {
    WebDavSyncCodec.clearRootKeyCache();
    client.close();
    await server.server.close(force: true);
  }
}

Future<void> collections(int count) async {
  const stamp = WebDavSyncStamp(normalizedTimeMs: 1, originDeviceId: 'stress');
  // Each title is separately allocated. Reusing one padding string would hide
  // the live inventory's actual memory cost (513 * 382 KiB = 191.37 MiB).
  final records = <String, WebDavSyncStampedValue>{};
  for (var i = 0; i < count; i++) {
    records['homecollection/$i'] = WebDavSyncStampedValue(
      stamp: stamp,
      value: HomeCollection(
        id: '$i',
        title: '$i:${'x' * (382 * 1024)}',
      ).toJson(),
    );
    if (i % 64 == 0) emit('inventory-build', {'records': i + 1});
  }
  final source = WebDavSyncHotDocument(
    circleProfileId: 'profile',
    scalars: WebDavSyncScalarPart(
      semanticDigest: semanticDigestOf({}),
      entries: const {},
    ),
    watchState: WebDavSyncWatchPart(
      stamp: stamp,
      semanticDigest: 'a' * 64,
      records: records,
      orders: {
        'homecollections/items': WebDavSyncOrderValue(
          stamp: stamp,
          keys: [for (var i = 0; i < count; i++) '$i'],
        ),
      },
    ),
  );
  final plan = await stage(
    'collection-plan',
    () => WebDavSyncCollectionSections.plan([source], reservedSections: 7),
  );
  final parts = await stage(
    'collection-prepare',
    () => WebDavSyncCollectionSections().prepare(
      'profile',
      source,
      targetBytes: plan.targetBytes,
    ),
  );
  await stage('collection-verify', () async {
    check(parts.length + 6 <= 512, 'Manifest section overflow');
    final seen = <String>{};
    for (final part in parts.values) {
      check(part.digest.length == 64, 'Invalid digest');
      for (final record in part.document.watchState.records.entries) {
        check(seen.add(record.key), 'Duplicate collection');
        // Compare the complete object graph without encoding two large JSON
        // strings. Assertion allocations must not masquerade as production OOM.
        check(
          const DeepCollectionEquality().equals(
            record.value.toJson(),
            records[record.key]!.toJson(),
          ),
          'Collection changed',
        );
      }
    }
    check(seen.length == count, 'Missing collection');
  });
  emit('collections-verified', {'count': count, 'sections': parts.length});
}

Future<void> main(List<String> args) async {
  final scenario = args[0];
  final size = int.parse(args[1]);
  final watch = Stopwatch()..start();
  emit('start', {'scenario': scenario, 'size': size, 'arguments': args});
  if (scenario == 'oom-control') {
    final blocks = <Uint8List>[];
    // Touch every page and retain all blocks, so Linux cannot lazily reserve
    // zero pages and the compiler cannot eliminate the allocation.
    for (var i = 0; i < size; i++) {
      final block = Uint8List(mib);
      for (var j = 0; j < block.length; j += 4096) {
        block[j] = (i % 255) + 1;
      }
      blocks.add(block);
      if (i % 16 == 0) emit('allocation', {'allocatedMiB': i + 1});
    }
    emit('control-survived', {
      'checksum': blocks.fold<int>(0, (n, b) => n + b[0]),
    });
    throw StateError('The OOM control must be killed by the memory limit');
  }
  final directory = await Directory.systemTemp.createTemp('debrify-memory-');
  try {
    if (scenario == 'collections') {
      await collections(size);
    } else {
      check(scenario == 'pipeline', 'Unknown scenario');
      await pipeline(directory, size, args[2], args[3], int.parse(args[4]));
    }
    emit('result', {
      'verified': true,
      'elapsedMs': watch.elapsedMilliseconds,
      'stageTimesMs': stageTimes,
    });
  } finally {
    await directory.delete(recursive: true);
  }
}
