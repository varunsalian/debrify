import '../../../models/advanced_search_selection.dart';

class SourceSearchRequest {
  final AdvancedSearchSelection selection;
  final String? keyword;
  final List<int> availableSeasons;

  SourceSearchRequest({
    required this.selection,
    this.keyword,
    List<int> availableSeasons = const [],
  }) : availableSeasons = List.unmodifiable(availableSeasons);
}
