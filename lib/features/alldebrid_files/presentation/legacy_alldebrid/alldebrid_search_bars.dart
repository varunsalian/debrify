import 'package:debrify/features/alldebrid_files/models/alldebrid_view.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AllDebridSearchBarsDeps = ({
  AllDebridSearchState searchState,
  AllDebridFocusState focusState,
  AllDebridNavigationState navigationState,
  BuildContext Function() context,
  void Function(VoidCallback) setState,
  void Function(FocusNode? target, FocusNode field) moveFocusTo,
  InputDecoration Function(String hint) searchDecoration,
});

class AllDebridSearchBars {
  final AllDebridSearchBarsDeps _deps;
  AllDebridSearchBars(this._deps);
  AllDebridSearchState get _search => _deps.searchState;
  AllDebridFocusState get _f => _deps.focusState;
  AllDebridNavigationState get _navigation => _deps.navigationState;

  /// Shared search-field decoration matching the cloud-screen styling.
  InputDecoration searchDecoration(String hint) {
    final app = AppThemeScope.of(_deps.context());
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: app.fade(app.core.tx, 0.3)),
      prefixIcon: Icon(
        Icons.search_rounded,
        color: app.fade(app.core.tx, 0.4),
        size: 20,
      ),
      filled: true,
      fillColor: app.fade(app.core.tx, 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: app.cloud.accent),
      ),
    );
  }

  Widget buildSearchBar() {
    final app = AppThemeScope.of(_deps.context());
    final hasText = _search.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _search.searchController,
              focusNode: _f.searchFocusNode,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              // D-pad exits (formerly a Focus/onKeyEvent wrapper): up to the
              // toolbar, down into the results, right to the clear button.
              onUpArrow: () => _deps.moveFocusTo(
                _f.toolbarSearchFocusNode,
                _f.searchFocusNode,
              ),
              onDownArrow: () =>
                  _deps.moveFocusTo(_f.firstItemFocusNode, _f.searchFocusNode),
              onRightArrow: hasText
                  ? () => _f.searchClearFocusNode.requestFocus()
                  : null,
              onChanged: (v) => _deps.setState(() => _search.searchQuery = v),
              onSubmitted: (_) => _f.searchFocusNode.unfocus(),
              decoration: _deps.searchDecoration(
                _navigation.selectedView == AllDebridView.webDownloads
                    ? 'Search your links...'
                    : 'Search your magnets...',
              ),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _f.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key)) {
                    _search.searchController.clear();
                    _deps.setState(() => _search.searchQuery = '');
                    _f.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _f.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return Container(
                      decoration: BoxDecoration(
                        color: app.fade(app.core.tx, 0.06),
                        borderRadius: app.shape.br(8),
                        border: isFocused
                            ? Border.all(color: app.core.tx, width: 2)
                            : null,
                      ),
                      child: IconButton(
                        onPressed: () {
                          _search.searchController.clear();
                          _deps.setState(() => _search.searchQuery = '');
                          _f.searchFocusNode.requestFocus();
                        },
                        icon: Icon(
                          Icons.clear_rounded,
                          color: app.fade(app.core.tx, 0.4),
                          size: 18,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildFileSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TvTextField(
        controller: _search.fileSearchController,
        focusNode: _f.fileSearchFocusNode,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        // D-pad exits (formerly a Focus/onKeyEvent wrapper): up to the back
        // button, down into the results.
        onUpArrow: () =>
            _deps.moveFocusTo(_f.backButtonFocusNode, _f.fileSearchFocusNode),
        onDownArrow: () =>
            _deps.moveFocusTo(_f.firstItemFocusNode, _f.fileSearchFocusNode),
        onChanged: (v) => _deps.setState(() => _search.fileSearchQuery = v),
        onSubmitted: (_) => _f.fileSearchFocusNode.unfocus(),
        decoration: _deps.searchDecoration('Search files...'),
      ),
    );
  }
}
