import '../../../models/torrent.dart';

/// The engine service's authoritative completion, without its untyped payload.
class KeywordSearchResult {
  final List<Torrent> torrents;
  final bool anyEngineRan;
  final bool hasEngineErrors;

  KeywordSearchResult({
    required List<Torrent> torrents,
    required this.anyEngineRan,
    required this.hasEngineErrors,
  }) : torrents = List.unmodifiable(torrents);
}
