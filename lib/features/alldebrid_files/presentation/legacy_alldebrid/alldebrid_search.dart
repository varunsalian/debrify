import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:flutter/material.dart';

typedef AllDebridSearchDeps = ({
  AllDebridSearchState searchState,
  AllDebridFocusState focusState,
  AllDebridLibraryState libraryState,
  AllDebridNavigationState navigationState,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

class AllDebridSearch {
  final AllDebridSearchDeps _deps;
  AllDebridSearch(this._deps);
  AllDebridSearchState get _search => _deps.searchState;
  AllDebridFocusState get _f => _deps.focusState;
  AllDebridLibraryState get _library => _deps.libraryState;
  AllDebridNavigationState get _navigation => _deps.navigationState;

  // ── Search ─────────────────────────────────────────────────────────────

  void toggleSearch() {
    _deps.setState(() {
      _search.searchActive = !_search.searchActive;
      if (!_search.searchActive) {
        _search.searchQuery = '';
        _search.searchController.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_deps.mounted()) _f.searchFocusNode.requestFocus();
        });
      }
    });
  }

  List<AllDebridMagnet> get visibleMagnets {
    if (_search.searchQuery.trim().isEmpty) return _library.magnets;
    final q = _search.searchQuery.trim().toLowerCase();
    return _library.magnets
        .where((m) => m.name.toLowerCase().contains(q))
        .toList();
  }

  List<AllDebridFile> get visibleFiles {
    if (_search.fileSearchQuery.trim().isEmpty) return _navigation.currentFiles;
    final q = _search.fileSearchQuery.trim().toLowerCase();
    return _navigation.currentFiles
        .where((f) => f.fileName.toLowerCase().contains(q))
        .toList();
  }

  List<AllDebridLink> get visibleLinks {
    if (_search.searchQuery.trim().isEmpty) return _library.links;
    final q = _search.searchQuery.trim().toLowerCase();
    return _library.links
        .where(
          (l) =>
              l.fileName.toLowerCase().contains(q) ||
              l.host.toLowerCase().contains(q),
        )
        .toList();
  }

  /// D-pad escape target for a search field (used by the TvTextField arrow
  /// callbacks below).
  void moveFocusTo(FocusNode? target, FocusNode field) {
    // Move focus to [target] if it's mounted; otherwise just release the field
    // so the remote can traverse onward.
    if (target != null && target.context != null) {
      target.requestFocus();
    } else {
      field.unfocus();
    }
  }
}
