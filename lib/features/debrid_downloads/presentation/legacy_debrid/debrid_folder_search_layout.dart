import 'package:debrify/features/debrid_downloads/models/rd_search_result.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debrid_focus_state.dart';
import 'debrid_folder_search_state.dart';

typedef DebridFolderSearchLayoutDeps = ({
  BuildContext Function() context,
  DebridFolderSearchState folderSearchState,
  DebridFocusState focusState,
  void Function(String query) performSearch,
  void Function(VoidCallback) setState,
  Future<void> Function(RDFileNode file) playFile,
});

class DebridFolderSearchLayout {
  DebridFolderSearchLayout(this._deps);
  final DebridFolderSearchLayoutDeps _deps;

  /// Build the search bar widget
  Widget buildSearchBar() {
    final app = AppThemeScope.of(_deps.context());
    final hasText = _deps.folderSearchState.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _deps.folderSearchState.searchController,
              focusNode: _deps.focusState.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent wrapper)
              onUpArrow: () => _deps.focusState.searchFocusNode.unfocus(),
              onDownArrow: () => _deps.focusState.searchFocusNode.unfocus(),
              onRightArrow: hasText
                  ? () => _deps.focusState.searchClearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: 'Search all files...',
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
          // Clear button - separate focusable widget for D-pad navigation
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _deps.focusState.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;

                  // Select/Enter: clear search
                  if (isActivateKey(key)) {
                    _deps.setState(() {
                      _deps.folderSearchState.searchController.clear();
                      _deps.folderSearchState.searchResults.clear();
                    });
                    _deps.focusState.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  // Arrow Left: go back to TextField
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
                        color: const Color(0xFF1E293B),
                        borderRadius: app.shape.br(8),
                        border: isFocused
                            // Pinned with the slate fill above, which does
                            // not follow the palette: a paper theme's
                            // near-black ring on dark slate is a ring you
                            // cannot see.
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _deps.setState(() {
                            _deps.folderSearchState.searchController.clear();
                            _deps.folderSearchState.searchResults.clear();
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

  /// Build search results list
  Widget buildSearchResults() {
    if (_deps.folderSearchState.searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Type to search all files',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_deps.folderSearchState.searchResults.isEmpty) {
      return const Center(
        child: Text('No files found', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _deps.folderSearchState.searchResults.length,
      itemBuilder: (context, index) {
        final result = _deps.folderSearchState.searchResults[index];
        return buildSearchResultCard(result, index);
      },
    );
  }

  /// Build a card for a search result
  Widget buildSearchResultCard(RDSearchResult result, int index) {
    final node = result.node;
    final borderColor = Colors.white.withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _deps.playFile(node),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  color: Colors.blue,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (result.path.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.path,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (node.bytes != null)
                        Text(
                          Formatters.formatFileSize(node.bytes!),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
