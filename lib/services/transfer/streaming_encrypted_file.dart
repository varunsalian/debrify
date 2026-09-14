import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartArgon2id;

import '../profiles/local_backup/local_backup_zip.dart';
import 'transfer_io.dart';

final class StreamingFileResult {
  const StreamingFileResult({
    required this.bytes,
    required this.sha256Hex,
    required this.elapsedMs,
    required this.peakResidentBytes,
  });

  final int bytes;
  final String sha256Hex;
  final int elapsedMs;
  final int peakResidentBytes;
}

/// Authenticated binary files with a fixed 69-byte application header followed
/// by the AES-GCM-HKDF streaming format specified by Google Tink:
/// https://developers.google.com/tink/streaming-aead/aes_gcm_hkdf_streaming
///
/// The application header is HKDF associated data. It binds version, length,
/// key mode, password salt, and the caller's context. Segment nonces contain a
/// random seven-byte prefix, the segment index, and an authenticated EOF bit.
/// Every file derives its own AES key from a random 32-byte salt. Segments
/// cannot be reordered, transplanted, appended, or truncated undetected.
///
/// Work runs in one worker at a time, passing paths and key material only.
/// Neither the UI isolate nor the crypto library receives a whole file.
abstract final class StreamingEncryptedFile {
  static const String extension = '.debrify.enc';
  static const int segmentBytes = TransferIo.bufferBytes;
  static const int headerBytes = 69;
  static const int streamHeaderBytes = 40;
  static const int tagBytes = 16;
  static const int passwordMemoryKiB = 19456;
  static const int passwordIterations = 2;
  static final Uint8List _magic = Uint8List.fromList(ascii.encode('DBRFENC2'));
  static int _pending = 0;

  static Future<bool> looksLike(File file) async {
    final input = await file.open();
    try {
      return _equal(await input.read(_magic.length), _magic);
    } finally {
      await input.close();
    }
  }

