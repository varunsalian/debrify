/// Requests a layout transition without owning the view's active layout or
/// player teardown. The view applies its existing ordered transition atomically.
class HomeLayoutPreference {
  HomeLayoutPreference({
    required this.initialStyle,
    required this.readSaved,
    required this.isOwnerCurrent,
  });

  final String initialStyle;
  final Future<String> Function() readSaved;
  final bool Function() isOwnerCurrent;
  int _generation = 0;
  bool _disposed = false;

  Future<void> load({
    required bool Function() isCurrent,
    required String Function() currentStyle,
    required void Function(String) transition,
  }) async {
    if (_disposed || !isOwnerCurrent() || !isCurrent()) return;
    final generation = ++_generation;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        isOwnerCurrent() &&
        isCurrent();
    final saved = await readSaved();
    if (!current() || saved == currentStyle()) return;
    transition(saved);
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}
