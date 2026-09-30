import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/metadata_title_navigation.dart';
import '../models/search_mode.dart';
import 'title_suggestion_presentation.dart';

typedef SearchTitleOpenDeps = ({
  SearchMode Function() mode,
  bool Function() mounted,
  BuildContext Function() context,
  String? Function() activeTab,
  bool Function() originCurrent,
  VoidCallback cancelSubmitFocus,
  VoidCallback cancelTitleSuggestions,
  void Function(StremioMeta, StremioAddon) openItem,
  Future<StremioMeta> Function(StremioMeta) Function() resolver,
  ValueChanged<String> submit,
});

/// Opening a suggestion preserves edit cancellation, profile and generation checks.
class SearchTitleOpen {
  SearchTitleOpen(this._deps, this._searchController, this._presentation);
  final SearchTitleOpenDeps _deps;
  final TextEditingController _searchController;
  final TitleSuggestionPresentation _presentation;
  Future<void> openSuggestedTitle(StremioMeta item) async {
    if (_presentation.opening ||
        !_deps.mounted() ||
        _deps.mode() != SearchMode.catalog ||
        _deps.activeTab() != 'search' ||
        !_deps.originCurrent()) {
      return;
    }
    _deps.cancelSubmitFocus();
    _searchController.value = TextEditingValue(
      text: item.name,
      selection: TextSelection.collapsed(offset: item.name.length),
    );
    _deps.cancelTitleSuggestions();
    // Filling the field above goes through the same edit/cancel listener as
    // typing. Capture ownership only after that update has finished.
    final generation = _presentation.beginOpen();
    try {
      final context = _deps.context();
      await openMetadataTitle(
        context,
        item,
        (selected) {
          if (!_deps.mounted() ||
              !_presentation.accepts(generation) ||
              _deps.activeTab() != 'search') {
            return;
          }
          _deps.openItem(
            selected,
            selected.sourceAddon ??
                StremioAddon(
                  id: 'metadata_title',
                  name: 'Title metadata',
                  manifestUrl: '',
                  baseUrl: '',
                ),
          );
        },
        resolve: _deps.resolver(),
        onUnresolved: (unresolved) => _deps.submit(unresolved.name),
        isCurrent: () =>
            _deps.mounted() &&
            _presentation.accepts(generation) &&
            _deps.mode() == SearchMode.catalog &&
            _deps.activeTab() == 'search',
      );
    } finally {
      // A cancelled lookup can finish while a newer selection is loading.
      _presentation.finishOpen(generation);
    }
  }
}
