import 'dart:async';
import 'package:debrify/features/alldebrid_files/models/alldebrid_view.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:flutter/material.dart';

typedef AllDebridRootLayoutDeps = ({
  AllDebridFocusState focusState,
  AllDebridNavigationState navigationState,
  AllDebridSearchState searchState,
  AllDebridSelectionState selectionState,
  AllDebridLibraryState libraryState,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  Widget Function() buildBody,
  Widget Function() buildFileSearchBar,
  Widget Function() buildFilesView,
  Widget Function() buildLinksView,
  Widget Function() buildMagnetsView,
  Widget Function() buildSearchBar,
  Widget Function() buildSelectionBar,
  Widget Function() buildToolbar,
  Widget Function() buildViewSelectorBar,
  bool Function() isAtRoot,
  Future<void> Function() load,
  void Function() navigateUp,
});

class AllDebridRootLayout {
  final AllDebridRootLayoutDeps _deps;
  AllDebridRootLayout(this._deps);
  AllDebridFocusState get _f => _deps.focusState;
  AllDebridNavigationState get _navigation => _deps.navigationState;
  AllDebridSearchState get _search => _deps.searchState;
  AllDebridSelectionState get _selection => _deps.selectionState;
  AllDebridLibraryState get _library => _deps.libraryState;

  // ── Build ─────────────────────────────────────────────────────────────

  Widget build(BuildContext context) {
    return CloudScaffold(
      appBar: _deps.isAtRoot()
          ? null
          : AppBar(
              leading: IconButton(
                focusNode: _f.backButtonFocusNode,
                icon: const Icon(Icons.arrow_back),
                onPressed: _deps.navigateUp,
                tooltip: 'Back',
              ),
              title: Text(_navigation.currentMagnet!.name),
              actions: [
                if (_navigation.currentFiles.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _search.fileSearchActive ? Icons.close : Icons.search,
                    ),
                    onPressed: () {
                      _deps.setState(() {
                        _search.fileSearchActive = !_search.fileSearchActive;
                        if (!_search.fileSearchActive) {
                          _search.fileSearchQuery = '';
                          _search.fileSearchController.clear();
                        } else {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_deps.mounted()) {
                              _f.fileSearchFocusNode.requestFocus();
                            }
                          });
                        }
                      });
                    },
                    tooltip: 'Search files',
                  ),
              ],
            ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          if (_deps.isAtRoot()) _deps.buildToolbar(),
          if (_deps.isAtRoot()) _deps.buildViewSelectorBar(),
          if (_deps.isAtRoot() && _search.searchActive) _deps.buildSearchBar(),
          if (_deps.isAtRoot() && _selection.selectionMode)
            _deps.buildSelectionBar(),
          if (!_deps.isAtRoot() && _search.fileSearchActive)
            _deps.buildFileSearchBar(),
          Expanded(child: _deps.buildBody()),
        ],
      ),
    );
  }

  Widget buildBody() {
    final app = AppThemeScope.of(_deps.context());
    if (_navigation.selectedView == AllDebridView.webDownloads) {
      return _deps.buildLinksView();
    }
    if (_library.loading) {
      return const CloudRowSkeletonList();
    }
    if (_library.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 48,
                color: app.fade(app.core.tx, 0x62 / 0xFF),
              ),
              const SizedBox(height: 16),
              Text(_library.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _deps.load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (!_deps.isAtRoot()) {
      return _deps.buildFilesView();
    }
    return _deps.buildMagnetsView();
  }
}
