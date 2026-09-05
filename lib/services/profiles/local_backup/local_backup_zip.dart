import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';

/// Thrown when a local backup archive is damaged, truncated, or built from
/// entries this reader refuses (compressed, encrypted, unsafe names).
final class LocalBackupFormatException extends FormatException {
  const LocalBackupFormatException(super.message);
}

/// Thrown when an entry, manifest, or aggregate exceeds a configured bound.
final class LocalBackupLimitException extends FormatException {
  const LocalBackupLimitException(super.message);
}

/// Thrown after the user cancelled before publication.
final class LocalBackupCancelledException implements Exception {
  const LocalBackupCancelledException();

  @override
  String toString() => 'Backup operation cancelled';
}

/// Cooperative cancellation shared between UI and the streaming loops.
class LocalBackupCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const LocalBackupCancelledException();
  }
}

/// Byte-level progress for one streamed entry.
typedef LocalBackupByteProgress =
    void Function(String entryName, int bytesDone, int bytesTotal);

/// Streaming SHA-256 in the same base64url-without-padding shape the profile
/// package uses for its digests, so archive records and package records can be
/// compared directly.
class StreamedSha256 {
  StreamedSha256() {
    _input = sha256.startChunkedConversion(_output);
  }

  final _DigestSink _output = _DigestSink();
  late final ByteConversionSink _input;

  void add(List<int> chunk) => _input.add(chunk);

  String finish() {
    _input.close();
    return encodeDigest(_output.digest!.bytes);
  }

