import 'package:flutter/widgets.dart';
import '../../features/discover/presentation/discover_section.dart';
import '../../features/home/presentation/home_screen_controls.dart';
import '../../features/search/models/search_mode.dart';
import '../../features/search/presentation/keyword_search_section.dart';
import '../../features/search/presentation/lists_search_section.dart';
import '../../features/search/presentation/search_input_section.dart';
import '../../features/search/presentation/search_mode_section.dart';

/// Implements Home's view of the screen controls over the Search and Discover
/// sections. Sections are resolved at call time, as the direct references were.
class HomeScreenControlsAdapter implements HomeScreenControls {
  HomeScreenControlsAdapter({
    required this.input,
    required this.modes,
    required this.lists,
    required this.keyword,
    required this.discover,
  });
  final SearchInputSection Function() input;
  final SearchModeSection Function() modes;
  final ListsSearchSection Function() lists;
  final KeywordSearchSection Function() keyword;
  final DiscoverSection Function() discover;

  @override
  SearchMode get mode => modes().mode;
  @override
  set mode(SearchMode mode) => modes().mode = mode;
  @override
  void switchMode(SearchMode mode) => modes().switchMode(mode);
  @override
  bool get searchFieldHasFocus => input().searchFocus.hasFocus;
  @override
  FocusNode get searchFieldNode => input().searchFocusNode;
  @override
  FocusNode get discoverSourceNode => discover().discSourceNode;
  @override
  List<FocusNode> get listsNodes => lists().listsNodes;
  @override
  void clearListsSearch() => lists().clearListsSearch();
  @override
  Future<void> loadSourceTextFormatting({bool Function()? isCurrent}) =>
      keyword().loadSourceTextFormatting(isCurrent: isCurrent);
}
