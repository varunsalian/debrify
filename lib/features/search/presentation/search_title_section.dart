import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/metadata_preferences.dart';
import '../../discover/models/metadata_feature_policy.dart';
import '../models/search_mode.dart';
import 'title_suggestion_presentation.dart';

typedef SearchTitleSectionDeps = ({
  SearchMode Function() mode,
  bool Function() searchMode,
  // Only the current policy state is read; its controller stays with its owner.
  MetadataFeaturePolicy Function() metadata,
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
  ValueChanged<StremioMeta> open,
  ValueChanged<String> submit,
});

/// Edit, composition and tab eligibility for the existing debounced title lookup.
class SearchTitleSection {
  SearchTitleSection(this._deps, this._searchController);
  final SearchTitleSectionDeps _deps;
  final TextEditingController _searchController;
  final presentation = TitleSuggestionPresentation();
  void onTitleSearchTabChanged() {
    if (_deps.activeTab() != 'search') {
      // Invalidate even if Search is reselected before the transition ends.
      cancelTitleSuggestions();
    }
  }

  void onTitleSearchEditingChanged() {
    final editing = _searchController.value;
    if (!presentation.acceptEdit(editing)) return;
    cancelSuggestedTitleOpen();
    scheduleTitleSuggestions();
  }

  void scheduleTitleSuggestions() {
    final preferences = _deps.metadata().preferences;
    final editing = _searchController.value;
    _deps.update(
      editing.text,
      language: preferences?.language ?? 'en-US',
      // Title lookup belongs only to Catalog. Keyword, Lists and pasted
      // links retain their own search semantics.
      enabled:
          _deps.searchMode() &&
          _deps.mode() == SearchMode.catalog &&
          _deps.activeTab() == 'search' &&
          _deps.metadata().ready &&
          !presentation.opening &&
          _deps.originCurrent() &&
          (preferences?.features.contains(MetadataFeature.discovery) ?? false),
      composing: editing.composing.isValid && !editing.composing.isCollapsed,
    );
  }

  void cancelSuggestedTitleOpen() => presentation.cancelOpen();

  void cancelTitleSuggestions() {
    cancelSuggestedTitleOpen();
    _deps.clear();
  }

  void publishTitleSuggestions() {
    presentation.publish(
      _deps.titles(),
      query: _searchController.text.trim(),
      onOpen: _deps.open,
      onSubmit: _deps.submit,
    );
  }
}