  static String encodeDigest(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Future<String> ofFile(
    File file, {
    LocalBackupCancellation? cancellation,
    int chunkSize = LocalBackupZip.chunkSize,
  }) async {
    final hasher = StreamedSha256();
    final input = await file.open();
    try {
      while (true) {
        cancellation?.throwIfCancelled();
        final chunk = await input.read(chunkSize);
        if (chunk.isEmpty) break;
        hasher.add(chunk);
      }
    } finally {
      await input.close();
    }
    return hasher.finish();
  }

  static Future<String> ofUtf8(
    String text, {
    int chunkChars = 64 * 1024,
  }) async {
    final hasher = StreamedSha256();
    for (var start = 0; start < text.length; start += chunkChars) {
      final end = start + chunkChars > text.length
          ? text.length
          : start + chunkChars;
      hasher.add(utf8.encode(text.substring(start, end)));
      // Let the UI isolate breathe between chunks.
      await Future<void>.delayed(Duration.zero);
    }
    return hasher.finish();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

/// A file to store in the archive under [name]. [bytes] must be the exact
/// file length; the writer refuses a source whose length changed.
class LocalBackupZipSource {
  const LocalBackupZipSource({
    required this.name,
    required this.file,
    required this.bytes,
  });

  final String name;
  final File file;
  final int bytes;
}

/// One entry of a parsed central directory.
class LocalBackupZipEntry {
  const LocalBackupZipEntry({
    required this.name,
    required this.bytes,
    required this.crc32,
    required this.localHeaderOffset,
  });

  final String name;
  final int bytes;
  final int crc32;
  final int localHeaderOffset;
}

/// A minimal ZIP container with stored (uncompressed) entries only.
///
/// The `archive` package's encoder and decoder process a whole entry
/// synchronously and buffer compressed entries in memory. Backups can be
/// hundreds of megabytes, so both directions here stream fixed-size chunks
/// with `await`s between them: bounded memory, cooperative cancellation, and
/// a UI isolate that keeps painting. Archives are standard ZIP (ZIP64 when
/// offsets require it) so any tool can inspect them.
class LocalBackupZip {
  LocalBackupZip._();

  static const int chunkSize = 256 * 1024;

  static const int _localHeaderSignature = 0x04034b50;
  static const int _centralHeaderSignature = 0x02014b50;
  static const int _endOfCentralDirectorySignature = 0x06054b50;
  static const int _zip64EndSignature = 0x06064b50;
  static const int _zip64LocatorSignature = 0x07064b50;
  static const int _utf8Flag = 0x0800;
  static const int _versionStored = 20;
  static const int _versionZip64 = 45;
  static const int _maxUint16 = 0xFFFF;
  static const int _maxUint32 = 0xFFFFFFFF;

  /// Entries above this are refused: the local header would need ZIP64 size
  /// fields and no supported device library approaches this size.
  static const int maxEntryBytes = _maxUint32 - 1;

  /// Entry names are generated by the exporter; anything else is rejected
  /// before a path is ever built from it.
  static final RegExp entryNamePattern = RegExp(
    r'^[a-z0-9][a-z0-9._-]{0,99}(/[a-z0-9][a-z0-9._-]{0,99}){0,3}$',
  );

  static bool isSafeEntryName(String name) =>
      name.length <= 240 &&
      entryNamePattern.hasMatch(name) &&
      !name.split('/').any((segment) => segment == '.' || segment == '..');

  // ---- Writing --------------------------------------------------------------

  /// Streams [sources] into [output] as stored entries. Returns each entry's
  /// CRC-32 by name. The output file is replaced if it already exists.
  static Future<Map<String, int>> write({
    required File output,
    required List<LocalBackupZipSource> sources,
    required DateTime modified,
    LocalBackupByteProgress? onProgress,
    LocalBackupCancellation? cancellation,
  }) async {
    final names = <String>{};
    for (final source in sources) {
      if (!isSafeEntryName(source.name)) {
        throw LocalBackupFormatException(
          'Unsafe archive entry name ${source.name}',
        );
      }
      if (!names.add(source.name)) {
        throw LocalBackupFormatException(
          'Duplicate archive entry ${source.name}',
        );
      }
      if (source.bytes < 0 || source.bytes > maxEntryBytes) {
        throw LocalBackupLimitException(
          'Archive entry ${source.name} exceeds the size limit',
        );
      }
    }
    if (sources.length > _maxUint16) {
      throw const LocalBackupLimitException('Too many archive entries');
    }
    final dosTime = _dosTime(modified);
    final dosDate = _dosDate(modified);
    if (await output.exists()) await output.delete();
    await output.parent.create(recursive: true);
    final sink = await output.open(mode: FileMode.write);
    final crcs = <String, int>{};
    final centralRecords = <_CentralRecord>[];
    var position = 0;
    try {
      for (final source in sources) {
        cancellation?.throwIfCancelled();
        final nameBytes = utf8.encode(source.name);
        final header = ByteData(30);
        header.setUint32(0, _localHeaderSignature, Endian.little);
        header.setUint16(4, _versionStored, Endian.little);
        header.setUint16(6, _utf8Flag, Endian.little);
        header.setUint16(8, 0, Endian.little);
        header.setUint16(10, dosTime, Endian.little);
        header.setUint16(12, dosDate, Endian.little);
        // CRC is patched after streaming; sizes are known up front.
        header.setUint32(14, 0, Endian.little);
        header.setUint32(18, source.bytes, Endian.little);
        header.setUint32(22, source.bytes, Endian.little);
        header.setUint16(26, nameBytes.length, Endian.little);
        header.setUint16(28, 0, Endian.little);
        final headerOffset = position;
        await sink.writeFrom(header.buffer.asUint8List());
        await sink.writeFrom(nameBytes);
        position += 30 + nameBytes.length;

        final input = await source.file.open();
        var crc = 0;
        var written = 0;
        try {
          while (true) {
            cancellation?.throwIfCancelled();
            final chunk = await input.read(chunkSize);
            if (chunk.isEmpty) break;
            written += chunk.length;
            if (written > source.bytes) {
              throw LocalBackupFormatException(
                'Source ${source.name} grew while packing',
              );
            }
            crc = getCrc32(chunk, crc);
            await sink.writeFrom(chunk);
            onProgress?.call(source.name, written, source.bytes);
          }
        } finally {
          await input.close();
        }
        if (written != source.bytes) {
          throw LocalBackupFormatException(
            'Source ${source.name} shrank while packing',
          );
        }
        position += written;
        final crcField = ByteData(4)..setUint32(0, crc, Endian.little);
        await sink.setPosition(headerOffset + 14);
        await sink.writeFrom(crcField.buffer.asUint8List());
        await sink.setPosition(position);
        crcs[source.name] = crc;
        centralRecords.add(
          _CentralRecord(
            nameBytes: nameBytes,
            bytes: source.bytes,
            crc32: crc,
            localHeaderOffset: headerOffset,
          ),
        );
      }

      final centralStart = position;
      for (final record in centralRecords) {
        final zip64Offset = record.localHeaderOffset > _maxUint32;
        final extra = BytesBuilder(copy: false);
        if (zip64Offset) {
          final field = ByteData(12);
          field.setUint16(0, 0x0001, Endian.little);
          field.setUint16(2, 8, Endian.little);
          field.setUint64(4, record.localHeaderOffset, Endian.little);
          extra.add(field.buffer.asUint8List());
        }
        final extraBytes = extra.takeBytes();
        final header = ByteData(46);
        header.setUint32(0, _centralHeaderSignature, Endian.little);
        header.setUint16(
          4,
          zip64Offset ? _versionZip64 : _versionStored,
          Endian.little,
        );
        header.setUint16(
          6,
          zip64Offset ? _versionZip64 : _versionStored,
          Endian.little,
        );
        header.setUint16(8, _utf8Flag, Endian.little);
        header.setUint16(10, 0, Endian.little);
        header.setUint16(12, dosTime, Endian.little);
        header.setUint16(14, dosDate, Endian.little);
        header.setUint32(16, record.crc32, Endian.little);
        header.setUint32(20, record.bytes, Endian.little);
        header.setUint32(24, record.bytes, Endian.little);
        header.setUint16(28, record.nameBytes.length, Endian.little);
        header.setUint16(30, extraBytes.length, Endian.little);
        header.setUint16(32, 0, Endian.little);
        header.setUint16(34, 0, Endian.little);
        header.setUint16(36, 0, Endian.little);
        header.setUint32(38, 0, Endian.little);
        header.setUint32(
          42,
          zip64Offset ? _maxUint32 : record.localHeaderOffset,
          Endian.little,
        );
        await sink.writeFrom(header.buffer.asUint8List());
        await sink.writeFrom(record.nameBytes);
        if (extraBytes.isNotEmpty) await sink.writeFrom(extraBytes);
        position += 46 + record.nameBytes.length + extraBytes.length;
      }
      final centralSize = position - centralStart;
      final needsZip64End =
          centralStart > _maxUint32 || centralSize > _maxUint32;
      if (needsZip64End) {
        final zip64End = ByteData(56);
        zip64End.setUint32(0, _zip64EndSignature, Endian.little);
        zip64End.setUint64(4, 44, Endian.little);
        zip64End.setUint16(12, _versionZip64, Endian.little);
        zip64End.setUint16(14, _versionZip64, Endian.little);
        zip64End.setUint32(16, 0, Endian.little);
        zip64End.setUint32(20, 0, Endian.little);
        zip64End.setUint64(24, centralRecords.length, Endian.little);
        zip64End.setUint64(32, centralRecords.length, Endian.little);
        zip64End.setUint64(40, centralSize, Endian.little);
        zip64End.setUint64(48, centralStart, Endian.little);
        final zip64EndOffset = position;
        await sink.writeFrom(zip64End.buffer.asUint8List());
        position += 56;
        final locator = ByteData(20);
        locator.setUint32(0, _zip64LocatorSignature, Endian.little);
        locator.setUint32(4, 0, Endian.little);
        locator.setUint64(8, zip64EndOffset, Endian.little);
        locator.setUint32(16, 1, Endian.little);
        await sink.writeFrom(locator.buffer.asUint8List());
        position += 20;
      }
      final end = ByteData(22);
      end.setUint32(0, _endOfCentralDirectorySignature, Endian.little);
      end.setUint16(4, 0, Endian.little);
      end.setUint16(6, 0, Endian.little);
      end.setUint16(8, centralRecords.length, Endian.little);
      end.setUint16(10, centralRecords.length, Endian.little);
      end.setUint32(
        12,
        needsZip64End ? _maxUint32 : centralSize,
        Endian.little,
      );
      end.setUint32(
        16,
        needsZip64End ? _maxUint32 : centralStart,
        Endian.little,
      );
      end.setUint16(20, 0, Endian.little);
      await sink.writeFrom(end.buffer.asUint8List());
      await sink.flush();
    } catch (_) {
      await sink.close();
      try {
        if (await output.exists()) await output.delete();
      } catch (_) {}
      rethrow;
    }
    await sink.close();
    return crcs;
  }

  // ---- Reading --------------------------------------------------------------

  /// Reads only the first bytes of [file]: true when it starts like a ZIP
  /// local header. Legacy JSON backups start with `{`.
  static Future<bool> looksLikeArchive(File file) async {
    final input = await file.open();
    try {
      final head = await input.read(4);
      return head.length == 4 &&
          head[0] == 0x50 &&
          head[1] == 0x4B &&
          head[2] == 0x03 &&
          head[3] == 0x04;
    } finally {
      await input.close();
    }
  }

  static int _dosTime(DateTime time) =>
      ((time.hour & 0x1F) << 11) |
      ((time.minute & 0x3F) << 5) |
      ((time.second ~/ 2) & 0x1F);

  static int _dosDate(DateTime time) {
    final year = time.year < 1980 ? 1980 : time.year;
    return (((year - 1980) & 0x7F) << 9) |
        ((time.month & 0x0F) << 5) |
        (time.day & 0x1F);
  }
}

class _CentralRecord {
  const _CentralRecord({
    required this.nameBytes,
    required this.bytes,
    required this.crc32,
    required this.localHeaderOffset,
  });

  final List<int> nameBytes;
  final int bytes;
  final int crc32;
  final int localHeaderOffset;
}

/// Bounded reader for archives produced by [LocalBackupZip.write] (or any
/// stored-entry ZIP). The central directory is parsed once under a size cap;
/// entry bytes are streamed on demand with CRC-32 and SHA-256 computed on the
/// way through.
class LocalBackupZipReader {
  LocalBackupZipReader._(this._file, this._length, this.entries);

  static const int maxEntries = 4096;
  static const int maxCentralDirectoryBytes = 4 * 1024 * 1024;
  static const int _maxCommentBytes = 0xFFFF;

  final RandomAccessFile _file;
  final int _length;
  final List<LocalBackupZipEntry> entries;

  static Future<LocalBackupZipReader> open(File file) async {
    final length = await file.length();
    if (length < 22) {
      throw const LocalBackupFormatException('Backup archive is truncated');
    }
    final raf = await file.open();
    try {
      final entries = await _readCentralDirectory(raf, length);
      return LocalBackupZipReader._(raf, length, entries);
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }

  Future<void> close() => _file.close();

  LocalBackupZipEntry? find(String name) {
    for (final entry in entries) {
      if (entry.name == name) return entry;
    }
    return null;
  }

  /// Streams one entry through [onChunk], verifying the stored CRC-32 and
  /// returning the SHA-256. Throws before any partial result is trusted.
  Future<String> _stream(
    LocalBackupZipEntry entry, {
    required FutureOr<void> Function(Uint8List chunk) onChunk,
    LocalBackupByteProgress? onProgress,
    LocalBackupCancellation? cancellation,
  }) async {
    final dataOffset = await _dataOffset(entry);
    if (dataOffset + entry.bytes > _length) {
      throw const LocalBackupFormatException('Backup archive is truncated');
    }
    await _file.setPosition(dataOffset);
    final hasher = StreamedSha256();
    var crc = 0;
    var remaining = entry.bytes;
    var done = 0;
    while (remaining > 0) {
      cancellation?.throwIfCancelled();
      final want = remaining < LocalBackupZip.chunkSize
          ? remaining
          : LocalBackupZip.chunkSize;
      final chunk = await _file.read(want);
      if (chunk.isEmpty) {
        throw const LocalBackupFormatException('Backup archive is truncated');
      }
      remaining -= chunk.length;
      done += chunk.length;
      crc = getCrc32(chunk, crc);
      hasher.add(chunk);
      await onChunk(chunk);
      onProgress?.call(entry.name, done, entry.bytes);
    }
    if (crc != entry.crc32) {
      throw LocalBackupFormatException(
        'Archive entry ${entry.name} failed its CRC check',
      );
    }
    return hasher.finish();
  }

  /// Extracts [entry] to [destination], replacing it. Returns the SHA-256.
  Future<String> extract(
    LocalBackupZipEntry entry,
    File destination, {
    LocalBackupByteProgress? onProgress,
    LocalBackupCancellation? cancellation,
  }) async {
    await destination.parent.create(recursive: true);
    if (await destination.exists()) await destination.delete();
    final output = await destination.open(mode: FileMode.write);
    try {
      final digest = await _stream(
        entry,
        onChunk: (chunk) => output.writeFrom(chunk),
        onProgress: onProgress,
        cancellation: cancellation,
      );
      await output.flush();
      await output.close();
      if (await destination.length() != entry.bytes) {
        throw LocalBackupFormatException(
          'Extracted entry ${entry.name} has the wrong size',
        );
      }
      return digest;
    } catch (_) {
      try {
        await output.close();
      } catch (_) {}
      try {
        if (await destination.exists()) await destination.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Hashes [entry] in place without extracting it.
  Future<String> digest(
    LocalBackupZipEntry entry, {
    LocalBackupByteProgress? onProgress,
    LocalBackupCancellation? cancellation,
  }) => _stream(
    entry,
    onChunk: (_) {},
    onProgress: onProgress,
    cancellation: cancellation,
  );

  /// Reads a small entry (manifest, digest stamp) entirely, refusing anything
  /// above [maxBytes].
  Future<Uint8List> readSmall(
    LocalBackupZipEntry entry, {
    required int maxBytes,
  }) async {
    if (entry.bytes > maxBytes) {
      throw LocalBackupLimitException(
        'Archive entry ${entry.name} exceeds its size limit',
      );
    }
    final builder = BytesBuilder(copy: false);
    await _stream(entry, onChunk: builder.add);
    return builder.takeBytes();
  }

  Future<int> _dataOffset(LocalBackupZipEntry entry) async {
    if (entry.localHeaderOffset < 0 || entry.localHeaderOffset + 30 > _length) {
      throw const LocalBackupFormatException('Backup archive is truncated');
    }
    await _file.setPosition(entry.localHeaderOffset);
    final raw = await _file.read(30);
    if (raw.length != 30) {
      throw const LocalBackupFormatException('Backup archive is truncated');
    }
    final header = ByteData.sublistView(raw);
    if (header.getUint32(0, Endian.little) !=
        LocalBackupZip._localHeaderSignature) {
      throw const LocalBackupFormatException('Archive entry header is invalid');
    }
    final flags = header.getUint16(6, Endian.little);
    final method = header.getUint16(8, Endian.little);
    if (method != 0 || (flags & 0x0001) != 0) {
      throw const LocalBackupFormatException(
        'Only stored, unencrypted archive entries are supported',
      );
    }
    final nameLength = header.getUint16(26, Endian.little);
    final extraLength = header.getUint16(28, Endian.little);
    final nameBytes = await _file.read(nameLength);
    if (nameBytes.length != nameLength) {
      throw const LocalBackupFormatException('Backup archive is truncated');
    }
    if (utf8.decode(nameBytes, allowMalformed: true) != entry.name) {
      throw const LocalBackupFormatException(
        'Archive entry name does not match its directory record',
      );
    }
    return entry.localHeaderOffset + 30 + nameLength + extraLength;
  }

  static Future<List<LocalBackupZipEntry>> _readCentralDirectory(
    RandomAccessFile file,
    int length,
  ) async {
    final tailLength = length < 22 + _maxCommentBytes
        ? length
        : 22 + _maxCommentBytes;
    await file.setPosition(length - tailLength);
    final tail = await file.read(tailLength);
    var endOffset = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] == 0x50 &&
          tail[i + 1] == 0x4B &&
          tail[i + 2] == 0x05 &&
          tail[i + 3] == 0x06) {
        endOffset = i;
        break;
      }
    }
    if (endOffset < 0) {
      throw const LocalBackupFormatException(
        'Backup archive is truncated or not a ZIP file',
      );
    }
    final end = ByteData.sublistView(tail, endOffset);
    var entryCount = end.getUint16(10, Endian.little);
    var centralSize = end.getUint32(12, Endian.little);
    var centralOffset = end.getUint32(16, Endian.little);
    if (end.getUint16(4, Endian.little) != 0 ||
        end.getUint16(6, Endian.little) != 0) {
      throw const LocalBackupFormatException(
        'Multi-part archives are not supported',
      );
    }
    final endAbsolute = length - tailLength + endOffset;
    if (entryCount == LocalBackupZip._maxUint16 ||
        centralSize == LocalBackupZip._maxUint32 ||
        centralOffset == LocalBackupZip._maxUint32) {
      final locatorOffset = endAbsolute - 20;
      if (locatorOffset < 0) {
        throw const LocalBackupFormatException('ZIP64 locator is missing');
      }
      await file.setPosition(locatorOffset);
      final locator = ByteData.sublistView(await file.read(20));
      if (locator.lengthInBytes != 20 ||
          locator.getUint32(0, Endian.little) !=
              LocalBackupZip._zip64LocatorSignature) {
        throw const LocalBackupFormatException('ZIP64 locator is invalid');
      }
      final zip64EndOffset = locator.getUint64(8, Endian.little);
      if (zip64EndOffset < 0 || zip64EndOffset + 56 > length) {
        throw const LocalBackupFormatException('ZIP64 record is invalid');
      }
      await file.setPosition(zip64EndOffset);
      final zip64End = ByteData.sublistView(await file.read(56));
      if (zip64End.lengthInBytes != 56 ||
          zip64End.getUint32(0, Endian.little) !=
              LocalBackupZip._zip64EndSignature) {
        throw const LocalBackupFormatException('ZIP64 record is invalid');
      }
      final count = zip64End.getUint64(32, Endian.little);
      final size = zip64End.getUint64(40, Endian.little);
      final offset = zip64End.getUint64(48, Endian.little);
      if (count < 0 || size < 0 || offset < 0) {
        throw const LocalBackupFormatException('ZIP64 record is invalid');
      }
      entryCount = count;
      centralSize = size;
      centralOffset = offset;
    }
    if (entryCount > maxEntries) {
      throw const LocalBackupLimitException(
        'Backup archive has too many entries',
      );
    }
    if (centralSize > maxCentralDirectoryBytes) {
      throw const LocalBackupLimitException(
        'Backup archive directory is too large',
      );
    }
    if (centralOffset + centralSize > length) {
      throw const LocalBackupFormatException('Backup archive is truncated');
    }
    await file.setPosition(centralOffset);
    final central = await file.read(centralSize);
    if (central.length != centralSize) {
      throw const LocalBackupFormatException('Backup archive is truncated');
    }
    final entries = <LocalBackupZipEntry>[];
    final seen = <String>{};
    var cursor = 0;
    for (var index = 0; index < entryCount; index++) {
      if (cursor + 46 > central.length) {
        throw const LocalBackupFormatException(
          'Backup archive directory is truncated',
        );
      }
      final header = ByteData.sublistView(central, cursor, cursor + 46);
      if (header.getUint32(0, Endian.little) !=
          LocalBackupZip._centralHeaderSignature) {
        throw const LocalBackupFormatException(
          'Backup archive directory is invalid',
        );
      }
      final flags = header.getUint16(8, Endian.little);
      final method = header.getUint16(10, Endian.little);
      final crc = header.getUint32(16, Endian.little);
      var compressedSize = header.getUint32(20, Endian.little);
      var uncompressedSize = header.getUint32(24, Endian.little);
      final nameLength = header.getUint16(28, Endian.little);
      final extraLength = header.getUint16(30, Endian.little);
      final commentLength = header.getUint16(32, Endian.little);
      var localOffset = header.getUint32(42, Endian.little);
      cursor += 46;
      if (cursor + nameLength + extraLength + commentLength > central.length) {
        throw const LocalBackupFormatException(
          'Backup archive directory is truncated',
        );
      }
      final name = utf8.decode(
        central.sublist(cursor, cursor + nameLength),
        allowMalformed: true,
      );
      cursor += nameLength;
      final extra = central.sublist(cursor, cursor + extraLength);
      cursor += extraLength + commentLength;
      if (method != 0 || (flags & 0x0001) != 0) {
        throw const LocalBackupFormatException(
          'Only stored, unencrypted archive entries are supported',
        );
      }
      if (uncompressedSize == LocalBackupZip._maxUint32 ||
          compressedSize == LocalBackupZip._maxUint32 ||
          localOffset == LocalBackupZip._maxUint32) {
        final zip64 = _zip64Extra(extra);
        if (zip64 == null) {
          throw const LocalBackupFormatException('ZIP64 extra field missing');
        }
        var field = 0;
        if (uncompressedSize == LocalBackupZip._maxUint32) {
          uncompressedSize = zip64.readField(field++);
        }
        if (compressedSize == LocalBackupZip._maxUint32) {
          compressedSize = zip64.readField(field++);
        }
        if (localOffset == LocalBackupZip._maxUint32) {
          localOffset = zip64.readField(field++);
        }
      }
      if (compressedSize != uncompressedSize) {
        throw const LocalBackupFormatException(
          'Stored archive entry sizes disagree',
        );
      }
      if (name.endsWith('/') || !LocalBackupZip.isSafeEntryName(name)) {
        throw LocalBackupFormatException('Unsafe archive entry name $name');
      }
      if (!seen.add(name)) {
        throw LocalBackupFormatException('Duplicate archive entry $name');
      }
      if (uncompressedSize < 0 ||
          uncompressedSize > LocalBackupZip.maxEntryBytes ||
          localOffset < 0 ||
          localOffset >= length) {
        throw const LocalBackupFormatException(
          'Backup archive directory is invalid',
        );
      }
      entries.add(
        LocalBackupZipEntry(
          name: name,
          bytes: uncompressedSize,
          crc32: crc,
          localHeaderOffset: localOffset,
        ),
      );
    }
    return entries;
  }

  static _Zip64Extra? _zip64Extra(Uint8List extra) {
    var cursor = 0;
    while (cursor + 4 <= extra.length) {
      final view = ByteData.sublistView(extra, cursor);
      final id = view.getUint16(0, Endian.little);
      final size = view.getUint16(2, Endian.little);
      if (cursor + 4 + size > extra.length) return null;
      if (id == 0x0001) {
        return _Zip64Extra(
          ByteData.sublistView(extra, cursor + 4, cursor + 4 + size),
        );
      }
      cursor += 4 + size;
    }
    return null;
  }
}

class _Zip64Extra {
  const _Zip64Extra(this.data);

  final ByteData data;

  int readField(int index) {
    final offset = index * 8;
    if (offset + 8 > data.lengthInBytes) {
      throw const LocalBackupFormatException('ZIP64 extra field is short');
    }
    final value = data.getUint64(offset, Endian.little);
    if (value < 0) {
      throw const LocalBackupFormatException('ZIP64 extra field is invalid');
    }
    return value;
  }
}
