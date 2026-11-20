import '../../../features/ledger/models/ledger_media.dart';
import '../../../features/ledger/models/ledger_tracking.dart';
import '../../../models/advanced_search_selection.dart';
import '../../../models/media_identity.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/continue_watching_presentation.dart';

/// One Ledger Continue Watching card: a movie or episode to resume, or a
/// show's next episode ("up next", no progress bar).
class HomeLedgerContinuationItem {
  const HomeLedgerContinuationItem({
    required this.meta,
    required this.progress,
    required this.season,
    required this.episode,
    required this.playbackId,
    required this.activityAtMs,
  });

  final StremioMeta meta;

  /// 0–100 for a resume point; null for an up-next episode.
  final double? progress;
  final int? season;
  final int? episode;

  /// The saved resume point behind a RESUME entry (removal deletes it).
  final String? playbackId;
  final int? activityAtMs;

  bool get isMovie => meta.type == 'movie';
  bool get isUpNext => progress == null && !isMovie;
  String get id => meta.progressId ?? meta.id;

  /// The exact resume payload for quick play.
  AdvancedSearchSelection get selection => AdvancedSearchSelection(
    imdbId: id,
    isSeries: !isMovie,
    title: meta.name,
    year: meta.year,
    season: season,
    episode: episode,
    contentType: meta.type,
    posterUrl: meta.poster,
    ledgerProgressPercent: progress,
    ledgerSource: true,
  );

  /// Builds a card from an Up Next entry; null for items without an IMDb id
  /// (the app's catalog identity) or an episode without its numbers.
  static HomeLedgerContinuationItem? fromEntry(LedgerUpNextEntry entry) {
    final item = entry.item;
    final isMovie = item.kind == LedgerMediaKind.movie;
    final title = isMovie ? item : item.show;
    final imdb = title?.ids.imdb;
    if (title == null || imdb == null || !MediaIdentity.isImdb(imdb)) {
      return null;
    }
    if (!isMovie && (item.season == null || item.number == null)) return null;
    final resume = entry.reason == LedgerUpNextReason.resume;
    final progress = resume ? entry.progress : null;
    return HomeLedgerContinuationItem(
      meta: StremioMeta(
        id: imdb,
        imdbId: imdb,
        type: isMovie ? 'movie' : 'series',
        name: title.name ?? imdb,
        poster: 'https://images.metahub.space/poster/medium/$imdb/img',
        year: title.year?.toString(),
      ),
      // A resume point at 0% has nothing to resume; show it as up next.
      progress: progress == null || progress <= 0 ? null : progress,
      season: isMovie ? null : item.season,
      episode: isMovie ? null : item.number,
      playbackId: resume ? entry.playbackId : null,
      activityAtMs: entry.lastActivityAt?.millisecondsSinceEpoch,
    );
  }
}

/// Detached, read-only Ledger shelf. One row: movies and episodes together,
/// in the server's Up Next order (most recent activity first).
class HomeLedgerContinuation {
  const HomeLedgerContinuation.empty()
    : all = const [],
      progress = const {},
      episode = const {},
      episodeRefs = const {},
      byKey = const {};

  HomeLedgerContinuation._({
    required List<StremioMeta> all,
    required Map<String, double> progress,
    required Map<String, String> episode,
    required Map<String, ({int season, int episode})> episodeRefs,
    required Map<String, HomeLedgerContinuationItem> byKey,
  }) : all = List.unmodifiable(all),
       progress = Map.unmodifiable(progress),
       episode = Map.unmodifiable(episode),
       episodeRefs = Map.unmodifiable(episodeRefs),
       byKey = Map.unmodifiable(byKey);

  static String cardKey(StremioMeta item) => item.progressId ?? item.id;

  factory HomeLedgerContinuation.fromItems(
    List<HomeLedgerContinuationItem> items,
  ) {
    final all = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final byKey = <String, HomeLedgerContinuationItem>{};
    for (final it in items) {
      final id = cardKey(it.meta);
      // One card per title: the server lists a show once, but a movie and a
      // show could in principle share nothing else, so dedup defensively.
      if (id.isEmpty || byKey.containsKey(id)) continue;
      all.add(it.meta);
      byKey[id] = it;
      final p = it.progress;
      if (p != null) progress[id] = (p / 100).clamp(0.0, 1.0);
      final label = continueWatchingEpisodeLabel(it.season, it.episode);
      if (label != null) episode[id] = label;
      if (it.season != null &&
          it.episode != null &&
          it.season! > 0 &&
          it.episode! > 0) {
        episodeRefs[id] = (season: it.season!, episode: it.episode!);
      }
    }
    return HomeLedgerContinuation._(
      all: all,
      progress: progress,
      episode: episode,
      episodeRefs: episodeRefs,
      byKey: byKey,
    );
  }

  final List<StremioMeta> all;
  final Map<String, double> progress;
  final Map<String, String> episode;
  final Map<String, ({int season, int episode})> episodeRefs;
  final Map<String, HomeLedgerContinuationItem> byKey;

  bool get isEmpty => all.isEmpty;
}
