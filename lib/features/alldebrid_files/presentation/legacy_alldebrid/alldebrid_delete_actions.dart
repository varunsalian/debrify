import 'dart:async';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:flutter/material.dart';

typedef AllDebridDeleteActionsDeps = ({
  AllDebridLibraryState libraryState,
  AllDebridSelectionState selectionState,
  BuildContext Function() context,
  bool Function() mounted,
  Future<void> Function(List<AllDebridLink> links, {String? title}) deleteLinks,
  Future<void> Function(List<AllDebridMagnet> magnets, {String? title})
  deleteMagnets,
  void Function() dismissLoading,
  void Function() exitSelectionMode,
  Future<void> Function() load,
  Future<void> Function() loadLinks,
  void Function(String message) showLoading,
  void Function(String message, {bool isError}) snack,
});

class AllDebridDeleteActions {
  final AllDebridDeleteActionsDeps _deps;
  AllDebridDeleteActions(this._deps);
  AllDebridLibraryState get _library => _deps.libraryState;
  AllDebridSelectionState get _selection => _deps.selectionState;

  Future<void> deleteLinks(List<AllDebridLink> links, {String? title}) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty || links.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (ctx) => AlertDialog(
        title: Text(
          title ??
              (links.length == 1
                  ? 'Delete link?'
                  : 'Delete ${links.length} links?'),
        ),
        content: Text(
          links.length == 1
              ? 'Remove "${links.first.fileName}" from your AllDebrid saved links?'
              : 'Remove these ${links.length} links from your AllDebrid saved links?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _deps.showLoading('Deleting…');
    int fail = 0;
    for (final l in links) {
      try {
        await AllDebridService.deleteSavedLink(apiKey, l.link);
      } catch (_) {
        fail++;
      }
    }
    _deps.dismissLoading();
    await _deps.loadLinks();
    if (!_deps.mounted()) return;
    if (fail == 0) {
      _deps.snack(
        links.length == 1 ? 'Link deleted' : '${links.length} links deleted',
        isError: false,
      );
    } else {
      _deps.snack(
        'Failed to delete $fail link${fail == 1 ? '' : 's'}',
        isError: true,
      );
    }
  }

  void confirmDeleteAllLinks() {
    if (_library.links.isEmpty) return;
    _deps.deleteLinks(List.of(_library.links), title: 'Delete all links?');
  }

  // ── Delete ─────────────────────────────────────────────────────────────

  Future<void> deleteMagnets(
    List<AllDebridMagnet> magnets, {
    String? title,
  }) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty || magnets.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (ctx) => AlertDialog(
        title: Text(
          title ??
              (magnets.length == 1
                  ? 'Delete magnet?'
                  : 'Delete ${magnets.length} magnets?'),
        ),
        content: Text(
          magnets.length == 1
              ? 'Remove "${magnets.first.name}" from your AllDebrid account?'
              : 'Remove these ${magnets.length} magnets from your AllDebrid account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _deps.showLoading('Deleting…');
    for (final m in magnets) {
      await AllDebridService.deleteMagnet(apiKey, m.id);
    }
    _deps.dismissLoading();
    _deps.exitSelectionMode();
    await _deps.load();
    if (_deps.mounted()) {
      _deps.snack(
        magnets.length == 1
            ? 'Magnet deleted'
            : '${magnets.length} magnets deleted',
        isError: false,
      );
    }
  }

  void confirmDeleteAll() {
    if (_library.magnets.isEmpty) return;
    _deps.deleteMagnets(
      List.of(_library.magnets),
      title: 'Delete all magnets?',
    );
  }

  Future<void> handleDeleteSelected() async {
    final targets = _library.magnets
        .where((m) => _selection.selectedIds.contains(m.id))
        .toList();
    if (targets.isEmpty) return;
    await _deps.deleteMagnets(targets);
  }
}
