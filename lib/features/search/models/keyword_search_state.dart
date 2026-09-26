import '../../../models/torrent.dart';

enum KeywordSearchStatus { idle, searching, complete, failed }

/// Latest engine publication. The view may temporarily keep an older displayed
/// projection when interaction freezes arrivals; that projection is not a query.
class KeywordSearchState {
  final int request;
  final String query;
  final KeywordSearchStatus status;
  final List<Torrent>? results;
  final String? error;

  const KeywordSearchState.idle({required this.request, this.query = ''})
    : status = KeywordSearchStatus.idle,
      results = null,
      error = null;

  KeywordSearchState({
    required this.request,
    required this.query,
    required this.status,
    List<Torrent>? results,
    this.error,
  }) : results = results == null ? null : List.unmodifiable(results);

  bool get searching => status == KeywordSearchStatus.searching;
  bool get loading => searching && results == null;
}
