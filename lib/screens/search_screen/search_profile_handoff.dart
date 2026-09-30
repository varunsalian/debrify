import 'package:flutter/widgets.dart';
import '../../features/home/presentation/home_board_rows.dart';
import '../../features/search/presentation/search_title_section.dart';
import '../../features/search/presentation/keyword_search_section.dart';
import '../../features/search/presentation/lists_search_section.dart';
import '../../features/search/presentation/catalog_search_section.dart';

/// Clears this mounted view's private search state during the existing profile handoff.
class SearchProfileHandoff {
  SearchProfileHandoff(
    this._profileChanged,
    this._searchController,
    this._titleSection,
    this._keywordSection,
    this._listsSection,
    this._catalogSection,
    this._boardRows,
  );
  final bool Function() _profileChanged;
  final TextEditingController _searchController;
  final SearchTitleSection _titleSection;
  final KeywordSearchSection _keywordSection;
  final ListsSearchSection _listsSection;
  final CatalogSearchSection _catalogSection;
  final HomeBoardRows _boardRows;

  void onSearchProfileChanged() {
    _titleSection.cancelTitleSuggestions();
    if (_profileChanged()) {
      _searchController.clear();
      _keywordSection.clearKeywordSearch();
      _listsSection.clearListsSearch();
      final hadCatalogSearch =
          _catalogSection.catalogQuery.isNotEmpty ||
          _catalogSection.catalogSearching;
      _catalogSection.catalogController.clear();
      if (hadCatalogSearch) _boardRows.applySections(const []);
    }
  }
}
