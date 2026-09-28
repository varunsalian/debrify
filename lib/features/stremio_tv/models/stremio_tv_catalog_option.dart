/// Immutable display values; catalog JSON stays at the data boundary.
class StremioTvCatalogOption {
  const StremioTvCatalogOption({
    required this.id,
    required this.name,
    required this.searchName,
    required this.itemCount,
  });
  final String id, name, searchName;
  final int itemCount;
}
