import 'dart:async';
import 'package:debrify/features/playlist_content/models/playlist_content_search_result.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_focus_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_state.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaylistContentSearchLayoutDeps = ({
  BuildContext Function() context,
  PlaylistContentSearchState searchState,
  PlaylistContentFocusState focusState,
  void Function(String query) performSearch,
  void Function(VoidCallback) setState,
  Map<String, dynamic>? Function(RDFileNode file) getProgressForFile,
  Future<void> Function(RDFileNode file) playFile,
});

class PlaylistContentSearchLayout {
  PlaylistContentSearchLayout(this._deps);
  final PlaylistContentSearchLayoutDeps _deps;

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
              focusNode: _deps.focusState.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent wrapper)
              onUpArrow: () => _deps.focusState.searchFocusNode.unfocus(),
              onDownArrow: () => _deps.focusState.searchFocusNode.unfocus(),
              onRightArrow: hasText
                  ? () => _deps.focusState.searchClearFocusNode.requestFocus()
                  : null,
              // The shared TV shell/keyboard chrome follows settings.accent,
              // as Downloads established. The panel's ground and ink are the
              // keyboard's own roles rather than this surface's, so they come
              // from `youtube.keyboardPanel` / `core.tx`; the keycap label is
              // scored against the accent actually being painted.
              accent: app.settings.accent,
              keyboardGround: app.youtube.keyboardPanel,
              keyboardInk: app.core.tx,
              keyboardInkOnAccent: app.inkOn(app.settings.accent),
              decoration: InputDecoration(
                hintText: 'Search all files...',
                // Colors.grey left literal: no token carries it.
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: app.playlist.fieldFill,
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
              onSubmitted: (_) {
                // Unfocus TextField when user presses search/enter on TV keyboard
                _deps.focusState.searchFocusNode.unfocus();
              },
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
                      _deps.searchState.searchController.clear();
                      _deps.searchState.searchResults.clear();
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
                        color: app.playlist.fieldFill,
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

  /// Build the search results list
  Widget buildSearchResults() {
    if (_deps.searchState.searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Type to search all files',
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
  Widget buildSearchResultCard(PlaylistContentSearchResult result) {
    final app = AppThemeScope.of(_deps.context());
    final node = result.node;

    // Get progress for this file
    double progress = 0.0;
    bool isFinished = false;
    final progressData = _deps.getProgressForFile(node);
    if (progressData != null) {
      final positionMs = progressData['positionMs'] as int? ?? 0;
      final durationMs = progressData['durationMs'] as int? ?? 0;
      if (durationMs > 0) {
        progress = positionMs / durationMs;
        isFinished = progress >= 0.9 || (durationMs - positionMs) < 120000;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: app.playlist.card,
      child: InkWell(
        onTap: () => _deps.playFile(node),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Icon
                  const Icon(
                    Icons.play_circle_outline,
                    color: Colors.blue,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  // File info
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
                        const SizedBox(height: 4),
                        // Show path if not empty
                        if (result.path.isNotEmpty)
                          Text(
                            result.path,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                  // Progress badge
                  if (progress > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        // Colors.green (#4CAF50) left literal: it is NOT
                        // playlist.statusWatched (#059669), so no token holds
                        // it. The in-progress half is progressPlayed.
                        color: isFinished
                            ? Colors.green
                            : app.playlist.progressPlayed,
                        borderRadius: app.shape.br(4),
                      ),
                      child: Text(
                        isFinished ? 'DONE' : '${(progress * 100).toInt()}%',
                        style: TextStyle(
                          color: app.core.tx,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Progress bar at bottom
            if (progress > 0 && !isFinished)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    app.playlist.progressPlayed,
                  ),
                  minHeight: 3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
