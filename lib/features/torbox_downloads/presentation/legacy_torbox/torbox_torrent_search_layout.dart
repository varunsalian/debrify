import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'torbox_focus_state.dart';
import 'torbox_torrent_search_state.dart';

typedef TorboxTorrentSearchLayoutDeps = ({
  BuildContext Function() context,
  TorboxTorrentSearchState torrentSearchState,
  TorboxFocusState focusState,
  void Function() submitTorrentSearch,
  void Function(VoidCallback) setState,
  List<TorboxTorrent> Function() filteredTorrentSearchResults,
  Widget Function(TorboxTorrent torrent, int index) buildTorrentFolderCard,
});

class TorboxTorrentSearchLayout {
  TorboxTorrentSearchLayout(this._deps);
  final TorboxTorrentSearchLayoutDeps _deps;

  Widget buildTorrentSearchBar() {
    final app = AppThemeScope.of(_deps.context());
    final hasText =
        _deps.torrentSearchState.torrentSearchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _deps.torrentSearchState.torrentSearchController,
              focusNode: _deps.focusState.torrentSearchFocusNode,
              autofocus: true,
              onChanged: (_) =>
                  _deps.focusState.torrentSearchSubmitFocus.cancel(),
              onSubmitted: (_) => _deps.submitTorrentSearch(),
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search your torrents...',
                hintStyle: TextStyle(color: app.fade(app.core.tx, 0.3)),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: app.fade(app.core.tx, 0.4),
                  size: 20,
                ),
                filled: true,
                fillColor: app.fade(app.core.tx, 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
              ),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _deps.focusState.torrentSearchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
                    _deps.focusState.torrentSearchSubmitFocus.cancel();
                    _deps.torrentSearchState.torrentSearchController.clear();
                    _deps.setState(
                      () => _deps.torrentSearchState.torrentSearchQuery = '',
                    );
                    _deps.focusState.torrentSearchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _deps.focusState.torrentSearchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return IconButton(
                      onPressed: () {
                        _deps.focusState.torrentSearchSubmitFocus.cancel();
                        _deps.torrentSearchState.torrentSearchController
                            .clear();
                        _deps.setState(
                          () =>
                              _deps.torrentSearchState.torrentSearchQuery = '',
                        );
                        _deps.focusState.torrentSearchFocusNode.requestFocus();
                      },
                      icon: Icon(
                        Icons.clear_rounded,
                        color: isFocused
                            ? app.core.tx
                            : app.fade(app.core.tx, 0.4),
                        size: 18,
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

  Widget buildTorrentSearchResults() {
    final app = AppThemeScope.of(_deps.context());
    if (_deps.torrentSearchState.isLoadingTorrentSearch) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading all torrents...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_deps.torrentSearchState.torrentSearchQuery.isEmpty) {
      return Center(
        child: Text(
          'Type a keyword and press search',
          style: TextStyle(color: app.fade(app.core.tx, 0.4)),
        ),
      );
    }

    final results = _deps.filteredTorrentSearchResults();

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: app.fade(app.core.tx, 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'No results for "${_deps.torrentSearchState.torrentSearchQuery}"',
              style: TextStyle(color: app.fade(app.core.tx, 0.5)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final torrent = results[index];
        return _deps.buildTorrentFolderCard(torrent, index);
      },
    );
  }
}
