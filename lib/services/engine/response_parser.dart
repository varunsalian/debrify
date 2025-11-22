import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/engine_config/engine_config.dart';

/// Exception thrown when response validation fails
class ResponseValidationException implements Exception {
  final String message;
  const ResponseValidationException(this.message);

  @override
  String toString() => 'ResponseValidationException: $message';
}

/// Handles parsing HTTP response bodies based on ResponseConfig
class ResponseParser {
  const ResponseParser();

  /// Parse already-decoded and unwrapped JSON based on config.
  ///
  /// This is the preferred method when the JSON has already been parsed
  /// and Jina-unwrapped by the caller (e.g., EngineExecutor).
  /// Returns the extracted results as `List<Map<String, dynamic>>`.
  List<Map<String, dynamic>> parseJson(
    dynamic jsonData,
    ResponseConfig config, {
    String searchType = 'keyword',
  }) {
    try {
      debugPrint('ResponseParser: Format: ${config.format}');
      debugPrint('ResponseParser: Search type: $searchType');
      debugPrint('ResponseParser: JSON type: ${jsonData.runtimeType}');

      // Validate pre-checks if configured (warn but don't fail)
      if (config.preChecks != null &&
          config.preChecks!.isNotEmpty &&
          jsonData is Map<String, dynamic>) {
        debugPrint('ResponseParser: Running ${config.preChecks!.length} pre-checks...');
        debugPrint('ResponseParser: JSON keys: ${jsonData.keys.toList()}');
        try {
          validatePreChecks(jsonData, config.preChecks!);
          debugPrint('ResponseParser: Pre-checks passed');
        } catch (e) {
          debugPrint('ResponseParser: Pre-check warning (continuing anyway): $e');
        }
      }

      // Navigate to results path
      final String resultsPath = config.getResultsPathForType(searchType);
      debugPrint('ResponseParser: Navigating to results path: "$resultsPath"');
      final dynamic results = navigatePath(jsonData, resultsPath);
      debugPrint('ResponseParser: Results type after path navigation: ${results?.runtimeType}');

      // Check if results are empty
      if (config.emptyCheck != null && isEmpty(results, config.emptyCheck!)) {
        debugPrint('ResponseParser: Results are empty (empty check triggered)');
        return const [];
      }

      // Handle null or empty results
      if (results == null) {
        debugPrint('ResponseParser: Results are null');
        return const [];
      }

      // Convert to list
      List<dynamic> itemsList;
      if (results is List) {
        itemsList = results;
        debugPrint('ResponseParser: Results is a List with ${results.length} items');
      } else if (results is Map) {
        itemsList = [results];
        debugPrint('ResponseParser: Results is a single Map, wrapping in list');
      } else {
        debugPrint('ResponseParser: Unexpected results type: ${results.runtimeType}');
        return const [];
      }

      // Handle nested results if configured
      if (config.nestedResults != null && config.nestedResults!.enabled) {
        debugPrint('ResponseParser: Flattening nested results from field "${config.nestedResults!.itemsField}"');
        final flattened = flattenNestedResults(itemsList, config.nestedResults!);
        debugPrint('ResponseParser: Flattened to ${flattened.length} results');
        return flattened;
      }

      // Convert to List<Map<String, dynamic>>
      final resultList = _convertToMapList(itemsList);
      debugPrint('ResponseParser: Extracted ${resultList.length} results');
      return resultList;
    } catch (e, stackTrace) {
      if (e is ResponseValidationException) {
        debugPrint('ResponseParser: Validation failed: ${e.message}');
        rethrow;
      }
      debugPrint('ResponseParser.parseJson error: $e');
      debugPrint('ResponseParser.parseJson stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Parse response body based on config (legacy method that handles raw string).
  /// Returns the extracted results as `List<Map<String, dynamic>>`.
  List<Map<String, dynamic>> parse(
    String responseBody,
    ResponseConfig config, {
    String searchType = 'keyword',
  }) {
    try {
      String body = responseBody.trim();

      // Debug logging for troubleshooting
      debugPrint('ResponseParser: Raw body length: ${responseBody.length}');
      debugPrint('ResponseParser: Format: ${config.format}');
      debugPrint('ResponseParser: Search type: $searchType');

      // Step 1: Handle Jina-wrapped responses
      // Jina.ai returns: {"code":200, "data": {"content": "{...actual JSON...}"}, ...}
      dynamic jsonData;
      if (config.format == 'jina_wrapped') {
        debugPrint('ResponseParser: Processing Jina-wrapped response...');
        try {
          final jinaResponse = json.decode(body);
          if (jinaResponse is Map<String, dynamic>) {
            // Try to get content from data.content (Jina's structure)
            final data = jinaResponse['data'];
            if (data is Map<String, dynamic> && data['content'] is String) {
              final contentStr = data['content'] as String;
              debugPrint('ResponseParser: Extracting JSON from data.content (length: ${contentStr.length})');
              jsonData = json.decode(contentStr);
              debugPrint('ResponseParser: Successfully parsed inner JSON');
            } else {
              // Fallback: maybe it's directly in the response
              debugPrint('ResponseParser: No data.content found, using response directly');
              jsonData = jinaResponse;
            }
          } else {
            jsonData = jinaResponse;
          }
        } catch (e) {
          debugPrint('ResponseParser: Error processing Jina response: $e');
          // Try legacy unwrap method
          if (config.jinaUnwrap != null) {
            body = unwrapJinaResponse(body, config.jinaUnwrap!);
          }
          jsonData = json.decode(body);
        }
      } else {
        // Step 2: Parse JSON directly for non-Jina responses
        debugPrint('ResponseParser: Parsing JSON...');
        jsonData = json.decode(body);
      }
      debugPrint('ResponseParser: JSON parsed, type: ${jsonData.runtimeType}');

      // Step 3: Validate pre-checks if configured (warn but don't fail)
      if (config.preChecks != null &&
          config.preChecks!.isNotEmpty &&
          jsonData is Map<String, dynamic>) {
        debugPrint('ResponseParser: Running ${config.preChecks!.length} pre-checks...');
        debugPrint('ResponseParser: JSON keys: ${jsonData.keys.toList()}');
        debugPrint('ResponseParser: JSON preview: ${body.length > 500 ? body.substring(0, 500) : body}');
        try {
          validatePreChecks(jsonData, config.preChecks!);
          debugPrint('ResponseParser: Pre-checks passed');
        } catch (e) {
          debugPrint('ResponseParser: Pre-check warning (continuing anyway): $e');
          // Continue processing instead of failing
        }
      }

      // Step 4: Navigate to results path
      final String resultsPath = config.getResultsPathForType(searchType);
      debugPrint('ResponseParser: Navigating to results path: "$resultsPath"');
      final dynamic results = navigatePath(jsonData, resultsPath);
      debugPrint('ResponseParser: Results type after path navigation: ${results?.runtimeType}');

      // Step 5: Check if results are empty
      if (config.emptyCheck != null && isEmpty(results, config.emptyCheck!)) {
        debugPrint('ResponseParser: Results are empty (empty check triggered)');
        return const [];
      }

      // Handle null or empty results
      if (results == null) {
        debugPrint('ResponseParser: Results are null');
        return const [];
      }

      // Step 6: Convert to list
      List<dynamic> itemsList;
      if (results is List) {
        itemsList = results;
        debugPrint('ResponseParser: Results is a List with ${results.length} items');
      } else if (results is Map) {
        // Single result, wrap in a list
        itemsList = [results];
        debugPrint('ResponseParser: Results is a single Map, wrapping in list');
      } else {
        debugPrint('ResponseParser: Unexpected results type: ${results.runtimeType}');
        return const [];
      }

      // Step 7: Handle nested results if configured
      if (config.nestedResults != null && config.nestedResults!.enabled) {
        debugPrint('ResponseParser: Flattening nested results from field "${config.nestedResults!.itemsField}"');
        final flattened = flattenNestedResults(itemsList, config.nestedResults!);
        debugPrint('ResponseParser: Flattened to ${flattened.length} results');
        return flattened;
      }

      // Step 8: Convert to List<Map<String, dynamic>>
      final resultList = _convertToMapList(itemsList);
      debugPrint('ResponseParser: Extracted ${resultList.length} results');
      return resultList;
    } catch (e, stackTrace) {
      if (e is ResponseValidationException) {
        debugPrint('ResponseParser: Validation failed: ${e.message}');
        rethrow;
      }
      debugPrint('ResponseParser.parse error: $e');
      debugPrint('ResponseParser.parse stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Extract JSON from Jina-wrapped response
  String unwrapJinaResponse(String body, JinaUnwrapConfig config) {
    if (config.method != 'json_extraction') {
      debugPrint('ResponseParser: Unknown jina unwrap method: ${config.method}');
      return body;
    }

    // Find JSON boundaries based on configured markers
    final String startMarker = config.jsonStart ?? '{';
    final String endMarker = config.jsonEnd ?? '}';

    final int jsonStart = body.indexOf(startMarker);
    final int jsonEnd = body.lastIndexOf(endMarker);

    if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
      final int previewLength = body.length > 120 ? 120 : body.length;
      throw FormatException(
        'Could not extract JSON from Jina response: ${body.substring(0, previewLength)}',
      );
    }

    return body.substring(jsonStart, jsonEnd + 1);
  }

  /// Navigate to results path (e.g., "data.movies" or "$" for root)
  dynamic navigatePath(dynamic data, String path) {
    if (path.isEmpty || path == r'$') {
      return data;
    }

    final List<String> segments = path.split('.');
    dynamic current = data;

    for (final segment in segments) {
      if (current == null) {
        debugPrint('ResponseParser: Path navigation failed at segment "$segment" - current is null');
        return null;
      }

      if (current is Map) {
        current = current[segment];
      } else if (current is List && int.tryParse(segment) != null) {
        final int index = int.parse(segment);
        if (index >= 0 && index < current.length) {
          current = current[index];
        } else {
          debugPrint('ResponseParser: Array index $index out of bounds');
          return null;
        }
      } else {
        debugPrint('ResponseParser: Cannot navigate path "$segment" on ${current.runtimeType}');
        return null;
      }
    }

    return current;
  }

  /// Run pre-checks (e.g., status == "ok")
  void validatePreChecks(Map<String, dynamic> data, List<PreCheck> checks) {
    for (final check in checks) {
      final dynamic actualValue = navigatePath(data, check.field);

      // Handle different comparison scenarios
      bool matches = false;
      if (check.equals == null) {
        matches = actualValue == null;
      } else if (check.equals is bool) {
        matches = actualValue == check.equals;
      } else if (check.equals is num && actualValue is num) {
        matches = actualValue == check.equals;
      } else {
        matches = actualValue?.toString() == check.equals.toString();
      }

      if (!matches) {
        final String errorMessage = check.errorMessage ??
            'Pre-check failed: ${check.field} expected "${check.equals}" but got "$actualValue"';
        throw ResponseValidationException(errorMessage);
      }
    }
  }

  /// Check if response is empty based on config
  bool isEmpty(dynamic data, EmptyCheckConfig config) {
    switch (config.type) {
      case 'array_empty':
        if (data == null) return true;
        if (data is List) return data.isEmpty;
        return false;

      case 'field_value':
        if (config.field == null) return data == null;
        final dynamic fieldValue = data is Map ? navigatePath(data, config.field!) : null;
        if (config.equals != null) {
          return fieldValue?.toString() == config.equals;
        }
        return fieldValue == null;

      case 'null_check':
        return data == null;

      default:
        debugPrint('ResponseParser: Unknown empty check type: ${config.type}');
        return data == null || (data is List && data.isEmpty);
    }
  }

  /// Handle nested results (e.g., YTS movies containing torrents)
  List<Map<String, dynamic>> flattenNestedResults(
    List<dynamic> items,
    NestedResultsConfig config,
  ) {
    final List<Map<String, dynamic>> flattenedResults = [];

    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        debugPrint('ResponseParser: Skipping non-map item in nested results');
        continue;
      }

      final dynamic nestedItems = item[config.itemsField];
      if (nestedItems == null || nestedItems is! List || nestedItems.isEmpty) {
        // No nested items, skip this parent
        continue;
      }

      // Extract parent fields to copy to each nested item
      final Map<String, dynamic> parentData = {};
      for (final parentField in config.parentFields) {
        dynamic value = item[parentField.source];

        // Try fallback if source is null or empty
        if ((value == null || (value is String && value.isEmpty)) &&
            parentField.fallback != null) {
          value = item[parentField.fallback];
        }

        // Apply transform if specified
        if (value != null && parentField.transform != null) {
          value = _applySimpleTransform(value, parentField.transform!);
        }

        if (value != null) {
          parentData[parentField.target] = value;
        }
      }

      // Flatten: add each nested item with parent data
      for (final nestedItem in nestedItems) {
        if (nestedItem is Map<String, dynamic>) {
          final Map<String, dynamic> mergedItem = {
            ...nestedItem,
            ...parentData,
          };
          flattenedResults.add(mergedItem);
        }
      }
    }

    return flattenedResults;
  }

  /// Convert list of dynamic items to list of maps
  List<Map<String, dynamic>> _convertToMapList(List<dynamic> items) {
    final List<Map<String, dynamic>> result = [];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        result.add(item);
      } else if (item is Map) {
        // Convert Map<dynamic, dynamic> to Map<String, dynamic>
        result.add(Map<String, dynamic>.from(item));
      } else {
        debugPrint('ResponseParser: Skipping non-map item: ${item.runtimeType}');
      }
    }
    return result;
  }

  /// Apply simple transform for parent field values
  dynamic _applySimpleTransform(dynamic value, String transform) {
    if (value == null) return null;

    switch (transform) {
      case 'lowercase':
        return value.toString().toLowerCase();
      case 'uppercase':
        return value.toString().toUpperCase();
      case 'trim':
        return value.toString().trim();
      case 'join_comma':
        if (value is List) {
          return value.join(', ');
        }
        return value;
      default:
        debugPrint('ResponseParser: Unknown transform: $transform');
        return value;
    }
  }
}
