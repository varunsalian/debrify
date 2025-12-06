import 'package:flutter/foundation.dart';
import '../../models/engine_config/engine_config.dart';
import '../../models/torrent.dart';
import '../../utils/torrent_coverage_detector.dart';

/// Maps parsed API response data to Torrent objects
class FieldMapper {
  const FieldMapper();

  /// Map a single result to Torrent
  Torrent mapToTorrent(
    Map<String, dynamic> data,
    ResponseConfig config,
    String engineId, {
    String searchType = 'keyword',
  }) {
    final int nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Extract infohash first as it's required for rowid generation
    final String infohash = _extractStringField(
      data,
      'infohash',
      config,
      defaultValue: '',
    ).trim().toLowerCase();

    // Generate rowid from infohash
    final int rowid = infohash.isNotEmpty ? infohash.hashCode.abs() : 0;

    // Extract all other fields
    final String name = _extractStringField(
      data,
      'name',
      config,
      defaultValue: 'Unknown',
    );

    final int sizeBytes = _extractIntField(
      data,
      'size_bytes',
      config,
      defaultValue: 0,
    );

    final int createdUnix = _extractIntField(
      data,
      'created_unix',
      config,
      defaultValue: nowUnix,
    );

    final int seeders = _extractIntField(
      data,
      'seeders',
      config,
      defaultValue: 0,
    );

    final int leechers = _extractIntField(
      data,
      'leechers',
      config,
      defaultValue: 0,
    );

    final int completed = _extractIntField(
      data,
      'completed',
      config,
      defaultValue: 0,
    );

    final String? category = _extractNullableStringField(
      data,
      'category',
      config,
    );

    // Detect coverage type and generate transformed title
    // Only run coverage detection for IMDB/series searches (not keyword searches)
    CoverageInfo? coverage;
    if (searchType == 'imdb' || searchType == 'series') {
      try {
        coverage = TorrentCoverageDetector.detectCoverage(
          title: name,
          infohash: infohash,
        );
      } catch (e) {
        debugPrint('FieldMapper: Coverage detection failed: $e');
        // Continue without coverage info
      }
    }

    return Torrent(
      rowid: rowid,
      infohash: infohash,
      name: name,
      sizeBytes: sizeBytes,
      createdUnix: createdUnix,
      seeders: seeders,
      leechers: leechers,
      completed: completed,
      scrapedDate: nowUnix,
      category: category,
      source: engineId,
      coverageType: coverage?.coverageType.name,
      startSeason: coverage?.startSeason,
      endSeason: coverage?.endSeason,
      seasonNumber: coverage?.seasonNumber,
      transformedTitle: coverage?.transformedTitle,
      episodeIdentifier: coverage?.episodeIdentifier,
    );
  }

  /// Extract a string field with support for mapping, templates, and transforms
  String _extractStringField(
    Map<String, dynamic> data,
    String fieldName,
    ResponseConfig config, {
    required String defaultValue,
  }) {
    final value = getFieldValue(
      data,
      fieldName,
      config.fieldMapping,
      config.typeConversions,
      config.transforms,
      config.specialParsers,
    );

    if (value == null) return defaultValue;
    if (value is String) return value.isEmpty ? defaultValue : value;
    return value.toString();
  }

  /// Extract a nullable string field
  String? _extractNullableStringField(
    Map<String, dynamic> data,
    String fieldName,
    ResponseConfig config,
  ) {
    final value = getFieldValue(
      data,
      fieldName,
      config.fieldMapping,
      config.typeConversions,
      config.transforms,
      config.specialParsers,
    );

    if (value == null) return null;
    final String strValue = value.toString();
    return strValue.isEmpty ? null : strValue;
  }

  /// Extract an int field
  int _extractIntField(
    Map<String, dynamic> data,
    String fieldName,
    ResponseConfig config, {
    required int defaultValue,
  }) {
    final value = getFieldValue(
      data,
      fieldName,
      config.fieldMapping,
      config.typeConversions,
      config.transforms,
      config.specialParsers,
    );

    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      return int.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }

