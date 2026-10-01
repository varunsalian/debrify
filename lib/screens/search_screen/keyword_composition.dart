import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/presentation/home_board_rendering.dart';
import '../../features/search/presentation/keyword_search_actions.dart';
import '../../features/search/presentation/keyword_search_dialogs.dart';
import '../../features/search/presentation/keyword_search_frame.dart';
import '../../features/search/presentation/keyword_search_rows.dart';
import '../../features/search/presentation/keyword_search_section.dart';
import '../../features/search/presentation/keyword_selection.dart';
import '../../features/search/presentation/search_input_section.dart';
import '../../features/search/presentation/search_mode_section.dart';
import '../../utils/tv_search_focus_handoff.dart';
import 'search_session_lifecycle.dart';

typedef KeywordCompositionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  SearchSessionLifecycle Function() session,
  SearchModeSection Function() mode,
  SearchInputSection Function() input,
  HomeBoardRendering Function() board,
  bool Function() floatingNavigation,
  VoidCallback sidebar,
  KeywordSearchActions Function(KeywordSearchSection, KeywordSelection)
  createActions,
});

typedef KeywordComposition = ({
  KeywordSearchSection keywordSection,
  KeywordSearchDialogs keywordDialogs,
  KeywordSelection keywordSelection,
  KeywordSearchRows keywordRows,
});

/// Constructs keyword state, dialogs, selection, actions and rows in the original order.
KeywordComposition createKeywordSearch(
  WidgetRef ref,
  KeywordCompositionDeps deps,
  TvSearchFocusHandoff searchSubmitFocus,
) {
  late final KeywordSearchSection keywordSection;
  late final KeywordSearchDialogs keywordDialogs;
  late final KeywordSelection keywordSelection;
  late final KeywordSearchActions keywordActions;
  late final KeywordSearchRows keywordRows;

  keywordSection = KeywordSearchSection(ref, (
    session: () => deps.session().searchSession,
    bindings: () => deps.session().searchResultBindings,
    mode: () => deps.mode().mode,
    mounted: deps.mounted,
    setState: deps.setState,
    focusSearch: () => deps.input().focusSearchFieldAtEnd(),
    focusSearchNode: () => deps.input().searchFocusNode.requestFocus(),
    focusSidebar: deps.sidebar,
    completeSubmitFocus: (target) =>
        deps.input().completeSearchSubmitFocus(target),
    cancelSubmitFocus: searchSubmitFocus.cancel,
  ));
  keywordDialogs = KeywordSearchDialogs(ref, (
    context: deps.context,
    mounted: deps.mounted,
    session: () => deps.session().searchSession,
    bindings: () => deps.session().searchResultBindings,
    toolbarNodes: () => keywordSection.kwToolbarNodes,
    freezeAndAdopt: keywordSection.kwFreezeAndAdopt,
    syncResults: keywordSection.syncKeywordResults,
    runKeyword: keywordSection.runKeyword,
  ));
  keywordSelection = KeywordSelection((
    mounted: deps.mounted,
    controller: () => keywordSection.keywordResultsController,
    toolbarNodes: () => keywordSection.kwToolbarNodes,
    freezeAndAdopt: keywordSection.kwFreezeAndAdopt,
  ));
  keywordActions = deps.createActions(keywordSection, keywordSelection);
  final keywordFrame = KeywordSearchFrame(
    (
      isTelevision: deps.isTelevision,
      bindings: () => deps.session().searchResultBindings,
      focus: () => keywordSection.keywordFocus,
      floatingNavigation: deps.floatingNavigation,
      focusSearchNode: () => deps.input().searchFocusNode.requestFocus(),
      freeze: keywordSection.kwFreeze,
      setSourceTab: keywordSection.setKwSourceTab,
    ),
    keywordSection.keywordViewport,
    keywordSection.kwCinemaKey,
    keywordActions,
    keywordSelection,
  );
  keywordRows = KeywordSearchRows(
    (
      mounted: deps.mounted,
      isTelevision: deps.isTelevision,
      bindings: () => deps.session().searchResultBindings,
      focus: () => keywordSection.keywordFocus,
      appearance: () => keywordSection.appearance,
      message: (icon, title, body, {VoidCallback? onRetry}) =>
          deps.board().message(icon, title, body, onRetry: onRetry),
      focusSearch: () => deps.input().focusSearchFieldAtEnd(),
      focusSidebar: deps.sidebar,
      focusAboveResults: keywordSection.focusAboveKeywordResults,
      freeze: keywordSection.kwFreeze,
      adopt: keywordSection.kwAdoptPending,
      setSourceTab: keywordSection.setKwSourceTab,
    ),
    keywordSection.keywordViewport,
    keywordActions,
    keywordDialogs,
    keywordSelection,
    keywordFrame,
  );
  return (
    keywordSection: keywordSection,
    keywordDialogs: keywordDialogs,
    keywordSelection: keywordSelection,
    keywordRows: keywordRows,
  );
}
