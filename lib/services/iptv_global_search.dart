import 'package:flutter/foundation.dart';

import '../models/iptv_playlist.dart';
import 'iptv_catalog_cache.dart';
import 'iptv_catalog_db.dart';
import 'iptv_service.dart';
import 'storage_service.dart';
import 'xtream_codes_service.dart';

/// One searchable catalog: a stored playlist × content type. Backed either by
/// a materialized channel list (local files, legacy caches) or by a catalog-DB
/// [CatalogSnapshot] — the DB shape searches with SQL and never holds the
/// catalog on the heap.
class IptvGlobalSearchSource {
  final IptvPlaylist playlist;

  /// 'live' / 'vod' / 'series' for Xtream sources. For M3U/local sources this
  /// is 'mixed' — their entries carry no reliable type, so each channel is
  /// bucketed individually at search time via [IptvChannel.isLive].
  final String contentType;
  final List<IptvChannel> channels;

  /// Set for DB-backed sources; [channels] is then empty.
  final CatalogSnapshot? snapshot;

  const IptvGlobalSearchSource({
    required this.playlist,
    required this.contentType,
    required this.channels,
    this.snapshot,
  });

  int get channelCount => snapshot?.channelCount ?? channels.length;

  /// The live-channel zapping window around [channel] for a player launch,
  /// as (channels, startIndex). Falls back to just the channel itself when
  /// it can't be located.
  (List<IptvChannel>, int) liveZapWindow(IptvChannel channel, int maxSize) {
    final snap = snapshot;
    if (snap == null) {
      final live = contentType == 'mixed'
          ? [
              for (final c in channels)
                if (c.isLive) c,
            ]
          : channels;
      var idx = live.indexOf(channel);
      if (idx < 0) return ([channel], 0);
      var window = live;
      if (window.length > maxSize) {
        final lo = (idx - maxSize ~/ 2).clamp(0, window.length - maxSize);
        window = window.sublist(lo, lo + maxSize);
        idx -= lo;
      }
      return (window, idx);
    }
    // DB source: locate the hit's catalog position, then materialize only
    // the window around it (live rows only for mixed catalogs).
    final live = contentType == 'mixed' ? true : null;
    final position = snap.positionOf(url: channel.url, name: channel.name);
    if (position == null) return ([channel], 0);
    final before = snap.count(live: live, beforePosition: position);
    final total = snap.count(live: live);
    final lo =
        total > maxSize ? (before - maxSize ~/ 2).clamp(0, total - maxSize) : 0;
    final window = snap.page(offset: lo, limit: maxSize, live: live);
    if (window.isEmpty) return ([channel], 0);
    return (window, (before - lo).clamp(0, window.length - 1));
  }
}

/// A single search result: the channel plus enough context to act on it —
/// which playlist it came from (credentials for series drill-in, label for
/// the UI) and which section it belongs to.
class IptvGlobalSearchHit {
  final IptvChannel channel;
  final IptvGlobalSearchSource source;

  /// 'live' / 'vod' / 'series' — the result section.
  final String section;

  const IptvGlobalSearchHit({
    required this.channel,
    required this.source,
    required this.section,
  });
}

/// The outcome of one search: up to [IptvGlobalSearchIndex.sectionCap] hits
/// per section plus the true total per section (so the UI can say
/// "Movies · 3 of 240" honestly when it truncates).
class IptvGlobalSearchResults {
  final List<IptvGlobalSearchHit> live;
  final List<IptvGlobalSearchHit> vod;
  final List<IptvGlobalSearchHit> series;
  final int liveTotal;
  final int vodTotal;
  final int seriesTotal;

  const IptvGlobalSearchResults({
    required this.live,
    required this.vod,
    required this.series,
    required this.liveTotal,
    required this.vodTotal,
    required this.seriesTotal,
  });

  bool get isEmpty => liveTotal == 0 && vodTotal == 0 && seriesTotal == 0;
}

/// Cross-source IPTV search over the catalogs this device already has:
/// in-memory service caches first, then the disk snapshots the SWR layer
/// persists, then (for local-file playlists) the file content itself. No
/// network — the whole index loads in well under a second and works offline.
///
/// Deliberately excluded: Stremio-addon live TV (progressive, per-session)
/// and the virtual Favorites/Continue shelves (their channels already live in
/// a real source that IS indexed). A network-backed source the user has never
/// opened has no snapshot yet — it's reported in [unindexed] so the UI can
/// say so instead of silently searching past it.
class IptvGlobalSearchIndex {
  final List<IptvGlobalSearchSource> sources;

  /// Human-readable labels ("Sports Pro · Movies") for source × type pairs
  /// that exist but have nothing cached to search.
  final List<String> unindexed;

  const IptvGlobalSearchIndex({
    required this.sources,
    required this.unindexed,
  });

