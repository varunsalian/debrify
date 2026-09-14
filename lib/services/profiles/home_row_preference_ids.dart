import 'dart:convert';

/// Home catalog rows embed a connection ID in `addonId:type:catalogId`.
/// Only these preferences use that grammar: replacing arbitrary string
/// prefixes would also change titles, URLs, and unrelated provider IDs.
abstract final class HomeRowPreferenceIds {
  static const keys = {'home_disabled_sections_v1', 'home_row_order_v1'};

  static Object? remap(
    String key,
    Object? value,
    Map<String, String> resourceIds, {
    Set<String> droppedResourceIds = const {},
  }) {
    if (!keys.contains(key) ||
        (resourceIds.isEmpty && droppedResourceIds.isEmpty)) {
      return value;
    }
    Object? rows = value;
    if (value is String) {
      try {
        rows = jsonDecode(value);
      } on FormatException {
        return value;
      }
    }
    if (rows is! List || rows.any((row) => row is! String)) return value;
    var changed = false;
    final result = <String>[];
    for (final row in rows.cast<String>()) {
      final first = row.indexOf(':');
      final second = first < 0 ? -1 : row.indexOf(':', first + 1);
      // Fixed rows (cw:movies, collection:ID, etc.) are not addon rows.
      if (first <= 0 || second <= first + 1 || second == row.length - 1) {
        result.add(row);
        continue;
      }
      final resource = row.substring(0, first);
      if (droppedResourceIds.contains(resource)) {
        changed = true;
        continue;
      }
      final replacement = resourceIds[resource];
      if (replacement == null || replacement == resource) {
        result.add(row);
      } else {
        result.add('$replacement${row.substring(first)}');
        changed = true;
      }
    }
    if (!changed) return value;
    return value is String ? jsonEncode(result) : result;
  }
}
