import 'package:debrify/features/search/data/catalog_search_repository.dart';
import 'package:debrify/features/search/models/catalog_search_row.dart';
import 'package:debrify/models/stremio_addon.dart';

class FakeCatalogSearchRepository implements CatalogSearchRepository {
  @override
  bool isCurrent = true;
  List<StremioAddon> addons = [];
  Set<String> disabled = {};
  final List<Set<String>> writes = [];
  final List<({String addon, String catalog, String query})> requests = [];
  Future<Set<String>> Function()? read;
  Future<void> Function(Set<String>)? write;
  Future<CatalogSearchRow?> Function(StremioAddon, StremioAddonCatalog, String)?
  fetch;

  @override
  Future<List<StremioAddon>> searchableAddons() async => addons;
  @override
  Future<Set<String>> readDisabledAddons() async =>
      read == null ? disabled : read!();
  @override
  Future<void> writeDisabledAddons(Set<String> disabled) async {
    writes.add(Set.of(disabled));
    this.disabled = Set.of(disabled);
    await write?.call(Set.of(disabled));
  }

  @override
  Future<CatalogSearchRow?> searchCatalog(
    StremioAddon addon,
    StremioAddonCatalog catalog,
    String query,
  ) async {
    requests.add((addon: addon.id, catalog: catalog.id, query: query));
    return fetch?.call(addon, catalog, query);
  }
}
