import '../models/iptv_playlist.dart';
import '../utils/m3u_parser.dart';
import 'iptv_catalog_db.dart';
import 'iptv_catalog_key.dart';

/// What the settings page can honestly say about one playlist without
/// fetching anything: the counts and freshness of whatever is already
/// ingested in the catalog DB.
///
/// Everything here is read from committed catalog rows, so a source that has
/// never been opened reports [cached] false rather than a zero — "not loaded
/// yet" and "empty playlist" are different statements and must not look alike.
///
/// Deliberately NOT reported: an EPG match rate. Nothing precomputes one, and
/// deriving it would mean scanning every channel against the guide store on
/// every focus move. [guide] says where guide data would come from instead,
/// which is knowable for free.
class IptvSourceStats {
  const IptvSourceStats({
    required this.cached,
    required this.live,
    required this.movies,
    required this.series,
    required this.categories,
    required this.refreshedAt,
    required this.guide,
  });

  /// Nothing ingested for this source yet (or it isn't cacheable at all —
  /// local files and virtual shelves have no catalog rows).
  const IptvSourceStats.none()
    : cached = false,
      live = 0,
      movies = 0,
      series = 0,
      categories = 0,
      refreshedAt = null,
      guide = IptvGuideSource.none;

  final bool cached;
  final int live;
  final int movies;
  final int series;

  /// Distinct provider categories in the live catalog.
  final int categories;

  /// When the newest of this source's catalogs was ingested.
  final DateTime? refreshedAt;

  final IptvGuideSource guide;

  int get total => live + movies + series;

  /// Xtream logins split into three catalogs; a plain M3U is one flat list
  /// where the movie/series split isn't meaningful.
  bool get hasVodSplit => movies > 0 || series > 0;
}

enum IptvGuideSource {
  /// A custom XMLTV URL is set on the playlist itself.
  custom,

  /// The playlist (or panel) declared its own guide — url-tvg or Xtream.
  provider,

  /// No guide data will be available for this source.
  none,
}

class IptvSourceStatsLoader {
  IptvSourceStatsLoader._();

  /// Read the stats for [playlist]. Cheap: a handful of indexed lookups
  /// against an already-open DB, no network and no full-table scans.
  ///
  /// Call [IptvCatalogDb.open] before this — a closed DB throws inside
  /// [IptvCatalogDb.snapshot], and the caller (a settings page) is better
  /// placed to await the open once than to have every row do it.
  static IptvSourceStats read(IptvPlaylist playlist) {
    // Resolved FIRST and independently of the catalog: whether a source has
    // guide data is a property of the source, not of whether its channels
    // happen to be ingested. Folding it into the DB paths meant a catalog
    // that was closed or failed to open made every source claim "no guide".
    final guide = _guideFor(playlist);

    // No catalog rows exist for these, so there is nothing to count. A local
    // file still plays; it just isn't ingested as a refreshable catalog.
    if (playlist.isVirtual || playlist.isLocalFile) {
      return _uncached(guide);
    }

    if (!IptvCatalogDb.isOpen) return _uncached(guide);

    var live = 0, movies = 0, series = 0, categories = 0;
    int? newest;
    var cached = false;
    var catalogDeclaresGuide = false;

    for (final type in _typesFor(playlist)) {
      final key = IptvCatalogKey.forPlaylist(playlist, type);
      if (key == null) continue;
      CatalogSnapshot? snap;
      try {
        snap = IptvCatalogDb.snapshot(key);
      } catch (_) {
        // A DB that closed or failed under us must not take the settings
        // page down with it — the source simply reads as uncached.
        return _uncached(guide);
      }
      if (snap == null) continue;
      cached = true;
      if ((snap.epgUrl ?? '').isNotEmpty) catalogDeclaresGuide = true;
      if (newest == null || snap.ingestedAt > newest) newest = snap.ingestedAt;
      switch (type) {
        case 'vod':
          movies += snap.channelCount;
        case 'series':
          series += snap.channelCount;
        default:
          live += snap.channelCount;
          categories += snap.categories.length;
      }
    }

    // A plain M3U only reveals its `url-tvg` once ingested, so the catalog
    // can promote none -> provider. It can never demote a custom URL.
    final resolved = guide == IptvGuideSource.none && catalogDeclaresGuide
        ? IptvGuideSource.provider
        : guide;

    if (!cached) return _uncached(resolved);

    return IptvSourceStats(
      cached: true,
      live: live,
      movies: movies,
      series: series,
      categories: categories,
      refreshedAt: newest == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(newest),
      guide: resolved,
    );
  }

