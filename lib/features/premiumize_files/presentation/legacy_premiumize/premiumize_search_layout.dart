import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'premiumize_focus_state.dart';
import 'premiumize_search_state.dart';

typedef PremiumizeSearchLayoutDeps = ({
  BuildContext Function() context,
  PremiumizeSearchState searchState,
  PremiumizeFocusState focusState,
  bool Function() isAtRoot,
  void Function(String query) performSearch,
  void Function(VoidCallback) setState,
  Widget Function(PremiumizeFolderItem item, int index, {bool autofocusFirst})
  buildFileCard,
});

class PremiumizeSearchLayout {
  PremiumizeSearchLayout(this._deps);
  final PremiumizeSearchLayoutDeps _deps;

  Widget buildSearchBar() {
    final app = AppThemeScope.of(_deps.context());
    final hasText = _deps.searchState.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _deps.searchState.searchController,
              focusNode: _deps.focusState.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent
              // wrapper): up to the app-bar actions, down into the results,
              // right to the clear button when visible.
              onUpArrow: () => _deps.focusState.searchFocusNode
                  .focusInDirection(TraversalDirection.up),
              onDownArrow: () => _deps.focusState.searchFocusNode
                  .focusInDirection(TraversalDirection.down),
              onRightArrow: hasText
                  ? () => _deps.focusState.searchClearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: _deps.isAtRoot()
                    ? 'Search your Premiumize cloud...'
                    : 'Search files...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: app.fade(app.core.tx, 0.06),
                border: OutlineInputBorder(
                  borderRadius: app.shape.br(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _deps.performSearch,
              onSubmitted: (_) => _deps.focusState.searchFocusNode.unfocus(),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _deps.focusState.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key)) {
                    _deps.setState(() {
                      _deps.searchState.searchController.clear();
                      _deps.searchState.searchResults = [];
                    });
                    _deps.focusState.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _deps.focusState.searchFocusNode.requestFocus();
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
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _deps.setState(() {
                            _deps.searchState.searchController.clear();
                            _deps.searchState.searchResults = [];
                          });
                          _deps.focusState.searchFocusNode.requestFocus();
                        },
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

  Widget buildSearchResults() {
    if (_deps.searchState.searchController.text.trim().isEmpty) {
      return Center(
        child: Text(
          _deps.isAtRoot()
              ? 'Type to search your cloud'
              : 'Type to search files',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_deps.searchState.isSearching &&
        _deps.searchState.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_deps.searchState.searchResults.isEmpty) {
      return const Center(
        child: Text('No results found', style: TextStyle(color: Colors.grey)),
      );
    }
    // Reuse the full file card so search results get the same Open / Play /
    // ⋮ (Download · Add to Playlist · Delete) actions as the main list.
    // autofocusFirst is disabled so results don't steal focus from the search
    // box while the user is typing.
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _deps.searchState.searchResults.length,
      itemBuilder: (context, index) {
        final item = _deps.searchState.searchResults[index];
        return KeyedSubtree(
          key: ValueKey('search-${item.id}'),
          child: _deps.buildFileCard(item, index, autofocusFirst: false),
        );
      },
    );
  }
}
