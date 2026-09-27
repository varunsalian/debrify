import '../../search/models/search_mode.dart';

/// Selects a default once per accepted read; active user-selected mode belongs
/// to the view. This operation retains no competing copy of that mode.
class HomeDefaultView {
  HomeDefaultView({
    required this.readSaved,
    required this.keywordAllowed,
    required this.isOwnerCurrent,
  });

  final Future<String?> Function() readSaved;
  final bool Function() keywordAllowed;
  final bool Function() isOwnerCurrent;
  int _generation = 0;
  bool _disposed = false;

  Future<void> load({
    required bool isTelevision,
    required bool isHome,
    required bool Function() isCurrent,
    required void Function(SearchMode) select,
  }) async {
    if (_disposed || !isOwnerCurrent() || !isCurrent()) return;
    final generation = ++_generation;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        isOwnerCurrent() &&
        isCurrent();
    // Keep TV selection synchronous and independent of saved preferences.
    if (isTelevision) {
      select(SearchMode.catalog);
      return;
    }
    final saved = await readSaved();
    if (!current() || !isHome) return;
    select(
      saved == 'keyword' && keywordAllowed()
          ? SearchMode.keyword
          : SearchMode.catalog,
    );
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}
