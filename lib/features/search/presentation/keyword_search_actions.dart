import 'keyword_selection.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/torrent.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/dialog_tap_guard.dart';
import 'search_result_bindings.dart';

typedef KeywordSearchActionsDeps = ({
  BuildContext Function() context,
  bool Function() mounted,
  SearchResultBindings Function() bindings,
  Future<bool> Function(
    BuildContext, {
    required List<Torrent> torrents,
    required String keyword,
  })
  bulkAdd,
  Future<void> Function(
    BuildContext,
    Torrent, {
    List<Torrent>? sources,
    int sourceIndex,
    String searchKeyword,
  })
  activate,
  bool Function(Torrent) canDownload,
  Future<void> Function(BuildContext, Torrent) download,
  Future<void> Function(String) copyText,
  void Function(String) snack,
  VoidCallback freeze,
  KeywordSelection selection,
});

/// Explicit bulk, stream-menu, clipboard and playback actions for Keyword rows.
class KeywordSearchActions {
  KeywordSearchActions(this._deps);
  final KeywordSearchActionsDeps _deps;
  bool _kwBulkBusy = false;

  Future<void> openBulkAdd() async {
    final context = _deps.context();
    if (_kwBulkBusy) return;
    final chosen = _deps
        .bindings()
        .results
        .results
        .where((t) => _deps.bindings().results.selected.contains(t.infohash))
        .toList();
    if (chosen.isEmpty) return;
    _kwBulkBusy = true;
    bool chose = false;
    try {
      chose = await _deps.bulkAdd(
        context,
        torrents: chosen,
        keyword: _deps.bindings().search.query,
      );
    } finally {
      _kwBulkBusy = false;
    }
    // Stay in selection mode if the user just dismissed the chooser.
    if (context.mounted && chose && _deps.bindings().results.selectionMode) {
      _deps.selection.exitKwSelection();
    }
  }

  /// Action menu for a keyword-result direct/external stream row (parity with
  /// the old direct-stream action dialog): Play/Open, Copy URL, Download.
  void showKwStreamMenu(Torrent t, int i) {
    final context = _deps.context();
    final app = AppThemeScope.of(context);
    final external = t.isExternalStream;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.home.sheetBg,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                external ? Icons.open_in_new_rounded : Icons.play_arrow_rounded,
                color: app.core.tx,
              ),
              title: Text(external ? 'Open externally' : 'Play now'),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                unawaited(
                  _deps.activate(
                    context,
                    t,
                    sources: _deps.bindings().results.results,
                    sourceIndex: i,
                    searchKeyword: _deps.bindings().search.query,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Color(0xFFF59E0B)),
              title: const Text('Copy link'),
              onTap: () async {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                await copyKwLink(t);
              },
            ),
            if (_deps.canDownload(t))
              ListTile(
                leading: const Icon(
                  Icons.download_rounded,
                  color: Color(0xFF60A5FA),
                ),
                title: const Text('Download to device'),
                onTap: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(sheetCtx).pop();
                  unawaited(_deps.download(context, t));
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> copyKwLink(Torrent t) async {
    final link = t.copyLink;
    if (link == null) {
      _deps.snack('No link available for this source.');
      return;
    }
    await _deps.copyText(link);
    if (_deps.mounted()) _deps.snack('Link copied to clipboard');
  }

  void activateKeywordResult(BuildContext context, Torrent torrent, int index) {
    if (_deps.bindings().results.selectionMode &&
        !torrent.isDirectStream &&
        !torrent.isExternalStream) {
      _deps.selection.toggleKwSelection(torrent);
      return;
    }
    // Ignore Select leaking from a closing toolbar dialog; freeze before playback.
    if (DialogTapGuard.shouldIgnoreTap()) return;
    _deps.freeze();
    unawaited(
      _deps.activate(
        context,
        torrent,
        sources: _deps.bindings().results.results,
        sourceIndex: index,
        searchKeyword: _deps.bindings().search.query,
      ),
    );
  }

  void longPressKeywordResult(Torrent torrent, int index) {
    if (!torrent.isDirectStream && !torrent.isExternalStream) {
      _deps.selection.enterKwSelection();
      _deps.selection.toggleKwSelection(torrent);
    } else {
      _deps.freeze();
      showKwStreamMenu(torrent, index);
    }
  }
}
