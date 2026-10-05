import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter/material.dart';

class DebrifyTvPlaybackFilters {
  final DebrifyTvDependencies _deps;
  DebrifyTvPlaybackFilters(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  /// Narrows a channel's cached torrents to the user's quality filter.
  /// Applied at cache READ time (not warm time) so changing the filter takes
  /// effect immediately instead of forcing a full channel rebuild the way the
  /// NSFW toggle does. Returns the input untouched when the filter is off, and
  /// falls back to the unfiltered pool (with a snackbar) when a channel has
  /// nothing at the requested quality — a filtered channel that plays nothing
  /// reads as broken, so it degrades instead of failing.
  List<CachedTorrent> _applyQualityFilterToCached(List<CachedTorrent> all) {
    if (!_owners.settings.tvFilters.hasQuality || all.isEmpty) return all;
    final matched = all
        .where(
          (cached) =>
              _owners.settings.tvFilters.qualityMatchesName(cached.name),
        )
        .toList();
    if (matched.isEmpty) {
      debugPrint(
        'DebrifyTV: Quality filter matched 0/${all.length} cached torrents — '
        'falling back to unfiltered.',
      );
      _sections.filters.notifyQualityFallback();
      return all;
    }
    if (matched.length != all.length) {
      debugPrint(
        'DebrifyTV: Quality filter on cached: ${all.length} → ${matched.length} torrents',
      );
    }
    return matched;
  }

  /// Quick-play twin of [_applyQualityFilterToCached], for the live search
  /// results each provider accumulates.
  ///
  /// [allowFallback] must stay false while a search is still streaming in.
  /// Quick play rebuilds this list on every engine that reports, and the RD
  /// flow launches the player from the first rebuild that yields something
  /// playable — so falling back on a partial result set would start playing an
  /// off-filter source just because the fastest engine happened to return
  /// none. Strict here means the queue simply stays empty until a matching
  /// result arrives. Pass true only once the result set is final, where an
  /// empty match genuinely means "this search has nothing".
  List<Torrent> applyQualityFilterToTorrents(
    List<Torrent> torrents, {
    bool allowFallback = false,
  }) {
    if (!_owners.settings.tvFilters.hasQuality || torrents.isEmpty)
      return torrents;
    final matched = torrents
        .where((t) => _owners.settings.tvFilters.qualityMatchesName(t.name))
        .toList();
    if (matched.isEmpty && allowFallback) {
      _sections.filters.notifyQualityFallback();
      return torrents;
    }
    return matched;
  }

  /// Tells the user once per playback session that the quality filter was
  /// relaxed. Rate-limited because the quick-play queue is rebuilt per engine
  /// and channel switches re-enter the same path.
  void notifyQualityFallback() {
    if (_owners.session.qualityFallbackNotified) return;
    _owners.session.qualityFallbackNotified = true;
    _sections.feedback.showSnack(
      'No ${_owners.settings.tvFilters.summary()} sources found — playing anything available.',
      color: Colors.orange,
    );
  }

  /// Whether an unrestricted Real-Debrid link may be played, per the size
  /// rules. RD is the one provider that hands back a flat list of links with
  /// no per-file metadata, so a file's size is only knowable AFTER
  /// unrestricting it — hence the check here rather than up front like the
  /// others. Links whose size RD doesn't report are accepted.
  ///
  /// Because RD can't pre-filter, a strict size choice could otherwise walk
  /// the entire queue rejecting everything. After
  /// [_rdSizeRejectionLimit] consecutive size-only rejections the size filter
  /// is relaxed for the rest of the session (with a snackbar) — the same
  /// degrade-don't-fail contract the other providers get per torrent.
  bool rdLinkPassesSizeRules(Map<String, dynamic> unrestrict) {
    final bytes = (unrestrict['filesize'] as num?)?.toInt() ?? 0;
    if (bytes <= 0) return true; // RD didn't report a size — don't guess.
    // Trailer/sample guard, matching Torbox/Premiumize/PikPak/AllDebrid.
    if (bytes < DebrifyTvConstants.torboxMinVideoSizeBytes) return false;
    if (_owners.session.sizeFilterRelaxed ||
        !_owners.settings.tvFilters.hasSize)
      return true;
    if (_owners.settings.tvFilters.sizeMatchesBytes(bytes)) {
      _owners.session.rdSizeRejections = 0;
      return true;
    }
    _owners.session.rdSizeRejections++;
    if (_owners.session.rdSizeRejections >=
        DebrifyTvConstants.rdSizeRejectionLimit) {
      _owners.session.sizeFilterRelaxed = true;
      _sections.feedback.showSnack(
        'Few ${_owners.settings.tvFilters.summary()} files here — playing other sizes too.',
        color: Colors.orange,
      );
      return true;
    }
    return false;
  }

  List<CachedTorrent> selectTorrentsForPlayback(
    DebrifyTvChannelCacheEntry entry,
    List<String> normalizedKeywords,
  ) {
    // Filter BEFORE the per-keyword/threshold narrowing below, so the
    // selection draws from the full matching pool rather than from a
    // pre-narrowed sample that the filter then guts.
    final all = _sections.filters._applyQualityFilterToCached(entry.torrents);
    if (all.length <= DebrifyTvConstants.playbackTorrentThreshold) {
      final list = List<CachedTorrent>.from(all);
      list.shuffle(Random());
      return list;
    }

    final selected = <CachedTorrent>[];
    final seenHashes = <String>{};

    if (normalizedKeywords.isNotEmpty) {
      for (final keyword in normalizedKeywords) {
        int count = 0;
        for (final cached in all) {
          if (!cached.keywords.contains(keyword)) continue;
          final hash = _sections.filters.normalizeInfohash(cached.infohash);
          if (hash.isEmpty || seenHashes.contains(hash)) {
            continue;
          }
          selected.add(cached);
          seenHashes.add(hash);
          count++;
          if (count >= DebrifyTvConstants.maxTorrentsPerKeywordPlayback) {
            break;
          }
        }
      }
    }

    if (selected.isEmpty) {
      return all.take(DebrifyTvConstants.playbackTorrentThreshold).toList();
    }

    if (selected.length < DebrifyTvConstants.playbackTorrentThreshold) {
      for (final cached in all) {
        final hash = _sections.filters.normalizeInfohash(cached.infohash);
        if (hash.isEmpty || seenHashes.contains(hash)) {
          continue;
        }
        selected.add(cached);
        seenHashes.add(hash);
        if (selected.length >= DebrifyTvConstants.playbackTorrentThreshold) {
          break;
        }
      }
    }

    final random = Random();
    selected.shuffle(random);
    return selected;
  }

  String normalizeInfohash(String hash) {
    return hash.trim().toLowerCase();
  }
}