  static const int sectionCap = 60;
  static const _xtreamTypes = ['live', 'vod', 'series'];
  static const _xtreamTypeLabels = {
    'live': 'Live TV',
    'vod': 'Movies',
    'series': 'Series',
  };

  int get itemCount {
    var n = 0;
    for (final s in sources) {
      n += s.channelCount;
    }
    return n;
  }

  static Future<IptvGlobalSearchIndex> load() async {
    final playlists = await StorageService.getIptvPlaylists();
    final sources = <IptvGlobalSearchSource>[];
    final unindexed = <String>[];

    // Catalog-DB rows are the primary index when the mode is on — they
    // survive across sessions and never materialize on this heap.
    final dbEnabled = await StorageService.getIptvDbCatalogEnabled();
    if (dbEnabled) await IptvCatalogDb.open();

    CatalogSnapshot? dbSnapshot(IptvPlaylist playlist, String type) {
      if (!dbEnabled) return null;
      final key = IptvCatalogCache.keyForPlaylist(playlist, type);
      if (key == null) return null;
      final snap = IptvCatalogDb.snapshot(key);
      return (snap != null && snap.channelCount > 0) ? snap : null;
    }

    for (final playlist in playlists) {
      if (playlist.isXtreamCodes) {
        final server = playlist.serverUrl!;
        final user = playlist.username ?? '';
        for (final type in _xtreamTypes) {
          final snap = dbSnapshot(playlist, type);
          if (snap != null) {
            sources.add(IptvGlobalSearchSource(
              playlist: playlist,
              contentType: type,
              channels: const [],
              snapshot: snap,
            ));
            continue;
          }
          // Same-session memory cache first (free), then the disk snapshot.
          var channels = XtreamCodesService.instance
              .cachedResult(server, user, type)
              ?.channels;
          if (channels == null) {
            final key = IptvCatalogCache.keyForPlaylist(playlist, type);
            if (key != null) {
              channels =
                  (await IptvCatalogCache.instance.read(key))?.channels;
            }
          }
          if (channels != null && channels.isNotEmpty) {
            sources.add(IptvGlobalSearchSource(
              playlist: playlist,
              contentType: type,
              channels: channels,
            ));
          } else {
            unindexed.add('${playlist.name} · ${_xtreamTypeLabels[type]}');
          }
        }
      } else if (playlist.isLocalFile) {
        // The file content is already on-device — parse it (off the UI
        // isolate for big files) rather than reporting it unsearchable.
        try {
          final result =
              await IptvService.instance.parseContent(playlist.content!);
          if (result.channels.isNotEmpty) {
            sources.add(IptvGlobalSearchSource(
              playlist: playlist,
              contentType: 'mixed',
              channels: result.channels,
            ));
          }
        } catch (_) {
          unindexed.add(playlist.name);
        }
      } else if (playlist.url.isNotEmpty && !playlist.isStremioAddon) {
        final snap = dbSnapshot(playlist, 'live');
        if (snap != null) {
          sources.add(IptvGlobalSearchSource(
            playlist: playlist,
            contentType: 'mixed',
            channels: const [],
            snapshot: snap,
          ));
          continue;
        }
        var channels = IptvService.instance.cachedResult(playlist.url)?.channels;
        if (channels == null) {
          final key = IptvCatalogCache.keyForPlaylist(playlist, 'live');
          if (key != null) {
            channels = (await IptvCatalogCache.instance.read(key))?.channels;
          }
        }
        if (channels != null && channels.isNotEmpty) {
          sources.add(IptvGlobalSearchSource(
            playlist: playlist,
            contentType: 'mixed',
            channels: channels,
          ));
        } else {
          unindexed.add(playlist.name);
        }
      }
    }

    return IptvGlobalSearchIndex(sources: sources, unindexed: unindexed);
  }

  static List<String> _tokenize(String query) => query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  static const IptvGlobalSearchResults _empty = IptvGlobalSearchResults(
    live: [], vod: [], series: [],
    liveTotal: 0, vodTotal: 0, seriesTotal: 0,
  );

  /// AND-semantics substring search over every indexed channel's precomputed
  /// [IptvChannel.searchKey] (lowercased name + group). Within each section,
  /// hits whose channel NAME starts with the first term lead; source order
  /// (and catalog order within a source) breaks ties.
  ///
  /// This runs the scan on the UI isolate. Prefer [searchAsync], which does the
  /// exact same work on a worker so a six-figure catalog never blocks a frame;
  /// this is kept as the shared algorithm and a synchronous fallback.
  IptvGlobalSearchResults search(String query) {
    final terms = _tokenize(query);
    if (terms.isEmpty) return _empty;
    return _reassemble(_run(
      [
        for (var i = 0; i < sources.length; i++)
          _Searchable(i, sources[i].contentType, sources[i].snapshot,
              sources[i].channels),
      ],
      terms,
    ));
  }

