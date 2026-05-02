import 'package:flutter/foundation.dart';

import '../../models/advanced_search_selection.dart';
import '../../models/stremio_addon.dart';
import 'trakt_item_transformer.dart';
import 'trakt_service.dart';

class TraktContinueWatchingItem {
  final StremioMeta meta;
  final String traktContentType;
  final double? progress;
  final int? season;
  final int? episode;
  final int? runtime;
  final List<int> playbackIds;

  const TraktContinueWatchingItem({
    required this.meta,
    required this.traktContentType,
    this.progress,
    this.season,
    this.episode,
    this.runtime,
    this.playbackIds = const [],
  });

  String get id => meta.effectiveImdbId ?? meta.id;
  String get title => meta.name;
  String? get year => meta.year;
  String? get posterUrl => meta.poster;
  bool get isSeries => meta.type == 'series';
}

class TraktContinueWatchingService {
  TraktContinueWatchingService._({TraktService? traktService})
    : _traktService = traktService ?? TraktService.instance;

  static final TraktContinueWatchingService instance =
      TraktContinueWatchingService._();

  static const moviesContentType = 'movies';
  static const showsContentType = 'episodes';

  final TraktService _traktService;

  Future<List<TraktContinueWatchingItem>> fetchMovies() {
    return fetchItems(moviesContentType);
  }

  Future<List<TraktContinueWatchingItem>> fetchShows() {
    return fetchItems(showsContentType);
  }

  Future<List<TraktContinueWatchingItem>> fetchItems(
    String traktContentType,
  ) async {
    try {
      final isAuth = await _traktService.isAuthenticated();
      if (!isAuth) return [];

      var rawItems = await _traktService.fetchPlaybackItems(traktContentType);

      if (traktContentType == showsContentType) {
        final playbackImdbIds = <String>{};
        for (final raw in rawItems) {
          if (raw is! Map<String, dynamic>) continue;
          final show = raw['show'] as Map<String, dynamic>?;
          final ids = show?['ids'] as Map<String, dynamic>?;
          final imdbId = ids?['imdb'] as String?;
          if (imdbId != null) playbackImdbIds.add(imdbId);
        }

        final recentWithNext = await _traktService
            .fetchRecentShowsWithNextEpisode(excludeImdbIds: playbackImdbIds);
        if (recentWithNext.isNotEmpty) {
          rawItems = List<dynamic>.from(rawItems)..addAll(recentWithNext);
        }
      }

      if (rawItems.isEmpty) return [];

      return traktContentType == moviesContentType
          ? _buildMovieItems(rawItems)
          : _buildShowItems(rawItems);
    } catch (e) {
      debugPrint('TraktContinueWatchingService: fetchItems failed: $e');
      return [];
    }
  }

  Future<AdvancedSearchSelection?> resolveSelection({
    required String traktContentType,
    required String? itemId,
  }) async {
    final items = await fetchItems(traktContentType);
    if (items.isEmpty) return null;

    final selected = itemId == null || itemId.isEmpty
        ? items.first
        : items.cast<TraktContinueWatchingItem?>().firstWhere(
            (item) => item?.id == itemId,
            orElse: () => null,
          );
    if (selected == null) return null;

    return selectionForItem(selected);
  }

  Future<AdvancedSearchSelection?> selectionForItem(
    TraktContinueWatchingItem item,
  ) async {
    int? season = item.season;
    int? episode = item.episode;
    double? traktProgress = _visibleProgress(item.progress);

    if (item.isSeries) {
      final showId = item.id;
      if (season == null || episode == null || season <= 0 || episode <= 0) {
        final next = await _traktService.fetchNextEpisode(showId);
        if (next == null) return null;
        season = next.season;
        episode = next.episode;
      }

      final episodeProgress = await _traktService.fetchEpisodePlaybackProgress(
        showId,
      );
      final progress = episodeProgress['$season-$episode'];
      traktProgress = _visibleProgress(progress) ?? traktProgress;
    }

    return AdvancedSearchSelection(
      imdbId: item.id,
      isSeries: item.isSeries,
      title: item.title,
      year: item.year,
      season: season,
      episode: episode,
      contentType: item.meta.type,
      posterUrl: item.posterUrl,
      traktProgressPercent: traktProgress,
      traktSource: true,
    );
  }

  List<TraktContinueWatchingItem> _buildMovieItems(List<dynamic> rawItems) {
    final metas = TraktItemTransformer.transformList(
      rawItems,
      inferredType: 'movie',
    );
    final progressById = <String, double>{};
    final playbackIdsById = <String, List<int>>{};

    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) continue;
      final progress = raw['progress'] as num?;
      final playbackId = raw['id'] as int?;
      final movie = raw['movie'] as Map<String, dynamic>?;
      final ids = movie?['ids'] as Map<String, dynamic>?;
      final imdbId = ids?['imdb'] as String?;
      if (imdbId == null) continue;
      if (progress != null) progressById[imdbId] = progress.toDouble();
      if (playbackId != null) {
        playbackIdsById.putIfAbsent(imdbId, () => []).add(playbackId);
      }
    }

    return metas
        .map(
          (meta) => TraktContinueWatchingItem(
            meta: meta,
            traktContentType: moviesContentType,
            progress: progressById[meta.id],
            playbackIds: playbackIdsById[meta.id] ?? const [],
          ),
        )
        .toList();
  }

  List<TraktContinueWatchingItem> _buildShowItems(List<dynamic> rawItems) {
    final metas = TraktItemTransformer.transformPlaybackEpisodes(rawItems);
    final progressById = <String, double>{};
    final playbackIdsById = <String, List<int>>{};
    final episodeInfoById =
        <String, ({int season, int episode, int? runtime})>{};

    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) continue;
      final progress = raw['progress'] as num?;
      final playbackId = raw['id'] as int?;
      final show = raw['show'] as Map<String, dynamic>?;
      final ids = show?['ids'] as Map<String, dynamic>?;
      final imdbId = ids?['imdb'] as String?;
      final episode = raw['episode'] as Map<String, dynamic>?;
      if (imdbId == null) continue;

      if (progress != null) {
        progressById.putIfAbsent(imdbId, () => progress.toDouble());
      }
      if (playbackId != null) {
        playbackIdsById.putIfAbsent(imdbId, () => []).add(playbackId);
      }
      if (episode != null && !episodeInfoById.containsKey(imdbId)) {
        episodeInfoById[imdbId] = (
          season: episode['season'] as int? ?? 0,
          episode: episode['number'] as int? ?? 0,
          runtime: episode['runtime'] as int?,
        );
      }
    }

    return metas.map((meta) {
      final episodeInfo = episodeInfoById[meta.id];
      return TraktContinueWatchingItem(
        meta: meta,
        traktContentType: showsContentType,
        progress: progressById[meta.id],
        season: episodeInfo?.season,
        episode: episodeInfo?.episode,
        runtime: episodeInfo?.runtime,
        playbackIds: playbackIdsById[meta.id] ?? const [],
      );
    }).toList();
  }

  double? _visibleProgress(double? progress) {
    if (progress == null || progress <= 0 || progress >= 100) return null;
    return progress;
  }
}