  /// Exactly one of [key] (a 256-bit machine key) and [passphrase] is required.
  /// The destination must not exist. Partial files are removed on failure.
  static Future<StreamingFileResult> encrypt({
    required File source,
    required File destination,
    required String context,
    SecretKey? key,
    String? passphrase,
    int maxPlainBytes = TransferIo.maxFileBytes,
    bool compress = false,
    LocalBackupCancellation? cancellation,
    void Function(int done, int total)? onProgress,
  }) => _run(
    source: source,
    destination: destination,
    context: context,
    key: key,
    passphrase: passphrase,
    encrypting: true,
    compress: compress,
    maxPlainBytes: maxPlainBytes,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  static Future<StreamingFileResult> decrypt({
    required File source,
    required File destination,
    required String context,
    SecretKey? key,
    String? passphrase,
    int maxPlainBytes = TransferIo.maxFileBytes,
    LocalBackupCancellation? cancellation,
    void Function(int done, int total)? onProgress,
  }) => _run(
    source: source,
    destination: destination,
    context: context,
    key: key,
    passphrase: passphrase,
    encrypting: false,
    compress: false,
    maxPlainBytes: maxPlainBytes,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  static Future<StreamingFileResult> _run({
    required File source,
    required File destination,
    required String context,
    required SecretKey? key,
    required String? passphrase,
    required bool encrypting,
    required bool compress,
    required int maxPlainBytes,
    required LocalBackupCancellation? cancellation,
    required void Function(int, int)? onProgress,
  }) async {
    if ((key == null) == (passphrase == null) ||
        (passphrase != null &&
            (passphrase.length < 8 || passphrase.length > 1024)) ||
        context.isEmpty ||
        context.length > 4096 ||
        maxPlainBytes < 0 ||
        maxPlainBytes > TransferIo.maxFileBytes) {
      throw ArgumentError('Invalid encrypted file parameters');
    }
    cancellation?.throwIfCancelled();
    if (_pending >= 8) throw StateError('Too many pending file transfers');
    _pending++;
    try {
      return await TransferIo.largeWorker.synchronized(() async {
        cancellation?.throwIfCancelled();
        final keyBytes = key == null
            ? null
            : Uint8List.fromList(await key.extractBytes());
        if (keyBytes != null && keyBytes.length != 32) {
          throw ArgumentError('File encryption requires a 256-bit key');
        }
        final receive = ReceivePort();
        final completed = Completer<StreamingFileResult>();
        void Function()? unsubscribe;
        SendPort? control;
        Object? callbackError;
        StackTrace? callbackStack;
        final subscription = receive.listen((message) {
          if (message is SendPort) {
            control = message;
            unsubscribe = cancellation?.listen(() => message.send('cancel'));
          } else if (message is StreamingFileResult) {
            if (!completed.isCompleted) completed.complete(message);
          } else if (message is _WorkerFailure) {
            if (!completed.isCompleted) {
              completed.completeError(message.error, message.stackTrace);
            }
          } else if (message is _Progress) {
            try {
              onProgress?.call(message.done, message.total);
            } catch (error, stack) {
              callbackError = error;
              callbackStack = stack;
              // Let the worker close and remove its own partial output. Killing
              // an isolate at the callback boundary can strand an open file.
              control?.send('cancel');
            }
          } else if (!completed.isCompleted) {
            completed.completeError(StateError('File transfer worker stopped'));
          }
        });
        Isolate? worker;
        try {
          worker = await Isolate.spawn(
            _worker,
            _WorkerRequest(
              reply: receive.sendPort,
              source: source.path,
              destination: destination.path,
              context: context,
              keyBytes: keyBytes,
              passphrase: passphrase,
              encrypting: encrypting,
              compress: compress,
              maxPlainBytes: maxPlainBytes,
            ),
            onError: receive.sendPort,
            onExit: receive.sendPort,
          );
          StreamingFileResult result;
          try {
            result = await completed.future;
          } catch (_) {
            if (callbackError != null) {
              Error.throwWithStackTrace(callbackError!, callbackStack!);
            }
            rethrow;
          }
          if (callbackError != null) {
            // A progress callback can race the final worker completion.
            if (await destination.exists()) await destination.delete();
            Error.throwWithStackTrace(callbackError!, callbackStack!);
          }
          if (cancellation?.isCancelled == true) {
            if (await destination.exists()) await destination.delete();
            throw const LocalBackupCancelledException();
          }
          return result;
        } finally {
          unsubscribe?.call();
          worker?.kill(priority: Isolate.immediate);
          await subscription.cancel();
          receive.close();
          keyBytes?.fillRange(0, keyBytes.length, 0);
        }
      });
    } finally {
      _pending--;
    }
  }

  static Future<void> _worker(_WorkerRequest request) async {
    final control = ReceivePort();
    var cancelled = false;
    control.listen((_) => cancelled = true);
    request.reply.send(control.sendPort);
    try {
      final result = await _process(request, () {
        if (cancelled) throw const LocalBackupCancelledException();
      });
      request.reply.send(result);
    } catch (error, stack) {
      request.reply.send(_WorkerFailure(error, stack));
    } finally {
      control.close();
      request.keyBytes?.fillRange(0, request.keyBytes!.length, 0);
    }
  }

  /// Compression is a native streaming gzip pass in the same sole worker.
  /// It removes SQLite/JSON redundancy before encryption without constructing
  /// a whole gzip buffer. Decompression follows full AEAD verification.
  static Future<StreamingFileResult> _process(
    _WorkerRequest request,
    void Function() checkCancelled,
  ) async {
    final watch = Stopwatch()..start();
    final destination = File(request.destination);
    if (await destination.exists()) {
      throw StateError('Encrypted file destination already exists');
    }
    var compressed = request.compress;
    if (!request.encrypting) {
      final source = await File(request.source).open();
      try {
        final header = await TransferIo.readExactly(source, headerBytes);
        _validateHeader(header, request);
        compressed = header[8] & 2 != 0;
      } finally {
        await source.close();
      }
    }
    if (request.encrypting &&
        compressed &&
        !await _worthCompressing(File(request.source), checkCancelled)) {
      return _processCipher(request.files(compress: false), checkCancelled);
    }
    if (!compressed) return _processCipher(request, checkCancelled);
    await destination.parent.create(recursive: true);
    final scratch = await destination.parent.createTemp('.stream-codec-');
    final gzipFile = File('${scratch.path}/payload.gz');
    var created = false;
    try {
      if (request.encrypting) {
        if (await File(request.source).length() > request.maxPlainBytes) {
          throw const FormatException('Backup exceeds the file size limit');
        }
        await _convertFile(
          File(request.source),
          gzipFile,
          GZipCodec(level: 1).encoder,
          request.maxPlainBytes,
          checkCancelled,
        );
        final sealed = await _processCipher(
          request.files(source: gzipFile.path),
          checkCancelled,
        );
        return StreamingFileResult(
          bytes: sealed.bytes,
          sha256Hex: sealed.sha256Hex,
          elapsedMs: watch.elapsedMilliseconds,
          peakResidentBytes: ProcessInfo.maxRss,
        );
      }
      await _processCipher(
        request.files(destination: gzipFile.path),
        checkCancelled,
      );
      checkCancelled();
      created = true;
      final expanded = await _convertFile(
        gzipFile,
        destination,
        gzip.decoder,
        request.maxPlainBytes,
        checkCancelled,
        compressedInput: true,
      );
      return StreamingFileResult(
        bytes: expanded.bytes,
        sha256Hex: expanded.hash,
        elapsedMs: watch.elapsedMilliseconds,
        peakResidentBytes: ProcessInfo.maxRss,
      );
    } catch (_) {
      if (created && await destination.exists()) await destination.delete();
      rethrow;
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  static Future<bool> _worthCompressing(
    File source,
    void Function() checkCancelled,
  ) async {
    final input = await source.open();
    try {
      final length = await input.length();
      if (length < 64 * 1024) return true;
      var plain = 0;
      var encoded = 0;
      for (final offset in {0, length ~/ 2}) {
        checkCancelled();
        await input.setPosition(offset);
        final chunk = await input.read(TransferIo.bufferBytes);
        plain += chunk.length;
        encoded += GZipCodec(level: 1).encode(chunk).length;
      }
      return encoded < plain * 0.97;
    } finally {
      await input.close();
    }
  }

  static Future<({int bytes, String hash})> _convertFile(
    File source,
    File destination,
    Converter<List<int>, List<int>> converter,
    int maxBytes,
    void Function() checkCancelled, {
    bool compressedInput = false,
  }) async {
    final input = await source.open();
    RandomAccessFile? output;
    try {
      output = await destination.open(mode: FileMode.writeOnly);
      // DEFLATE expands at most about 1032x: 4 KiB input limits even an
      // adversarial output chunk to about 4 MiB, in the sole large worker.
      Stream<List<int>> chunks() async* {
        while (true) {
          checkCancelled();
          final chunk = await input.read(compressedInput ? 4096 : 64 * 1024);
          if (chunk.isEmpty) break;
          yield chunk;
        }
      }

      var count = 0;
      final digest = TransferDigest();
      await for (final chunk in converter.bind(chunks())) {
        checkCancelled();
        if (chunk.length > maxBytes - count) {
          throw const FormatException(
            'Expanded backup exceeds the file size limit',
          );
        }
        await output.writeFrom(chunk);
        digest.add(chunk);
        count += chunk.length;
      }
      await output.flush();
      return (bytes: count, hash: digest.finish());
    } finally {
      await input.close();
      await output?.close();
    }
  }

  static Future<StreamingFileResult> _processCipher(
    _WorkerRequest request,
    void Function() checkCancelled,
  ) async {
    final stopwatch = Stopwatch()..start();
    final source = File(request.source);
    final destination = File(request.destination);
    if (await destination.exists()) {
      throw StateError('Encrypted file destination already exists');
    }
    final input = await source.open();
    RandomAccessFile? output;
    SecretKey? master;
    SecretKey? derived;
    var created = false;
    try {
      checkCancelled();
      final sourceBytes = await input.length();
      final header = request.encrypting
          ? _header(request, sourceBytes)
          : await TransferIo.readExactly(input, headerBytes);
      final length = _validateHeader(header, request);
      final segmentCount = max(
        1,
        (length + streamHeaderBytes + segmentBytes - tagBytes - 1) ~/
            (segmentBytes - tagBytes),
      );
      final encodedBytes =
          headerBytes + streamHeaderBytes + length + tagBytes * segmentCount;
      if (encodedBytes > TransferIo.maxFileBytes) {
        throw const FormatException(
          'Encrypted backup exceeds the file size limit',
        );
      }
      if (!request.encrypting && sourceBytes != encodedBytes) {
        throw const FormatException('Encrypted file length does not match');
      }
      master = request.keyBytes == null
          ? await DartArgon2id(
              memory: passwordMemoryKiB,
              iterations: passwordIterations,
              parallelism: 1,
              hashLength: 32,
              // This operation already owns the file worker. Keep the KDF's
              // working memory in its managed heap, without a nested worker
              // and a separate native allocation outside the GC's accounting.
              maxIsolates: 0,
            ).deriveKey(
              secretKey: SecretKey(utf8.encode(request.passphrase!)),
              nonce: Uint8List.sublistView(header, 21, 37),
            )
          : SecretKey(request.keyBytes!);
      checkCancelled();
      final streamHeader = request.encrypting
          ? (Uint8List(streamHeaderBytes)
              ..[0] = streamHeaderBytes
              ..setRange(1, streamHeaderBytes, _random(streamHeaderBytes - 1)))
          : await TransferIo.readExactly(input, streamHeaderBytes);
      if (streamHeader[0] != streamHeaderBytes) {
        throw const FormatException('Invalid encrypted stream header');
      }
      derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: master,
        nonce: Uint8List.sublistView(streamHeader, 1, 33),
        info: header,
      );
      final cipher = AesGcm.with256bits();
      final digest = TransferDigest();
      await destination.parent.create(recursive: true);
      output = await destination.open(mode: FileMode.writeOnly);
      created = true;
      var written = 0;
      Future<void> write(List<int> bytes) async {
        await output!.writeFrom(bytes);
        digest.add(bytes);
        written += bytes.length;
      }

      if (request.encrypting) {
        await write(header);
        await write(streamHeader);
      }
      var remaining = length;
      var lastProgressMs = -200;
      for (var index = 0; index < segmentCount; index++) {
        checkCancelled();
        final count = min(
          remaining,
          segmentBytes - tagBytes - (index == 0 ? streamHeaderBytes : 0),
        );
        final nonce = Uint8List(12)
          ..setRange(0, 7, streamHeader, 33)
          ..[11] = index == segmentCount - 1 ? 1 : 0;
        ByteData.sublistView(nonce).setUint32(7, index, Endian.big);
        if (request.encrypting) {
          final plain = await TransferIo.readExactly(input, count);
          final box = await cipher.encrypt(
            plain,
            secretKey: derived,
            nonce: nonce,
          );
          await write(box.cipherText);
          await write(box.mac.bytes);
        } else {
          final sealed = await TransferIo.readExactly(input, count + tagBytes);
          final plain = await cipher.decrypt(
            SecretBox(
              Uint8List.sublistView(sealed, 0, count),
              nonce: nonce,
              mac: Mac(Uint8List.sublistView(sealed, count)),
            ),
            secretKey: derived,
          );
          await write(plain);
        }
        remaining -= count;
        if (stopwatch.elapsedMilliseconds - lastProgressMs >= 150 ||
            remaining == 0) {
          lastProgressMs = stopwatch.elapsedMilliseconds;
          request.reply.send(_Progress(length - remaining, length));
        }
        // Drain cancellation messages even on memory-backed filesystems.
        await Future<void>.delayed(Duration.zero);
      }
      checkCancelled();
      if ((await input.read(1)).isNotEmpty) {
        throw const FormatException('Transfer source changed while reading');
      }
      await output.flush();
      return StreamingFileResult(
        bytes: written,
        sha256Hex: digest.finish(),
        elapsedMs: stopwatch.elapsedMilliseconds,
        peakResidentBytes: ProcessInfo.maxRss,
      );
    } catch (error) {
      await output?.close();
      output = null;
      if (created && await destination.exists()) await destination.delete();
      if (error is SecretBoxAuthenticationError) {
        throw const FormatException('Invalid encryption key or damaged backup');
      }
      rethrow;
    } finally {
      await output?.close();
      await input.close();
      derived?.destroy();
      master?.destroy();
    }
  }

  static Uint8List _header(_WorkerRequest request, int length) {
    if (length > request.maxPlainBytes) {
      throw const FormatException('Backup exceeds the file size limit');
    }
    final bytes = Uint8List(headerBytes)
      ..setRange(0, _magic.length, _magic)
      ..[8] = (request.keyBytes == null ? 1 : 0) | (request.compress ? 2 : 0)
      ..setRange(21, 37, _random(16))
      ..setRange(
        37,
        69,
        hashes.sha256.convert(utf8.encode(request.context)).bytes,
      );
    ByteData.sublistView(bytes)
      ..setUint32(9, segmentBytes, Endian.big)
      ..setUint64(13, length, Endian.big);
    return bytes;
  }

  static int _validateHeader(Uint8List header, _WorkerRequest request) {
    final data = ByteData.sublistView(header);
    final length = data.getUint64(13, Endian.big);
    if (!_equal(Uint8List.sublistView(header, 0, 8), _magic) ||
        header[8] > 3 ||
        (header[8] & 1) != (request.keyBytes == null ? 1 : 0) ||
        data.getUint32(9, Endian.big) != segmentBytes ||
        length < 0 ||
        length > request.maxPlainBytes ||
        !_equal(
          Uint8List.sublistView(header, 37),
          hashes.sha256.convert(utf8.encode(request.context)).bytes,
        )) {
      throw const FormatException('Invalid encrypted file header or context');
    }
    return length;
  }

  static Uint8List _random(int count) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(count, (_) => random.nextInt(256)));
  }

  static bool _equal(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }
}

final class _WorkerRequest {
  const _WorkerRequest({
    required this.reply,
    required this.source,
    required this.destination,
    required this.context,
    required this.keyBytes,
    required this.passphrase,
    required this.encrypting,
    required this.compress,
    required this.maxPlainBytes,
  });
  final SendPort reply;
  final String source;
  final String destination;
  final String context;
  final Uint8List? keyBytes;
  final String? passphrase;
  final bool encrypting;
  final bool compress;
  final int maxPlainBytes;

  _WorkerRequest files({String? source, String? destination, bool? compress}) =>
      _WorkerRequest(
        reply: reply,
        source: source ?? this.source,
        destination: destination ?? this.destination,
        context: context,
        keyBytes: keyBytes,
        passphrase: passphrase,
        encrypting: encrypting,
        compress: compress ?? this.compress,
        maxPlainBytes: maxPlainBytes,
      );
}

final class _WorkerFailure {
  const _WorkerFailure(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

final class _Progress {
  const _Progress(this.done, this.total);
  final int done;
  final int total;
}
