import 'dart:convert';

import 'package:debrify/services/storage/stremio_catalog_storage.dart';

class LocalCatalogExportPayload {
  final String name;
  final String json;

  const LocalCatalogExportPayload({required this.name, required this.json});
}

class LocalCatalogExporter {
  LocalCatalogExporter._();

  static Future<LocalCatalogExportPayload?> loadCatalog({
    required String catalogId,
    required String catalogType,
  }) async {
    final catalogs = await StremioCatalogStorage.getStremioTvLocalCatalogs();
    Map<String, dynamic>? catalog;
    for (final candidate in catalogs) {
      if (candidate['id'] == catalogId &&
          (candidate['type'] as String? ?? 'movie') == catalogType) {
        catalog = candidate;
        break;
      }
    }
    if (catalog == null) return null;

    final rawName = (catalog['name'] as String? ?? '').trim();
    final name = rawName.isEmpty ? 'local_catalog' : rawName;

    return LocalCatalogExportPayload(
      name: name,
      json: const JsonEncoder.withIndent('  ').convert(catalog),
    );
  }
}