  /// Get field value with optional transformation
  dynamic getFieldValue(
    Map<String, dynamic> data,
    String fieldName,
    Map<String, String> fieldMapping,
    Map<String, String>? typeConversions,
    Map<String, dynamic>? transforms,
    Map<String, SpecialParserConfig>? specialParsers,
  ) {
    // Check if there's a special parser for this field
    if (specialParsers != null && specialParsers.containsKey(fieldName)) {
      return parseSpecial(data, fieldName, specialParsers[fieldName]!);
    }

    // Get the mapping for this field
    final String? mapping = fieldMapping[fieldName];
    if (mapping == null) {
      return null;
    }

    dynamic value;

    // Check if mapping is a template (contains {})
    if (mapping.contains('{') && mapping.contains('}')) {
      value = processTemplate(mapping, data);
    } else {
      // Direct field mapping - support dot notation
      value = _navigatePath(data, mapping);
    }

    // Apply type conversion if specified
    if (value != null && typeConversions != null && typeConversions.containsKey(fieldName)) {
      value = convertType(value, typeConversions[fieldName]!);
    }

    // Apply transform if specified
    if (value != null && transforms != null && transforms.containsKey(fieldName)) {
      value = applyTransform(value, transforms[fieldName]);
    }

    return value;
  }

  /// Navigate a dot-notation path in data
  dynamic _navigatePath(Map<String, dynamic> data, String path) {
    if (!path.contains('.')) {
      return data[path];
    }

    final List<String> segments = path.split('.');
    dynamic current = data;

    for (final segment in segments) {
      if (current == null) return null;

      if (current is Map) {
        current = current[segment];
      } else if (current is List && int.tryParse(segment) != null) {
        final int index = int.parse(segment);
        if (index >= 0 && index < current.length) {
          current = current[index];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }

    return current;
  }

  /// Process template strings like "{_movie_title} [{quality}]"
  String processTemplate(String template, Map<String, dynamic> data) {
    final RegExp placeholderRegex = RegExp(r'\{([^}]+)\}');
    String result = template;

    for (final match in placeholderRegex.allMatches(template)) {
      final String placeholder = match.group(0)!; // e.g., {quality}
      final String fieldPath = match.group(1)!; // e.g., quality

      dynamic value;

      // Handle special prefixes
      if (fieldPath.startsWith('_')) {
        // _fieldName refers to a previously extracted parent field
        value = data[fieldPath];
      } else {
        // Regular field path
        value = _navigatePath(data, fieldPath);
      }

      if (value != null) {
        result = result.replaceAll(placeholder, value.toString());
      } else {
        // Remove placeholder with empty string, but keep surrounding text
        result = result.replaceAll(placeholder, '');
      }
    }

    // Clean up extra spaces and brackets from empty replacements
    result = result.replaceAll(RegExp(r'\[\s*\]'), '');
    result = result.replaceAll(RegExp(r'\(\s*\)'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result.trim();
  }

  /// Apply type conversion
  dynamic convertType(dynamic value, String conversion) {
    if (value == null) return null;

    switch (conversion) {
      case 'int':
        if (value is int) return value;
        if (value is double) return value.round();
        if (value is String) return int.tryParse(value) ?? 0;
        return 0;

      case 'string_to_int':
        if (value is int) return value;
        if (value is String) return int.tryParse(value) ?? 0;
        return 0;

      case 'lowercase':
        return value.toString().toLowerCase();

      case 'uppercase':
        return value.toString().toUpperCase();

      case 'string':
        return value.toString();

      case 'bool':
        if (value is bool) return value;
        if (value is String) {
          return value.toLowerCase() == 'true' || value == '1';
        }
        if (value is num) return value != 0;
        return false;

      default:
        debugPrint('FieldMapper: Unknown type conversion: $conversion');
        return value;
    }
  }

  /// Apply transformation
  dynamic applyTransform(dynamic value, dynamic transform) {
    if (value == null) return null;

    // Handle string transform
    if (transform is String) {
      return _applyStringTransform(value, transform);
    }

    // Handle map transform with more complex operations
    if (transform is Map) {
      return _applyMapTransform(value, transform);
    }

    debugPrint('FieldMapper: Unknown transform type: ${transform.runtimeType}');
    return value;
  }

  /// Apply a simple string transform
  dynamic _applyStringTransform(dynamic value, String transform) {
    switch (transform) {
      case 'lowercase':
        return value.toString().toLowerCase();

      case 'uppercase':
        return value.toString().toUpperCase();

      case 'trim':
        return value.toString().trim();

      case 'join_comma':
        if (value is List) {
          return value.map((e) => e.toString()).join(', ');
        }
        return value.toString();

      case 'first_element':
        if (value is List && value.isNotEmpty) {
          return value.first;
        }
        return value;

      default:
        debugPrint('FieldMapper: Unknown string transform: $transform');
        return value;
    }
  }

  /// Apply a map-based transform (e.g., replace operations)
  dynamic _applyMapTransform(dynamic value, Map transform) {
    final String? type = transform['type']?.toString();

    switch (type) {
      case 'replace':
        final String? from = transform['from']?.toString();
        final String? to = transform['to']?.toString();
        if (from != null && to != null) {
          return value.toString().replaceAll(from, to);
        }
        return value;

      case 'regex_replace':
        final String? pattern = transform['pattern']?.toString();
        final String replacement = transform['replacement']?.toString() ?? '';
        if (pattern != null) {
          try {
            final RegExp regex = RegExp(pattern);
            return value.toString().replaceAll(regex, replacement);
          } catch (e) {
            debugPrint('FieldMapper: Invalid regex pattern: $pattern');
            return value;
          }
        }
        return value;

      case 'prefix':
        final String? prefix = transform['value']?.toString();
        if (prefix != null) {
          return '$prefix${value.toString()}';
        }
        return value;

      case 'suffix':
        final String? suffix = transform['value']?.toString();
        if (suffix != null) {
          return '${value.toString()}$suffix';
        }
        return value;

      case 'concat':
        final List<dynamic>? fields = transform['fields'] as List<dynamic>?;
        final String separator = transform['separator']?.toString() ?? ' ';
        if (fields != null && value is Map<String, dynamic>) {
          final List<String> parts = [];
          for (final field in fields) {
            final dynamic fieldValue = _navigatePath(value, field.toString());
            if (fieldValue != null) {
              parts.add(fieldValue.toString());
            }
          }
          return parts.join(separator);
        }
        return value;

      default:
        debugPrint('FieldMapper: Unknown map transform type: $type');
        return value;
    }
  }

  /// Parse using special parser (regex patterns)
  dynamic parseSpecial(
    Map<String, dynamic> data,
    String fieldName,
    SpecialParserConfig config,
  ) {
    // Get the source field value
    final dynamic sourceValue = _navigatePath(data, config.sourceField);
    if (sourceValue == null) {
      return config.defaultValue;
    }

    final String sourceStr = sourceValue.toString();

    try {
      final RegExp regex = RegExp(config.pattern);
      final RegExpMatch? match = regex.firstMatch(sourceStr);

      if (match == null) {
        return config.defaultValue;
      }

      final int captureGroup = config.captureGroup ?? 1;
      final String? captured = match.group(captureGroup);

      if (captured == null) {
        return config.defaultValue;
      }

      // Apply type-specific parsing
      switch (config.type) {
        case 'int':
          return int.tryParse(captured) ?? config.defaultValue ?? 0;

        case 'size_with_unit':
          return parseSizeWithUnit(captured, _extractUnit(sourceStr, captured));

        case 'string':
          return captured;

        case 'float':
        case 'double':
          return double.tryParse(captured) ?? config.defaultValue ?? 0.0;

        case 'datetime_iso':
        case 'datetime':
          return parseDateTimeToUnix(captured) ?? config.defaultValue ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

        default:
          return captured;
      }
    } catch (e) {
      debugPrint('FieldMapper: Special parser error for $fieldName: $e');
      return config.defaultValue;
    }
  }

  /// Extract unit from a size string after the number
  String _extractUnit(String fullStr, String number) {
    final int numIndex = fullStr.indexOf(number);
    if (numIndex == -1) return '';

    final String afterNumber = fullStr.substring(numIndex + number.length).trim();
    final RegExp unitRegex = RegExp(r'^([KMGT]?B|[KMGT]iB?)', caseSensitive: false);
    final RegExpMatch? match = unitRegex.firstMatch(afterNumber);
    return match?.group(1) ?? '';
  }

  /// Parse size with unit (e.g., "1.5 GB" -> bytes)
  int parseSizeWithUnit(String sizeStr, String unit) {
    try {
      // Clean up the size string
      final String cleanSize = sizeStr.replaceAll(RegExp(r'[^\d.]'), '');
      final double? sizeValue = double.tryParse(cleanSize);

      if (sizeValue == null) {
        debugPrint('FieldMapper: Could not parse size value: $sizeStr');
        return 0;
      }

      // Normalize unit
      final String normalizedUnit = unit.toUpperCase().trim();

      // Calculate multiplier based on unit
      int multiplier;
      switch (normalizedUnit) {
        case 'B':
        case 'BYTES':
          multiplier = 1;
          break;
        case 'KB':
        case 'KIB':
        case 'K':
          multiplier = 1024;
          break;
        case 'MB':
        case 'MIB':
        case 'M':
          multiplier = 1024 * 1024;
          break;
        case 'GB':
        case 'GIB':
        case 'G':
          multiplier = 1024 * 1024 * 1024;
          break;
        case 'TB':
        case 'TIB':
        case 'T':
          multiplier = 1024 * 1024 * 1024 * 1024;
          break;
        default:
          // Try to extract from the original sizeStr if unit wasn't separately provided
          if (sizeStr.toUpperCase().contains('GB') || sizeStr.toUpperCase().contains('GIB')) {
            multiplier = 1024 * 1024 * 1024;
          } else if (sizeStr.toUpperCase().contains('MB') || sizeStr.toUpperCase().contains('MIB')) {
            multiplier = 1024 * 1024;
          } else if (sizeStr.toUpperCase().contains('KB') || sizeStr.toUpperCase().contains('KIB')) {
            multiplier = 1024;
          } else if (sizeStr.toUpperCase().contains('TB') || sizeStr.toUpperCase().contains('TIB')) {
            multiplier = 1024 * 1024 * 1024 * 1024;
          } else {
            // Assume bytes
            multiplier = 1;
          }
      }

      return (sizeValue * multiplier).round();
    } catch (e) {
      debugPrint('FieldMapper: Error parsing size "$sizeStr" with unit "$unit": $e');
      return 0;
    }
  }

  /// Parse a size string that includes both number and unit (e.g., "1.5 GB")
  int parseSizeString(String sizeStr) {
    final RegExp sizeRegex = RegExp(
      r'([\d.]+)\s*([KMGT]?i?B|bytes?)',
      caseSensitive: false,
    );
    final RegExpMatch? match = sizeRegex.firstMatch(sizeStr);

    if (match == null) {
      debugPrint('FieldMapper: Could not parse size string: $sizeStr');
      return 0;
    }

    final String numberPart = match.group(1) ?? '0';
    final String unitPart = match.group(2) ?? 'B';

    return parseSizeWithUnit(numberPart, unitPart);
  }

  /// Parse a datetime string to Unix timestamp
  /// Supports ISO 8601 and common datetime formats
  int? parseDateTimeToUnix(String dateTimeStr) {
    try {
      // Try parsing as ISO 8601 or standard datetime format
      final DateTime dateTime = DateTime.parse(dateTimeStr);
      return dateTime.millisecondsSinceEpoch ~/ 1000;
    } catch (e) {
      debugPrint('FieldMapper: Could not parse datetime string: $dateTimeStr');
      return null;
    }
  }
}
