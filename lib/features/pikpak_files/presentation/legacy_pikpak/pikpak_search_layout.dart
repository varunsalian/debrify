import 'package:debrify/features/pikpak_files/models/pikpak_search_result.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pikpak_search_state.dart';

typedef PikpakSearchLayoutDeps = ({
  BuildContext Function() context,
  PikpakSearchState searchState,
  Future<void> Function(String query) performSearch,
  void Function(VoidCallback) setState,
  bool Function() selectSourceMode,
  Future<void> Function(Map<String, dynamic> file) selectBoundSource,
  Future<void> Function(Map<String, dynamic> fileData) playFile,
});

class PikpakSearchLayout {
  PikpakSearchLayout(this._deps);
  final PikpakSearchLayoutDeps _deps;

  /// Build the search bar widget
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
              focusNode: _deps.searchState.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent wrapper)
              onUpArrow: () => _deps.searchState.searchFocusNode.unfocus(),
              onDownArrow: () => _deps.searchState.searchFocusNode.unfocus(),
              onRightArrow: hasText
                  ? () => _deps.searchState.searchClearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: 'Search files...',
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
              onSubmitted: (_) => _deps.searchState.searchFocusNode.unfocus(),
            ),
          ),
          // Clear button - separate focusable widget for D-pad navigation
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _deps.searchState.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;

                  // Select/Enter: clear search
                  if (isActivateKey(key)) {
                    _deps.setState(() {
                      _deps.searchState.searchController.clear();
                      _deps.searchState.searchResults.clear();
                    });
                    _deps.searchState.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  // Arrow Left: go back to TextField
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _deps.searchState.searchFocusNode.requestFocus();
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
                            _deps.searchState.searchResults.clear();
                          });
                          _deps.searchState.searchFocusNode.requestFocus();
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
    if (_deps.searchState.searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Type to search files',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_deps.searchState.searchResults.isEmpty) {
      return const Center(
        child: Text('No files found', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _deps.searchState.searchResults.length,
      itemBuilder: (context, index) {
        final result = _deps.searchState.searchResults[index];
        return buildSearchResultCard(result);
      },
    );
  }

  /// Build a card for a search result
  Widget buildSearchResultCard(PikPakSearchResult result) {
    final file = result.file;
    final name = file['name'] as String? ?? 'Unknown';
    final size = file['size'] as String? ?? '0';

    if (_deps.selectSourceMode()) {
      return CloudFileRow(
        kind: CloudRowKind.video,
        title: name,
        meta: result.path.isEmpty
            ? Formatters.formatFileSize(int.tryParse(size) ?? 0)
            : result.path,
        onTap: () => _deps.selectBoundSource(file),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _deps.playFile(file),
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
                        name,
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
                      Text(
                        Formatters.formatFileSize(int.tryParse(size) ?? 0),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
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
