import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/mdblist_list_choice.dart';
import '../models/search_session.dart';
import '../models/lists_search_state.dart';
import '../application/lists_search_controller.dart';
import 'search_result_bindings.dart';
import 'lists_focus.dart';
import 'lists_navigation.dart';

typedef ListsSearchSectionDeps = ({
  SearchSession Function() session,
  SearchResultBindings Function() bindings,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  bool Function() isTelevision,
  bool mdblistEnabled,
  VoidCallback cancelSubmitFocus,
  void Function(FocusNode) completeSubmitFocus,
  ValueChanged<MdblistListChoice> trackOpen,
  ValueChanged<MdblistListChoice> handoff,
  BuildContext Function() context,
  ListsNavigation Function() createNavigation,
});

/// List-search request, focus and navigation glue; provider state stays authoritative.
class ListsSearchSection {
  ListsSearchSection(this._ref, this._deps);
  final WidgetRef _ref;
  final ListsSearchSectionDeps _deps;
  ListsSearchState get listsState => _deps.bindings().lists;
  ListsSearchController get listsController =>
      _ref.read(listsSearchProvider(_deps.session()).notifier);
  String get listsQuery => listsState.query;
  List<MdblistListChoice> get listsResults => listsState.results;
  final listsFocus = ListsFocus();
  List<FocusNode> get listsNodes => listsFocus.nodes;
  // Debounce for opening a list from the rail — one fast double-press must not
  // stack two pushed item screens (TV) / double-fire the handoff.
  DateTime? lastListOpenAt;

  void disposeListsNodes() => listsFocus.clear();

  void clearListsSearch() {
    if (!_deps.mounted()) return;
    disposeListsNodes();
    listsController.clear();
  }

  /// One focus node per result row, rebuilt to match the current result set.
  void ensureListsNodes() => listsFocus.resize(listsResults.length);

  /// Keep route/focus effects in presentation; the notifier owns requests,
  /// results, errors and stale-completion checks.
  Future<void> runListsSearch(String query) async {
    if (!_deps.mdblistEnabled) {
      _deps.cancelSubmitFocus();
      return;
    }
    if (query.trim().isEmpty) {
      clearListsSearch();
      return;
    }
    disposeListsNodes();
    final accepted = await listsController.search(query);
    if (!_deps.mounted() || !accepted) return;
    _deps.setState(ensureListsNodes);
    if (listsNodes.isEmpty) {
      _deps.cancelSubmitFocus();
    } else {
      _deps.completeSubmitFocus(listsNodes.first);
    }
  }

  /// Hand the picked list to the Discover tab, which opens it focused (with
  /// the ♥ like toggle). Mirrors the pendingCatalogDetailOpen handoff.
  void openListsResult(MdblistListChoice choice) {
    // Debounce: a fast double OK/tap must not stack two pushed screens (TV) or
    // double-fire the tab handoff. A route push + Back takes far longer than
    // this, so re-opening the same card after returning still works.
    final now = DateTime.now();
    if (lastListOpenAt != null &&
        now.difference(lastListOpenAt!) < const Duration(milliseconds: 600)) {
      return;
    }
    lastListOpenAt = now;
    _deps.trackOpen(choice);
    // TV: switching to the Discover tab rebuilds this Search screen fresh on
    // return (main.dart keys tab content by index), losing the results, scroll,
    // and focused card. Instead PUSH the list's items over the Search board —
    // the screen stays mounted underneath, so Back returns to exactly this
    // state, and we re-focus the tapped rail card so the DPAD cursor lands back
    // on it (its focus handler scrolls it into view). Mobile/laptop keep the
    // Discover-tab landing (with its Source switcher).
    if (_deps.isTelevision()) {
      final context = _deps.context();
      openMdblistListItems(
        context,
        choice,
        onReturn: () => listsFocus.restore(
          isCurrent: _deps.mounted,
          indexOfResult: () =>
              listsResults.indexWhere((l) => l.id == choice.id),
        ),
      );
      return;
    }
    _deps.handoff(choice);
  }

  late final listsNavigation = _deps.createNavigation();

  void openListsSeeAll() =>
      listsNavigation.openGrid(_deps.context(), listsQuery, listsResults);

  void openMdblistListItems(
    BuildContext pushCtx,
    MdblistListChoice list, {
    VoidCallback? onReturn,
  }) => listsNavigation.openItems(pushCtx, list, onReturn: onReturn);
}
