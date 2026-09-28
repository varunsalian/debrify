class StremioTvCatalogPickerResult {
  final String message;
  final bool createdNew;
  final bool duplicate;

  const StremioTvCatalogPickerResult({
    required this.message,
    this.createdNew = false,
    this.duplicate = false,
  });
}