  /// Same result as [search], but the whole scan runs on a WORKER isolate, so
  /// typing/searching never blocks the UI — no matter the catalog size. Uses
  /// only ordinary SQL (`LIKE`) via the worker's own connection; no optional
  /// SQLite feature, nothing that can be missing on a device.
  Future<IptvGlobalSearchResults> searchAsync(String query) async {
    final terms = _tokenize(query);
    if (terms.isEmpty) return _empty;
    final hasDb = sources.any((s) => s.snapshot != null);
    final job = _SearchJob(
      query: query,
      dbPath: hasDb ? IptvCatalogDb.path : null,
      sources: [
        for (var i = 0; i < sources.length; i++)
          _JobSource(
            index: i,
            contentType: sources[i].contentType,
            catalogKey: sources[i].snapshot?.catalogKey,
            generation: sources[i].snapshot?.generation,
            channels:
                sources[i].snapshot == null ? sources[i].channels : const [],
          ),
      ],
    );
    final raw = await compute(_iptvGlobalSearchWorker, job);
    return _reassemble(raw);
  }

  /// Rebuilds hits that point at THIS index's live source objects (the worker
  /// only sent back source indices — it can't ship a CatalogSnapshot).
  ///
  /// For memory sources the worker's channel is a cross-isolate COPY; swap it
  /// back for the live object at [_RawHit.channelIndex] so `liveZapWindow`'s
  /// identity lookup still finds it. (Out-of-range guard: if the source list
  /// changed under us, fall back to the copy — display is fine, only zapping
  /// degrades.)
  IptvGlobalSearchResults _reassemble(_RawResults raw) {
    IptvGlobalSearchHit hit(_RawHit r) {
      final source = sources[r.sourceIndex];
      final channel =
          (r.channelIndex >= 0 && r.channelIndex < source.channels.length)
              ? source.channels[r.channelIndex]
              : r.channel;
      return IptvGlobalSearchHit(
        channel: channel,
        source: source,
        section: r.section,
      );
    }
    return IptvGlobalSearchResults(
      live: [for (final r in raw.live) hit(r)],
      vod: [for (final r in raw.vod) hit(r)],
      series: [for (final r in raw.series) hit(r)],
      liveTotal: raw.liveTotal,
      vodTotal: raw.vodTotal,
      seriesTotal: raw.seriesTotal,
    );
  }

  /// The bucketing core, shared by the inline and worker paths. Produces raw
  /// hits keyed by source index (sendable); the caller reassembles them into
  /// [IptvGlobalSearchHit]s against its live source objects.
  static _RawResults _run(List<_Searchable> items, List<String> terms) {
    // Two buckets per section: name-prefix matches lead, the rest follow.
    final lead = {
      'live': <_RawHit>[],
      'vod': <_RawHit>[],
      'series': <_RawHit>[],
    };
    final rest = {
      'live': <_RawHit>[],
      'vod': <_RawHit>[],
      'series': <_RawHit>[],
    };
    final totals = {'live': 0, 'vod': 0, 'series': 0};

    for (final item in items) {
      final snap = item.snapshot;
      if (snap != null) {
        // DB-backed source: the same rules in SQL — totals from COUNT, lead
        // (name-prefix) hits filled first, remaining capacity from the rest,
        // all in catalog order. Nothing materializes beyond the hits.
        void collect(String section, bool? live) {
          totals[section] =
              totals[section]! + snap.searchCount(terms, live: live);
          final sectionLead = lead[section]!;
          final sectionRest = rest[section]!;
          final leadRoom = sectionCap - sectionLead.length;
          for (final channel in snap.searchPage(
            terms,
            live: live,
            namePrefixLead: true,
            limit: leadRoom,
          )) {
            // -1: DB hits are materialized copies located by url+name, not by
            // in-memory index (see liveZapWindow's DB branch).
            sectionLead.add(_RawHit(item.index, channel, section, -1));
          }
          final restRoom =
              sectionCap - sectionLead.length - sectionRest.length;
          for (final channel in snap.searchPage(
            terms,
            live: live,
            namePrefixLead: false,
            limit: restRoom,
          )) {
            sectionRest.add(_RawHit(item.index, channel, section, -1));
          }
        }

        if (item.contentType == 'mixed') {
          collect('live', true);
          collect('vod', false);
        } else {
          collect(item.contentType, null);
        }
        continue;
      }
      for (var ci = 0; ci < item.channels.length; ci++) {
        final channel = item.channels[ci];
        final key = channel.searchKey;
        var matches = true;
        for (final term in terms) {
          if (!key.contains(term)) {
            matches = false;
            break;
          }
        }
        if (!matches) continue;

        final section = item.contentType == 'mixed'
            ? (channel.isLive ? 'live' : 'vod')
            : item.contentType;
        totals[section] = totals[section]! + 1;

        // A section keeps accepting name-prefix matches until the LEAD
        // bucket alone is full — a late source's exact-prefix hit must not
        // be crowded out by an early source's substring matches (the merge
        // below truncates rest to fit).
        final sectionLead = lead[section]!;
        final sectionRest = rest[section]!;
        final isLead = channel.name.toLowerCase().startsWith(terms.first);
        // ci lets [_reassemble] restore the LIVE channel object after the
        // worker returned a copy — so identity-based zapping still works.
        final hit = _RawHit(item.index, channel, section, ci);
        if (isLead) {
          if (sectionLead.length < sectionCap) sectionLead.add(hit);
        } else {
          if (sectionLead.length + sectionRest.length < sectionCap) {
            sectionRest.add(hit);
          }
        }
      }
    }

    List<_RawHit> merge(String s) =>
        [...lead[s]!, ...rest[s]!].take(sectionCap).toList();
    return _RawResults(
      live: merge('live'),
      vod: merge('vod'),
      series: merge('series'),
      liveTotal: totals['live']!,
      vodTotal: totals['vod']!,
      seriesTotal: totals['series']!,
    );
  }
}

