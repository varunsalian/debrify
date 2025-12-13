import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// Service for encoding/decoding channel YAML configs as debrify links
///
/// Debrify link format:
/// debrify://channel?v=1&name=ChannelName&data=base64&hash=sha256
class MagnetYamlService {
  static const String _debrifyPrefix = 'debrify://channel';
  static const String _currentVersion = '1';
  static const int _maxNameLength = 50;

  /// Encode YAML content into a debrify link
  ///
  /// Returns a debrify URI that can be shared via QR code, clipboard, etc.
  static String encode({
    required String yamlContent,
    required String channelName,
  }) {
    if (yamlContent.isEmpty) {
      throw MagnetYamlException('YAML content cannot be empty');
    }

    if (channelName.isEmpty) {
      throw MagnetYamlException('Channel name cannot be empty');
    }

    // Sanitize channel name for URL
    final sanitizedName = _sanitizeForUrl(channelName);

    // 1. Convert YAML to bytes
    final yamlBytes = utf8.encode(yamlContent);

    // 2. Compress with GZIP
    final gzipEncoder = GZipEncoder();
    final compressedBytes = gzipEncoder.encode(yamlBytes);
    if (compressedBytes == null) {
      throw MagnetYamlException('Failed to compress YAML content');
    }

    // 3. Base64 encode
    final base64Data = base64Url.encode(compressedBytes);

    // 4. Calculate hash for integrity check
    final hash = sha256.convert(yamlBytes);
    final hashHex = hash.toString().substring(0, 16); // First 16 chars

    // 5. Build debrify URI
    final params = [
      'v=$_currentVersion',
      'name=$sanitizedName',
      'data=$base64Data',
      'hash=$hashHex',
    ];

    return '$_debrifyPrefix?${params.join('&')}';
  }

  /// Decode a debrify link back to YAML content
  ///
  /// Returns the decoded YAML string
  /// Throws [MagnetYamlException] if the link is invalid or corrupted
  static MagnetYamlDecodeResult decode(String debrifyLink) {
    if (!isMagnetLink(debrifyLink)) {
      throw MagnetYamlException('Not a valid Debrify link');
    }

    try {
      // Parse URI
      final uri = Uri.parse(debrifyLink);
      final params = uri.queryParameters;

      // Extract parameters
      final version = params['v'];
      final name = params['name'];
      final data = params['data'];
      final hash = params['hash'];

      // Validate required fields
      if (version == null) {
        throw MagnetYamlException('Missing version parameter');
      }
      if (name == null) {
        throw MagnetYamlException('Missing name parameter');
      }
      if (data == null) {
        throw MagnetYamlException('Missing data parameter');
      }
      if (hash == null) {
        throw MagnetYamlException('Missing hash parameter');
      }

      // Check version compatibility
      if (version != _currentVersion) {
        throw MagnetYamlException(
          'Unsupported version: $version (expected: $_currentVersion)',
        );
      }

      // 1. Base64 decode
      final compressedBytes = base64Url.decode(data);

      // 2. Decompress with GZIP
      final gzipDecoder = GZipDecoder();
      final decompressedBytes = gzipDecoder.decodeBytes(compressedBytes);

      // 3. Verify hash
      final calculatedHash = sha256.convert(decompressedBytes);
      final calculatedHashHex = calculatedHash.toString().substring(0, 16);
      if (calculatedHashHex != hash) {
        throw MagnetYamlException('Hash mismatch - data may be corrupted');
      }

      // 4. Convert to string
      final yamlContent = utf8.decode(decompressedBytes);

      // Unsanitize name
      final channelName = Uri.decodeComponent(name);

      return MagnetYamlDecodeResult(
        yamlContent: yamlContent,
        channelName: channelName,
        version: version,
      );
    } on FormatException catch (e) {
      throw MagnetYamlException('Invalid debrify link format: ${e.message}');
    } on ArchiveException catch (e) {
      throw MagnetYamlException('Failed to decompress data: $e');
    } catch (e) {
      throw MagnetYamlException('Failed to decode debrify link: $e');
    }
  }

  /// Check if a string is a valid Debrify link
  static bool isMagnetLink(String input) {
    if (input.isEmpty) return false;

    final normalized = input.trim().toLowerCase();
    return normalized.startsWith('debrify://channel');
  }

  /// Normalize a debrify link (trim whitespace, decode URL encoding if needed)
  static String normalizeMagnetLink(String input) {
    return input.trim();
  }

  /// Get estimated size of debrify link for given YAML content
  static int estimateMagnetLinkSize(String yamlContent) {
    if (yamlContent.isEmpty) return 0;

    try {
      final yamlBytes = utf8.encode(yamlContent);
      final gzipEncoder = GZipEncoder();
      final compressedBytes = gzipEncoder.encode(yamlBytes);
      if (compressedBytes == null) return 0;

      final base64Data = base64Url.encode(compressedBytes);

      // Rough estimate: prefix + params + base64 data
      return _debrifyPrefix.length + 100 + base64Data.length;
    } catch (e) {
      return 0;
    }
  }

  /// Get compression ratio (original size / compressed size)
  static double getCompressionRatio(String yamlContent) {
    if (yamlContent.isEmpty) return 1.0;

    try {
      final yamlBytes = utf8.encode(yamlContent);
      final gzipEncoder = GZipEncoder();
      final compressedBytes = gzipEncoder.encode(yamlBytes);
      if (compressedBytes == null) return 1.0;

      return yamlBytes.length / compressedBytes.length;
    } catch (e) {
      return 1.0;
    }
  }

  /// Sanitize channel name for URL encoding
  static String _sanitizeForUrl(String name) {
    // Truncate if too long
    String sanitized = name.length > _maxNameLength
        ? name.substring(0, _maxNameLength)
        : name;

    // URL encode
    return Uri.encodeComponent(sanitized);
  }

  /// Extract channel name from debrify link without full decode
  static String? extractChannelName(String debrifyLink) {
    if (!isMagnetLink(debrifyLink)) return null;

    try {
      final uri = Uri.parse(debrifyLink);
      final name = uri.queryParameters['name'];
      if (name == null) return null;

      return Uri.decodeComponent(name);
    } catch (e) {
      return null;
    }
  }
}

/// Result of decoding a magnet link
class MagnetYamlDecodeResult {
  final String yamlContent;
  final String channelName;
  final String version;

  const MagnetYamlDecodeResult({
    required this.yamlContent,
    required this.channelName,
    required this.version,
  });

  @override
  String toString() {
    return 'MagnetYamlDecodeResult(channel: $channelName, version: $version, '
           'contentLength: ${yamlContent.length})';
  }
}

/// Exception thrown when magnet link operations fail
class MagnetYamlException implements Exception {
  final String message;

  const MagnetYamlException(this.message);

  @override
  String toString() => 'MagnetYamlException: $message';
}
