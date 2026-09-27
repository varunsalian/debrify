/// Reads a complete badge snapshot in displayed-title order.
class HomeBoundCountsRepository {
  const HomeBoundCountsRepository({required this.readCount});
  final Future<int> Function(String id, bool Function() isCurrent) readCount;

  Future<Map<String, int>?> read(
    Iterable<String?> ids, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    final unique = ids.whereType<String>().where((id) => id.isNotEmpty).toSet();
    final counts = <String, int>{};
    for (final id in unique) {
      if (!isCurrent()) return null;
      final int count;
      try {
        count = await readCount(id, isCurrent);
      } catch (_) {
        if (!isCurrent()) return null;
        rethrow;
      }
      if (!isCurrent()) return null;
      if (count > 0) counts[id] = count;
    }
    return Map.unmodifiable(counts);
  }
}