// ── Isolate plumbing ────────────────────────────────────────────────────────

/// A hit as computed on a worker: the source is named by its index into the
/// index's `sources` list (the worker can't send back a CatalogSnapshot), plus
/// the channel and section. Sendable across isolates.
///
/// [channelIndex] is the hit's position in a MEMORY source's `channels` list
/// (or -1 for DB-materialized hits). Across an isolate the worker returns a
/// COPY of the channel, and `liveZapWindow` locates the channel by identity —
/// so [_reassemble] uses this index to swap the copy back for the live object.
class _RawHit {
  final int sourceIndex;
  final IptvChannel channel;
  final String section;
  final int channelIndex;
  const _RawHit(this.sourceIndex, this.channel, this.section, this.channelIndex);
}

class _RawResults {
  final List<_RawHit> live;
  final List<_RawHit> vod;
  final List<_RawHit> series;
  final int liveTotal;
  final int vodTotal;
  final int seriesTotal;
  const _RawResults({
    required this.live,
    required this.vod,
    required this.series,
    required this.liveTotal,
    required this.vodTotal,
    required this.seriesTotal,
  });
}

/// One source to search, resolved to whatever the current isolate can use: a
/// live snapshot (UI isolate) or one the worker pinned on its own connection.
class _Searchable {
  final int index;
  final String contentType;
  final CatalogSnapshot? snapshot;
  final List<IptvChannel> channels;
  const _Searchable(
      this.index, this.contentType, this.snapshot, this.channels);
}

/// Sendable description of a source for the worker: a DB source carries its
/// (catalogKey, generation) so the worker can re-pin a snapshot on its own
/// connection; a mem source carries its channels.
class _JobSource {
  final int index;
  final String contentType;
  final String? catalogKey;
  final int? generation;
  final List<IptvChannel> channels;
  const _JobSource({
    required this.index,
    required this.contentType,
    required this.catalogKey,
    required this.generation,
    required this.channels,
  });
}

class _SearchJob {
  final String query;

  /// The catalog DB path, or null when the index has no DB-backed source.
  final String? dbPath;
  final List<_JobSource> sources;
  const _SearchJob({
    required this.query,
    required this.dbPath,
    required this.sources,
  });
}

/// Worker entry (top-level, for [compute]): opens its own DB connection when
/// the job has DB sources, re-pins each snapshot on it, and runs the shared
/// bucketing algorithm.
_RawResults _iptvGlobalSearchWorker(_SearchJob job) {
  final terms = IptvGlobalSearchIndex._tokenize(job.query);
  if (terms.isEmpty) {
    return const _RawResults(
      live: [], vod: [], series: [],
      liveTotal: 0, vodTotal: 0, seriesTotal: 0,
    );
  }
  List<_Searchable> build(CatalogSnapshot? Function(_JobSource) resolve) => [
        for (final s in job.sources)
          _Searchable(s.index, s.contentType, resolve(s), s.channels),
      ];

  final dbPath = job.dbPath;
  if (dbPath == null) {
    return IptvGlobalSearchIndex._run(build((_) => null), terms);
  }
  return IptvCatalogDb.withConnection(dbPath, (db) {
    return IptvGlobalSearchIndex._run(
      build((s) => s.catalogKey == null
          ? null
          : IptvCatalogDb.snapshotOn(db, s.catalogKey!, s.generation!)),
      terms,
    );
  });
}
