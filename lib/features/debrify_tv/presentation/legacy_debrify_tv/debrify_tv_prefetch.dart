import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_alldebrid_prepared.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DebrifyTvPrefetcher {
  final DebrifyTvDependencies _deps;
  DebrifyTvPrefetcher(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  // ===================== Prefetcher =====================

  Future<void> startPrefetch() async {
    if (_owners.prefetch.prefetchRunning ||
        _owners.prefetch.activeApiKey == null ||
        _owners.prefetch.activeApiKey!.isEmpty) {
      return;
    }

    final startEpoch = _owners.prefetch.prefetchEpoch;
    final enabled = await _owners.settings.settingsManager
        .getGlobalBackgroundPrefetchEnabled();

    // Re-check mutable state after the preference read. Multiple playback
    // paths can request a start at nearly the same time, and playback may
    // have stopped while this method was awaiting SharedPreferences.
    if (!_deps.mounted() ||
        startEpoch != _owners.prefetch.prefetchEpoch ||
        _owners.prefetch.prefetchRunning ||
        _owners.prefetch.activeApiKey == null ||
        _owners.prefetch.activeApiKey!.isEmpty) {
      return;
    }
    if (!enabled) {
      debugPrint('MagicTV: Background torrent prefetch is disabled.');
      return;
    }

    _owners.prefetch.prefetchRunning = true;
    _owners.prefetch.prefetchStopRequested = false;
    debugPrint('MagicTV: Prefetch started.');
    _owners.prefetch.prefetchTask = _sections.prefetch._runPrefetchLoop();
  }

  Future<void> stopPrefetch() async {
    _owners.prefetch.prefetchEpoch++;
    if (!_owners.prefetch.prefetchRunning) return;
    _owners.prefetch.prefetchStopRequested = true;
    try {
      await _owners.prefetch.prefetchTask;
    } catch (_) {}
    _owners.prefetch.prefetchRunning = false;
    _owners.prefetch.prefetchTask = null;
    _owners.prefetch.inflightInfohashes.clear();
    debugPrint('MagicTV: Prefetch stopped.');
  }

  Future<void> _runPrefetchLoop() async {
    while (_deps.mounted() && !_owners.prefetch.prefetchStopRequested) {
      try {
        final prepared = _sections.prefetch._countPreparedInLookahead();
        if (prepared >= DebrifyTvConstants.minPrepared) {
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        // Find first unprepared torrent within lookahead window and prefetch it
        final idx = _sections.prefetch._findUnpreparedTorrentIndexInLookahead();
        if (idx == -1) {
          // nothing to prefetch near head; small idle
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        await _sections.prefetch._prefetchOneAtIndex(idx);
        // brief yield (faster when under target prepared)
        await Future.delayed(Duration(milliseconds: prepared <= 2 ? 75 : 150));
      } catch (e) {
        debugPrint('MagicTV: Prefetch loop error: $e');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  int _countPreparedInLookahead() {
    final end =
        _owners.session.queue.length < DebrifyTvConstants.lookaheadWindow
        ? _owners.session.queue.length
        : DebrifyTvConstants.lookaheadWindow;
    int count = 0;
    for (int i = 0; i < end; i++) {
      final item = _owners.session.queue[i];
      if (item is Map &&
          (item['type'] == 'rd_restricted' || item['type'] == 'ad_locked')) {
        count++;
      }
    }
    return count;
  }

  int _findUnpreparedTorrentIndexInLookahead() {
    final end =
        _owners.session.queue.length < DebrifyTvConstants.lookaheadWindow
        ? _owners.session.queue.length
        : DebrifyTvConstants.lookaheadWindow;
    for (int i = 0; i < end; i++) {
      final item = _owners.session.queue[i];
      if (item is Torrent &&
          !_owners.prefetch.inflightInfohashes.contains(item.infohash)) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _prefetchOneAtIndex(int idx) async {
    if (_owners.prefetch.activeApiKey == null ||
        _owners.prefetch.activeApiKey!.isEmpty)
      return;
    if (idx < 0 || idx >= _owners.session.queue.length) return;
    final item = _owners.session.queue[idx];
    if (item is! Torrent) return;
    if (_owners.prefetch.activeProvider ==
        DebrifyTvConstants.providerAllDebrid) {
      await _sections.prefetch._prefetchOneAllDebrid(idx, item);
      return;
    }
    final infohash = item.infohash;
    _owners.prefetch.inflightInfohashes.add(infohash);
    debugPrint('MagicTV: Prefetching torrent at idx=$idx name="${item.name}"');
    try {
      final magnetLink = 'magnet:?xt=urn:btih:$infohash';
      final result = await DebridService.addTorrentToDebridPreferVideos(
        _owners.prefetch.activeApiKey!,
        magnetLink,
      );
      final String torrentId = result['torrentId'] as String? ?? '';
      final List<dynamic> rdLinks =
          (result['links'] as List<dynamic>? ?? const []);

      if (rdLinks.isEmpty) {
        // Nothing ready; move to tail to retry later
        if (idx < _owners.session.queue.length &&
            identical(_owners.session.queue[idx], item)) {
          _owners.session.queue.removeAt(idx);
          _owners.session.queue.add(item);
        }
        debugPrint(
          'MagicTV: Prefetch: no links; moved torrent to tail idx=$idx',
        );
        return;
      }

      // Convert this queue slot to rd_restricted using first link
      final headLinkCandidates = rdLinks
          .map((link) => link?.toString() ?? '')
          .where(
            (link) =>
                link.isNotEmpty &&
                !_owners.session.seenRestrictedLinks.contains(link),
          )
          .toList();
      if (headLinkCandidates.isEmpty) {
        if (idx < _owners.session.queue.length &&
            identical(_owners.session.queue[idx], item)) {
          _owners.session.queue.removeAt(idx);
          _owners.session.queue.add(item);
        }
        return;
      }

      headLinkCandidates.shuffle(Random());
      final headLink = headLinkCandidates.removeAt(0);
      _owners.session.seenRestrictedLinks.add(headLink);
      _owners.session.seenLinkWithTorrentId.add('$torrentId|$headLink');

      if (idx < _owners.session.queue.length &&
          identical(_owners.session.queue[idx], item)) {
        _owners.session.queue[idx] = {
          'type': 'rd_restricted',
          'restrictedLink': headLink,
          'torrentId': torrentId,
          'displayName': item.name,
        };
      }

      if (headLinkCandidates.isNotEmpty) {
        _owners.session.queue.add(item);
      }
    } catch (e) {
      // On failure, move to tail for retry later
      if (idx < _owners.session.queue.length &&
          identical(_owners.session.queue[idx], item)) {
        _owners.session.queue.removeAt(idx);
        _owners.session.queue.add(item);
      }
      debugPrint('MagicTV: Prefetch failed for $infohash: $e (moved to tail)');
    } finally {
      _owners.prefetch.inflightInfohashes.remove(infohash);
    }
  }

  /// Adds [candidate] to AllDebrid (trusting the upload `ready` flag — no
  /// polling) and returns its fresh (unseen) locked video-file links, marking
  /// them seen. Returns null when the torrent is not cached/ready (the magnet
  /// is deleted in that case) or has no usable video files. Each returned link
  /// is still locked and must be unlocked via [AllDebridService.unlockLink]
  /// before playback — the lazy model mirrors Real-Debrid's restricted links.
  Future<DebrifyTvAllDebridPrepared?> resolveAllDebridLinks(
    Torrent candidate,
    String apiKey,
  ) async {
    final magnetLink = 'magnet:?xt=urn:btih:${candidate.infohash}';
    AllDebridAddResult result;
    try {
      result = await AllDebridService.addMagnetAndResolveFiles(
        apiKey,
        magnetLink,
      );
    } on AllDebridTorrentNotReadyException catch (e) {
      // Not cached/ready — don't leave it downloading on the account.
      await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
      return null;
    }
    // AllDebrid returns a real per-file byte count, so the per-FILE size rules
    // apply before the files are reduced to bare links (after that reduction
    // the size is gone). The 50MB floor keeps trailers/samples out, matching
    // Torbox and Premiumize.
    List<String> collectLinks({required bool applySizeFilter}) {
      return result.files
          .where((f) {
            if (!FileUtils.isVideoFile(f.fileName)) return false;
            if (f.size > 0 &&
                f.size < DebrifyTvConstants.torboxMinVideoSizeBytes)
              return false;
            if (applySizeFilter &&
                !_owners.settings.tvFilters.sizeMatchesBytes(f.size)) {
              return false;
            }
            return true;
          })
          .map((f) => f.link)
          .where(
            (link) =>
                link.isNotEmpty &&
                !_owners.session.seenRestrictedLinks.contains(link),
          )
          .toList();
    }

    var freshLinks = collectLinks(applySizeFilter: true);
    if (freshLinks.isEmpty && _owners.settings.tvFilters.hasSize) {
      // Nothing matched in this torrent — take it unfiltered rather than
      // discarding the torrent (see the Torbox builder).
      debugPrint(
        'DebrifyTV/AD: no file matched the size filter in "${result.name}" — '
        'using it unfiltered.',
      );
      freshLinks = collectLinks(applySizeFilter: false);
    }
    if (freshLinks.isEmpty) return null;
    for (final link in freshLinks) {
      _owners.session.seenRestrictedLinks.add(link);
    }
    return DebrifyTvAllDebridPrepared(
      magnetId: result.magnetId,
      name: result.name,
      lockedLinks: freshLinks,
    );
  }

  /// AllDebrid analog of the Real-Debrid prefetch path. Converts the [item]
  /// queue slot into a prepared `ad_locked` entry (a still-locked link), and
  /// since AllDebrid returns every file at once, enqueues the remaining video
  /// files immediately rather than re-adding the torrent.
  Future<void> _prefetchOneAllDebrid(int idx, Torrent item) async {
    final infohash = item.infohash;
    _owners.prefetch.inflightInfohashes.add(infohash);
    debugPrint(
      'MagicTV: Prefetching AllDebrid torrent at idx=$idx name="${item.name}"',
    );
    try {
      final prepared = await _sections.prefetch.resolveAllDebridLinks(
        item,
        _owners.prefetch.activeApiKey!,
      );
      if (prepared == null || prepared.lockedLinks.isEmpty) {
        // Not ready / no usable video; move to tail to retry later.
        if (idx < _owners.session.queue.length &&
            identical(_owners.session.queue[idx], item)) {
          _owners.session.queue.removeAt(idx);
          _owners.session.queue.add(item);
        }
        debugPrint(
          'MagicTV: AllDebrid prefetch: not ready/no links; moved to tail idx=$idx',
        );
        return;
      }

      final links = List<String>.from(prepared.lockedLinks);
      final headLink = links.removeAt(0);
      Map<String, dynamic> lockedEntry(String link) => {
        'type': 'ad_locked',
        'allDebridLink': link,
        'magnetId': prepared.magnetId,
        'displayName': item.name,
      };

      if (idx < _owners.session.queue.length &&
          identical(_owners.session.queue[idx], item)) {
        _owners.session.queue[idx] = lockedEntry(headLink);
      } else {
        // Slot shifted out from under us; don't lose the resolved head link.
        _owners.session.queue.add(lockedEntry(headLink));
      }
      for (final link in links) {
        _owners.session.queue.add(lockedEntry(link));
      }
    } catch (e) {
      if (idx < _owners.session.queue.length &&
          identical(_owners.session.queue[idx], item)) {
        _owners.session.queue.removeAt(idx);
        _owners.session.queue.add(item);
      }
      debugPrint(
        'MagicTV: AllDebrid prefetch failed for $infohash: $e (moved to tail)',
      );
    } finally {
      _owners.prefetch.inflightInfohashes.remove(infohash);
    }
  }
}
