import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/tv_search_focus_handoff.dart';
import '../../discover/application/metadata_feature_controller.dart';
import 'search_mode_section.dart';
import 'search_title_section.dart';
import 'search_title_open.dart';

typedef SearchTitleCompositionDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  SearchModeSection Function() mode,
  bool Function() searchMode,
  MetadataFeatureController Function() metadata,
  String? Function() activeTab,
  bool Function() originCurrent,
  void Function(
    String, {
    required String language,
    bool enabled,
    bool composing,
  })
  update,
  VoidCallback clear,
  List<StremioMeta> Function() titles,
  Future<StremioMeta> Function(StremioMeta) Function() resolver,
  void Function(StremioMeta, StremioAddon) openItem,
});

typedef SearchTitleComposition = ({
  SearchTitleSection section,
  SearchTitleOpen opening,
});

/// Connects editing, title lookup and guarded detail opening without starting work.
SearchTitleComposition createSearchTitles(
  SearchTitleCompositionDeps deps,
  TextEditingController searchController,
  TvSearchFocusHandoff submitFocus,
) {
  late final SearchTitleSection title;
  late final SearchTitleOpen opening;
  title = SearchTitleSection((
    mode: () => deps.mode().mode,
    searchMode: deps.searchMode,
    metadata: deps.metadata,
    activeTab: deps.activeTab,
    originCurrent: deps.originCurrent,
    update: deps.update,
    clear: deps.clear,
    titles: deps.titles,
    open: (item) => opening.openSuggestedTitle(item),
    submit: (query) => deps.mode().onQuerySubmitted(query),
  ), searchController);
  opening = SearchTitleOpen(
    (
      mode: () => deps.mode().mode,
      mounted: deps.mounted,
      context: deps.context,
      activeTab: deps.activeTab,
      originCurrent: deps.originCurrent,
      cancelSubmitFocus: submitFocus.cancel,
      cancelTitleSuggestions: title.cancelTitleSuggestions,
      openItem: deps.openItem,
      resolver: deps.resolver,
      submit: (query) => deps.mode().onQuerySubmitted(query),
    ),
    searchController,
    title.presentation,
  );
  return (section: title, opening: opening);
}
