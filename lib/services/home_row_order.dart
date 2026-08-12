/// Pure helpers for the user-defined order of Home rows.
///
/// The persisted list may contain rows that are currently unavailable (an
/// uninstalled addon, a disconnected tracker, or an empty list). Those ids are
/// deliberately retained: when the row comes back it returns to the position
/// the user chose. Rows introduced after the preference was saved append in
/// their existing canonical order.
class HomeRowOrder {
  HomeRowOrder._();

  /// Remove empty/duplicate ids without otherwise changing the saved order.
  static List<String> normalize(Iterable<String> ids) {
    final seen = <String>{};
    return [
      for (final id in ids)
        if (id.isNotEmpty && seen.add(id)) id,
    ];
  }

  /// Preserve every saved id and append newly discovered ids canonically.
  static List<String> reconcile(
    Iterable<String> saved,
    Iterable<String> discovered,
  ) {
    final out = normalize(saved);
    final seen = out.toSet();
    for (final id in discovered) {
      if (id.isNotEmpty && seen.add(id)) out.add(id);
    }
    return out;
  }

  /// Sort [values] by the saved ids. Unranked values append stably.
  static List<T> apply<T>(
    Iterable<T> values,
    Iterable<String> saved,
    String Function(T value) idOf,
  ) {
    final order = normalize(saved);
    if (order.isEmpty) return List<T>.of(values);
    final rank = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };
    final indexed = values.indexed.toList();
    indexed.sort((a, b) {
      final ar = rank[idOf(a.$2)];
      final br = rank[idOf(b.$2)];
      if (ar != null && br != null) return ar.compareTo(br);
      if (ar != null) return -1;
      if (br != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  /// Insert temporary rows immediately after the leading run accepted by
  /// [belongsToLeadingRun]. This keeps placeholders in their canonical family
  /// before a saved order is applied.
  static List<T> insertAfterLeadingRun<T>(
    Iterable<T> values,
    Iterable<T> inserted,
    bool Function(T value) belongsToLeadingRun,
  ) {
    final out = List<T>.of(values);
    final additions = List<T>.of(inserted);
    if (additions.isEmpty) return out;
    var index = 0;
    while (index < out.length && belongsToLeadingRun(out[index])) {
      index++;
    }
    out.insertAll(index, additions);
    return out;
  }

  /// Compare two order lists without allocating sets (order is meaningful).
  static bool equals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