  static IptvSourceStats _uncached(IptvGuideSource guide) => IptvSourceStats(
    cached: false,
    live: 0,
    movies: 0,
    series: 0,
    categories: 0,
    refreshedAt: null,
    guide: guide,
  );

  /// Where this source's programme data comes from, knowable without touching
  /// the catalog or the network.
  static IptvGuideSource _guideFor(IptvPlaylist playlist) {
    // An explicit XMLTV URL on the playlist wins over anything the source
    // would otherwise supply — that is the point of setting it.
    if ((playlist.epgUrl ?? '').isNotEmpty) return IptvGuideSource.custom;

    // An Xtream login always has guide data: per-stream get_short_epg plus
    // the panel's own xmltv.php, which is exactly what
    // IptvEpgService.isEpgCapable keys on. It is NOT discoverable from the
    // catalog — only the M3U ingest path ever writes epg_url — so waiting for
    // a snapshot to declare one reported "no guide" for every panel.
    if (playlist.isXtreamCodes) return IptvGuideSource.provider;

    // An imported file's guide lives in its `#EXTM3U` header, and playback
    // recovers it by reparsing the stored content, so `none` would be plainly
    // wrong for a guide that is actually running.
    if (playlist.isLocalFile) {
      return _headerDeclaresGuide(playlist.content)
          ? IptvGuideSource.provider
          : IptvGuideSource.none;
    }

    // A remote M3U declares its guide in a header we haven't fetched; the
    // ingested catalog answers this one.
    return IptvGuideSource.none;
  }

  /// Xtream stores one catalog per content type; a plain M3U URL stores one.
  static List<String> _typesFor(IptvPlaylist playlist) => playlist.isXtreamCodes
      ? IptvCatalogKey.xtreamContentTypes
      : const ['live'];

  /// Whether a stored playlist's `#EXTM3U` header declares an XMLTV guide.
  ///
  /// Only the first line is examined — that is where the header lives, and
  /// [content] can be tens of megabytes. Delegates the actual parse to
  /// [M3uParser.headerEpgUrl] so this can't drift from what the loader does.
  static bool _headerDeclaresGuide(String? content) {
    if (content == null || content.isEmpty) return false;
    final end = content.indexOf('\n');
    // A header longer than this isn't one; the cap stops a file with no
    // newlines at all from being scanned in full.
    const cap = 4096;
    final stop = end < 0 ? (content.length < cap ? content.length : cap) : end;
    final header = content.substring(0, stop).trim();
    if (!header.startsWith('#EXTM3U')) return false;
    return M3uParser.headerEpgUrl(header) != null;
  }

  /// "2h ago" / "just now" — a compact relative stamp for the source header.
  static String ago(DateTime? at, {DateTime? now}) {
    if (at == null) return 'never';
    final delta = (now ?? DateTime.now()).difference(at);
    if (delta.isNegative || delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    final weeks = delta.inDays ~/ 7;
    if (weeks < 5) return '${weeks}w ago';
    // Bucket on days, not on the derived month count: 360 days is 12 "months"
    // by the /30 approximation but 0 years by /365, which used to print
    // "0y ago". The month label is clamped for the same reason.
    if (delta.inDays < 365) {
      final months = (delta.inDays ~/ 30).clamp(1, 12);
      return '${months}mo ago';
    }
    return '${delta.inDays ~/ 365}y ago';
  }

  /// Thousands separators — "12,480" reads at 10 feet, "12480" doesn't.
  static String count(int n) {
    final digits = n.abs().toString();
    final buf = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}
