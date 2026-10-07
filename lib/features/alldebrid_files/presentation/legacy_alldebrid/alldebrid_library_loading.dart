import 'dart:async';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AllDebridLibraryLoadingDeps = ({
  AllDebridLibraryState libraryState,
  AllDebridSelectionState selectionState,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  void Function() focusFirstItem,
});

class AllDebridLibraryLoading {
  final AllDebridLibraryLoadingDeps _deps;
  AllDebridLibraryLoading(this._deps);
  AllDebridLibraryState get _library => _deps.libraryState;
  AllDebridSelectionState get _selection => _deps.selectionState;

  Future<void> load() async {
    _deps.setState(() {
      _library.loading = true;
      _library.error = null;
    });
    final apiKey = await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _library.loading = false;
        _library.error = 'Add your AllDebrid API key in Settings first.';
      });
      return;
    }
    _library.apiKey = apiKey;
    try {
      final magnets = await AllDebridService.listMagnets(apiKey);
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _library.magnets = magnets.where((m) => m.isReady).toList();
        _library.loading = false;
        _selection.selectedIds.removeWhere(
          (id) => !_library.magnets.any((m) => m.id == id),
        );
      });
      _deps.focusFirstItem();
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _library.loading = false;
        _library.error = 'Failed to load your AllDebrid library: $e';
      });
    }
  }

  Future<void> loadLinks() async {
    _deps.setState(() {
      _library.loadingLinks = true;
      _library.linksError = null;
    });
    final apiKey =
        _library.apiKey ?? await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _library.loadingLinks = false;
        _library.linksLoadedOnce = true;
        _library.linksError = 'Add your AllDebrid API key in Settings first.';
      });
      return;
    }
    _library.apiKey = apiKey;
    try {
      final links = await AllDebridService.listSavedLinks(apiKey);
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _library.links = links;
        _library.loadingLinks = false;
        _library.linksLoadedOnce = true;
      });
      _deps.focusFirstItem();
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _library.loadingLinks = false;
        _library.linksLoadedOnce = true;
        _library.linksError = 'Failed to load your saved links: $e';
      });
    }
  }
}
