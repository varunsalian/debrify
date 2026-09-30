import 'package:flutter/widgets.dart';
import 'home_board_composition.dart';
import '../../features/home/presentation/home_catalog_badges.dart';
import '../../features/home/presentation/home_continuation_section.dart';
import '../../features/home/presentation/home_continuation_announcements.dart';
import '../../features/home/presentation/home_continuation_loading.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';
import '../../features/home/presentation/home_saved_content_section.dart';
import 'home_view_bindings.dart';

typedef HomeContinuationContentDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  HomeViewBindings Function() view,
  HomeBoardWorkflow Function() board,
  HomeCatalogBadges Function() badges,
  int Function() tabIndex,
  bool mdblistEnabled,
});

typedef HomeContinuationContent = ({
  HomeContinuationSection section,
  HomeContinuationLoading loading,
});

/// Constructs continuation content owners without starting loads or subscriptions.
HomeContinuationContent createHomeContinuationContent(
  HomeContinuationContentDeps deps,
  HomeSavedContentSection saved,
) {
  late final HomeContinuationSection section;
  late final HomeContinuationAnnouncements announcements;
  late final HomeContinuationLoading loading;
  section = HomeContinuationSection((
    bindings: () => deps.view().continuationBindings,
    artwork: () => deps.view().homeBoardBindings.artwork,
    mounted: deps.mounted,
    setState: deps.setState,
  ));
  announcements = HomeContinuationAnnouncements(
    (
      mounted: deps.mounted,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      loading: () => deps.board().boardSection.loading,
      activeTab: () => HomeHeroShellBridge.activeTvTabIndex == deps.tabIndex(),
      context: deps.context,
      disabled: () => deps.board().boardSection.homeDisabled,
      rowNodes: () => deps.board().boardSection.rowNodes,
    ),
    section,
    saved,
  );
  loading = HomeContinuationLoading(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      context: deps.context,
      requestRowFocus: (nodes, desired) =>
          deps.board().boardFocus.requestRowFocus(nodes, desired),
      autoFocus: () => deps.board().boardFocus.maybeAutoFocusBoard(),
      announceTrakt: announcements.maybeAnnounceTraktRows,
      announceSimkl: announcements.maybeAnnounceSimklRows,
      announceMdblist: announcements.maybeAnnounceMdblistRows,
      refreshBound: () => deps.badges().refreshBoundSources(),
    ),
    section,
    deps.mdblistEnabled,
  );
  return (section: section, loading: loading);
}
