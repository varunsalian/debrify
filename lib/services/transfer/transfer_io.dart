import 'dart:convert';
import 'dart:io';

import 'package:synchronized/synchronized.dart';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Shared bounds for disk and network transfer work. A transfer never queues
/// the next block until its consumer has accepted the previous block.
abstract final class TransferIo {
  static final Lock largeWorker = Lock();
  static const int bufferBytes = 256 * 1024;
  static const int maxFileBytes = 20 * 1024 * 1024 * 1024;
  static const int metadataConcurrency = 3;

  /// RandomAccessFile may return a short read even before EOF.
  static Future<Uint8List> readExactly(RandomAccessFile file, int bytes) async {
    if (bytes < 0 || bytes > bufferBytes) {
      throw ArgumentError.value(bytes, 'bytes');
    }
    final result = Uint8List(bytes);
    var offset = 0;
    while (offset < bytes) {
      final count = await file.readInto(result, offset, bytes);
      if (count == 0) {
        throw const FormatException('Transfer file is truncated');
      }
      offset += count;
    }
    return result;
  }

  static Future<String> hashFile(File file) async {
    final input = await file.open();
    final digest = TransferDigest();
    try {
      while (true) {
        final bytes = await input.read(bufferBytes);
        if (bytes.isEmpty) break;
        digest.add(bytes);
      }
      return digest.finish();
    } finally {
      await input.close();
    }
  }
}

/// SHA-256 calculated in the I/O pass, without retaining any input blocks.
final class TransferDigest {
  TransferDigest() {
    _input = sha256.startChunkedConversion(_output);
  }

  final _DigestSink _output = _DigestSink();
  late final ByteConversionSink _input;

  void add(List<int> bytes) => _input.add(bytes);

  String finish() {
    _input.close();
    return _output.digest!.toString();
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
