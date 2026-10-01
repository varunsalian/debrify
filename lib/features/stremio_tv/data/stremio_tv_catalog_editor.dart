import '../../../models/stremio_addon.dart';
import '../models/stremio_tv_catalog_option.dart';
import '../models/stremio_tv_catalog_picker_result.dart';

class StremioTvCatalogEditor {
  const StremioTvCatalogEditor({
    required this.read,
    required this.add,
    required this.update,
    required this.isCurrent,
  });
  final Future<List<Map<String, dynamic>>> Function() read;
  final Future<bool> Function(Map<String, dynamic>, bool Function()) add,
      update;
  final bool Function() isCurrent;

  Future<List<StremioTvCatalogOption>?> load(String type) async {
    if (!isCurrent()) return null;
    final rows = await read();
    if (!isCurrent()) return null;
    final compatible =
        rows.where((c) => (c['type'] as String? ?? 'movie') == type).toList()
          ..sort(
            (a, b) => (a['name'] as String? ?? '').toLowerCase().compareTo(
              (b['name'] as String? ?? '').toLowerCase(),
            ),
          );
    return List.unmodifiable(
      compatible.map(
        (c) => StremioTvCatalogOption(
          id: c['id'] as String? ?? '',
          name: c['name'] as String? ?? 'Unknown',
          searchName: c['name'] as String? ?? '',
          itemCount: (c['items'] as List<dynamic>? ?? []).length,
        ),
      ),
    );
  }

  Future<StremioTvCatalogPickerResult?> createCatalogWithItem({
    required String catalogName,
    required StremioMeta item,
    required bool Function() canContinue,
  }) async {
    bool current() => isCurrent() && canContinue();
    if (!current()) return null;
    final trimmedName = catalogName.trim();
    if (trimmedName.isEmpty) return null;

    final existing = await read();
    if (!current()) return null;
    if (existing.any(
      (catalog) => (catalog['name'] as String?) == trimmedName,
    )) {
      return const StremioTvCatalogPickerResult(
        message: 'A channel with that name already exists',
        duplicate: true,
      );
    }

    final added = await add({
      'id': _generateId(trimmedName),
      'name': trimmedName,
      'type': item.type,
      'addedAt': DateTime.now().toIso8601String(),
      'items': [item.toJson()],
    }, current);
    if (!current() || !added) return null;

    return StremioTvCatalogPickerResult(
      message: 'Created "$trimmedName" in Stremio TV',
      createdNew: true,
    );
  }

  Future<StremioTvCatalogPickerResult?> addItemToCatalog({
    required String catalogId,
    required StremioMeta item,
    required bool Function() canContinue,
  }) async {
    bool current() => isCurrent() && canContinue();
    if (!current()) return null;
    if (catalogId.isEmpty) return null;

    final existing = await read();
    if (!current()) return null;
    final index = existing.indexWhere((catalog) => catalog['id'] == catalogId);
    if (index < 0) return null;

    final catalog = Map<String, dynamic>.from(existing[index]);
    final catalogName = catalog['name'] as String? ?? 'Unknown';
    final items = List<Map<String, dynamic>>.from(
      (catalog['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>(),
    );

    if (_containsItem(items, item)) {
      return StremioTvCatalogPickerResult(
        message: '"${item.name}" is already in "$catalogName"',
        duplicate: true,
      );
    }

    items.add(item.toJson());
    catalog['items'] = items;
    catalog['updatedAt'] = DateTime.now().toIso8601String();

    final updated = await update(catalog, current);
    if (!current() || !updated) return null;

    return StremioTvCatalogPickerResult(
      message: 'Added "${item.name}" to "$catalogName"',
    );
  }

  static bool _containsItem(
    List<Map<String, dynamic>> items,
    StremioMeta target,
  ) {
    final targetKey = _identityKeyForMeta(target);
    if (targetKey == null) return false;

    for (final item in items) {
      final existingMeta = StremioMeta.fromJson({
        ...item,
        if (!item.containsKey('type')) 'type': target.type,
      });
      final existingKey = _identityKeyForMeta(existingMeta);
      if (existingKey == targetKey) {
        return true;
      }
    }
    return false;
  }

  static String? _identityKeyForMeta(StremioMeta item) {
    return item.effectiveImdbId ?? (item.id.isNotEmpty ? item.id : null);
  }

  static String _generateId(String name) {
    final sanitized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${sanitized}_$ts';
  }
}
