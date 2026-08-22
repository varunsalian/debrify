import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

class ExternalSubtitlePayload {
  const ExternalSubtitlePayload(this.bytes, this.extension);

  final Uint8List bytes;
  final String extension;
}

const int maxSubtitleResponseBytes = 5 * 1024 * 1024;
const int maxDecodedSubtitleBytes = 5 * 1024 * 1024;
const int maxSubtitleZipEntries = 32;

Future<Uint8List> readBoundedSubtitleResponse(
  Stream<List<int>> stream, {
  int maxBytes = maxSubtitleResponseBytes,
}) async {
  final builder = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in stream) {
    length += chunk.length;
    if (length > maxBytes) {
      throw FormatException(
        'Subtitle response exceeds the $maxBytes byte limit',
      );
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

const _subtitleExtensions = <String>{
  'srt',
  'vtt',
  'ass',
  'ssa',
  'ttml',
  'xml',
  'sub',
};

String externalSubtitleCacheStem(String url) =>
    sha256.convert(utf8.encode(url)).toString().substring(0, 24);

ExternalSubtitlePayload prepareExternalSubtitlePayload(
  List<int> responseBytes,
  Uri sourceUri,
) {
  if (responseBytes.isEmpty) {
    throw const FormatException('Subtitle response was empty');
  }
  if (responseBytes.length > maxSubtitleResponseBytes) {
    throw const FormatException('Subtitle response was too large');
  }

  var bytes = Uint8List.fromList(responseBytes);
  var sourceName = sourceUri.pathSegments.isEmpty
      ? ''
      : sourceUri.pathSegments.last;

  if (_hasPrefix(bytes, const [0x1f, 0x8b])) {
    bytes = _decodeGzipBounded(bytes);
    sourceName = sourceName.replaceFirst(
      RegExp(r'\.gz$', caseSensitive: false),
      '',
    );
  } else if (_hasPrefix(bytes, const [0x50, 0x4b])) {
    _validateZipDirectory(bytes);
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final entries = archive
        .where((entry) => entry.isFile && _extensionOf(entry.name) != null)
        .toList(growable: false);
    if (entries.isEmpty) {
      throw const FormatException('ZIP contained no supported subtitle file');
    }
    final entry = entries.first;
    if (entry.size > maxDecodedSubtitleBytes) {
      throw const FormatException('Decoded ZIP subtitle was too large');
    }
    bytes = _decodeZipEntryBounded(entry);
    sourceName = entry.name;
  }

  if (bytes.isEmpty) {
    throw const FormatException('Subtitle payload was empty after decoding');
  }
  if (bytes.length > maxDecodedSubtitleBytes) {
    throw const FormatException('Decoded subtitle was too large');
  }

  final preview = utf8
      .decode(bytes.take(256).toList(), allowMalformed: true)
      .trimLeft()
      .toLowerCase();
  if (preview.startsWith('<!doctype html') || preview.startsWith('<html')) {
    throw const FormatException('Subtitle URL returned an HTML page');
  }

  final extension =
      _extensionOf(sourceName) ??
      _extensionFromFormat(sourceUri) ??
      _extensionFromContent(preview);
  return ExternalSubtitlePayload(bytes, extension);
}

void _validateZipDirectory(Uint8List bytes) {
  // Locate the end-of-central-directory record before asking archive to
  // allocate an object per entry. The maximum legal ZIP comment is 65535
  // bytes, so only that bounded suffix can contain the record.
  final firstCandidate = (bytes.length - 22 - 0xffff)
      .clamp(0, bytes.length)
      .toInt();
  for (var i = bytes.length - 22; i >= firstCandidate; i--) {
    if (!_hasPrefixAt(bytes, i, const [0x50, 0x4b, 0x05, 0x06])) continue;
    final commentLength = _uint16Le(bytes, i + 20);
    if (i + 22 + commentLength != bytes.length) continue;

    final disk = _uint16Le(bytes, i + 4);
    final centralDisk = _uint16Le(bytes, i + 6);
    final diskEntries = _uint16Le(bytes, i + 8);
    final totalEntries = _uint16Le(bytes, i + 10);
    final centralSize = _uint32Le(bytes, i + 12);
    final centralOffset = _uint32Le(bytes, i + 16);
    if (disk != 0 || centralDisk != 0 || diskEntries != totalEntries) {
      throw const FormatException('Multi-disk subtitle ZIP is unsupported');
    }
    if (totalEntries > maxSubtitleZipEntries) {
      throw const FormatException('Subtitle ZIP contained too many entries');
    }
    if (centralOffset + centralSize > i) {
      throw const FormatException('Invalid subtitle ZIP directory');
    }
    return;
  }
  throw const FormatException('Subtitle ZIP directory was missing');
}

bool _hasPrefixAt(Uint8List bytes, int offset, List<int> prefix) {
  if (offset < 0 || offset + prefix.length > bytes.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[offset + i] != prefix[i]) return false;
  }
  return true;
}

int _uint16Le(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint32Le(Uint8List bytes, int offset) =>
    _uint16Le(bytes, offset) | (_uint16Le(bytes, offset + 2) << 16);

Uint8List _decodeGzipBounded(Uint8List bytes) {
  if (bytes.length < 18 || bytes[2] != 8) {
    throw const FormatException('Invalid gzip subtitle payload');
  }
  final flags = bytes[3];
  if (flags & 0xe0 != 0) {
    throw const FormatException('Invalid gzip flags');
  }

  var offset = 10;
  final trailerOffset = bytes.length - 8;
  if (flags & 0x04 != 0) {
    if (offset + 2 > trailerOffset) {
      throw const FormatException('Truncated gzip extra field');
    }
    final extraLength = bytes[offset] | (bytes[offset + 1] << 8);
    offset += 2 + extraLength;
  }
  if (flags & 0x08 != 0) {
    offset = _skipZeroTerminated(bytes, offset, trailerOffset);
  }
  if (flags & 0x10 != 0) {
    offset = _skipZeroTerminated(bytes, offset, trailerOffset);
  }
  if (flags & 0x02 != 0) offset += 2;
  if (offset > trailerOffset) {
    throw const FormatException('Truncated gzip header');
  }

  final declaredSize =
      bytes[trailerOffset + 4] |
      (bytes[trailerOffset + 5] << 8) |
      (bytes[trailerOffset + 6] << 16) |
      (bytes[trailerOffset + 7] << 24);
  if (declaredSize > maxDecodedSubtitleBytes) {
    throw const FormatException('Decoded gzip subtitle was too large');
  }

  final output = _BoundedOutputStream(maxDecodedSubtitleBytes);
  Inflate(bytes.sublist(offset, trailerOffset), output: output);
  final result = output.getBytes();
  if (result.length != declaredSize) {
    throw const FormatException('Gzip subtitle size did not match its trailer');
  }
  return result;
}

int _skipZeroTerminated(Uint8List bytes, int offset, int end) {
  while (offset < end && bytes[offset] != 0) {
    offset++;
  }
  if (offset >= end) {
    throw const FormatException('Truncated gzip header string');
  }
  return offset + 1;
}

Uint8List _decodeZipEntryBounded(ArchiveFile entry) {
  final rawContent = entry.rawContent;
  if (rawContent is! ZipFile) {
    throw const FormatException('ZIP subtitle entry had invalid content');
  }
  final compressed = rawContent.getRawContent();
  if (compressed.length > maxSubtitleResponseBytes) {
    throw const FormatException('Compressed ZIP subtitle was too large');
  }

  final output = _BoundedOutputStream(maxDecodedSubtitleBytes);
  switch (entry.compression) {
    case CompressionType.none:
      output.writeBytes(compressed);
      break;
    case CompressionType.deflate:
      Inflate(compressed, output: output);
      break;
    default:
      throw const FormatException('Unsupported ZIP subtitle compression');
  }
  final result = output.getBytes();
  if (result.length != entry.size) {
    throw const FormatException('ZIP subtitle size did not match its metadata');
  }
  return result;
}

class _BoundedOutputStream extends OutputStream {
  _BoundedOutputStream(this.maxLength)
    : _buffer = Uint8List(maxLength < 32768 ? maxLength : 32768),
      super(byteOrder: ByteOrder.littleEndian);

  final int maxLength;
  Uint8List _buffer;

  @override
  int length = 0;

  void _reserve(int additional) {
    final required = length + additional;
    if (required > maxLength) {
      throw const FormatException('Decoded subtitle exceeded its size limit');
    }
    if (required <= _buffer.length) return;
    var nextLength = _buffer.length;
    while (nextLength < required) {
      nextLength = (nextLength * 2).clamp(required, maxLength);
    }
    final next = Uint8List(nextLength)..setRange(0, length, _buffer);
    _buffer = next;
  }

  @override
  void writeByte(int value) {
    _reserve(1);
    _buffer[length++] = value;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _reserve(count);
    _buffer.setRange(this.length, this.length + count, bytes);
    this.length += count;
  }

  @override
  void writeStream(InputStream stream) {
    final count = stream.length;
    _reserve(count);
    writeBytes(stream.readBytes(count).toUint8List());
  }

  @override
  Uint8List subset(int start, [int? end]) {
    if (start < 0) start = length + start;
    if (end == null) {
      end = length;
    } else if (end < 0) {
      end = length + end;
    }
    return Uint8List.sublistView(_buffer, start, end);
  }

  @override
  Uint8List getBytes() => subset(0, length);

  @override
  void clear() {
    length = 0;
  }

  @override
  void flush() {}
}

bool _hasPrefix(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

String? _extensionOf(String name) {
  final match = RegExp(r'\.([^.?#/]+)$').firstMatch(name.toLowerCase());
  final extension = match?.group(1);
  return _subtitleExtensions.contains(extension) ? extension : null;
}

String? _extensionFromFormat(Uri uri) {
  final format =
      (uri.queryParameters['fmt'] ?? uri.queryParameters['format'] ?? '')
          .toLowerCase();
  return _subtitleExtensions.contains(format) ? format : null;
}

String _extensionFromContent(String preview) {
  if (preview.startsWith('webvtt')) return 'vtt';
  if (preview.contains('[script info]')) return 'ass';
  if (preview.startsWith('<?xml') || preview.startsWith('<tt')) return 'ttml';
  return 'srt';
}
