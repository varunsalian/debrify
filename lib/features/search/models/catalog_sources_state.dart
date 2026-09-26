import '../../../models/stremio_addon.dart';

class CatalogSourcesState {
  final List<StremioAddon> addons;
  final Set<String> disabled;
  final bool loading;
  final Object? failure;

  const CatalogSourcesState.loading()
    : addons = const [],
      disabled = const {},
      loading = true,
      failure = null;

  CatalogSourcesState({
    required List<StremioAddon> addons,
    required Set<String> disabled,
    this.loading = false,
    this.failure,
  }) : addons = List.unmodifiable(addons),
       disabled = Set.unmodifiable(disabled);
}
