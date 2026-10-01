import '../../../models/torrent.dart';
import '../models/keyword_results_state.dart';
import '../application/keyword_provider_selection.dart';

/// Pure display projections shared by streaming focus and Keyword rendering.
class KeywordResultsProjection {
  KeywordResultsProjection(this._read);
  final KeywordResultsState Function() _read;
  List<Torrent> get kwAll => _read().all;
  List<Torrent>? get kwPending => _read().pending;
  List<Torrent> get kwResults => _read().results;
  Map<String, int> get kwDirectCounts => _read().providers.directCounts;
  Map<String, int> get kwTorrentCounts => _read().providers.torrentCounts;
  Set<String> get kwSelectedDirect => _read().providers.selectedDirect;
  Set<String> get kwSelectedTorrent => _read().providers.selectedTorrent;

  /// Identity key for pending-row diffing (infohash when real, else the
  /// name+URL pair direct streams are distinguished by).
  static String kwRowKey(Torrent t) =>
      t.hasRealInfoHash && t.infohash.isNotEmpty
      ? 'h:${t.infohash.toLowerCase()}'
      : 'n:${t.name}|${t.directUrl ?? ''}';

  /// Rows waiting behind the pill (0 hides it) — a SET difference, not a
  /// length delta, so dedupe-shrunk pending sets still count their new rows.
  int get kwPendingNewCount {
    final p = kwPending;
    if (p == null) return 0;
    final shown = {for (final t in kwAll) kwRowKey(t)};
    var count = 0;
    for (final t in p) {
      if (!shown.contains(kwRowKey(t))) count++;
    }
    return count;
  }

  /// The fullest known result set: parked arrivals when frozen, else the
  /// displayed set. The tab strip derives from THIS so it live-updates
  /// (counts tick, new source pills appear) even while the rows are frozen —
  /// the strip sits above the list, so it never shifts what's being read.
  List<Torrent> get kwFullSet => kwPending ?? kwAll;

  /// Distinct sources in [kwFullSet], sorted — drives the tab strip.
  List<String> get kwSourceList {
    final s = <String>{for (final t in kwFullSet) keywordSourceOf(t)};
    final l = s.toList()..sort();
    return l;
  }

  /// The tab strip only earns its row when there's a real choice.
  bool get kwTabsVisible => kwSourceList.length > 1;

  // ── Bulk selection (keyword results) ──────────────────────────────────────
  /// Torrents eligible for bulk actions (excludes direct/external streams).
  List<Torrent> get kwSelectableResults =>
      kwResults.where((t) => !t.isDirectStream && !t.isExternalStream).toList();

  /// True when the provider (stream-type) filter is worth surfacing: at least
  /// two distinct sources exist across both groups, so filtering can change the
  /// result set. A single source imposes no meaningful choice.
  bool get kwHasProviderFilter =>
      (kwDirectCounts.length + kwTorrentCounts.length) >= 2;

  /// Count of source groups the user has narrowed away from "all selected" —
  /// drives the active state / badge on the Providers pill.
  int get kwProviderFilterActive {
    var n = 0;
    if (kwDirectCounts.isNotEmpty &&
        kwSelectedDirect.length != kwDirectCounts.length) {
      n += kwDirectCounts.length - kwSelectedDirect.length;
    }
    if (kwTorrentCounts.isNotEmpty &&
        kwSelectedTorrent.length != kwTorrentCounts.length) {
      n += kwTorrentCounts.length - kwSelectedTorrent.length;
    }
    return n;
  }
}
