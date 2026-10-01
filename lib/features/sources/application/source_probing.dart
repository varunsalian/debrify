import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/source_acquisition.dart';
import 'package:debrify/features/sources/data/source_acquisition_cleanup.dart';
import 'package:debrify/features/sources/data/source_magnet.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:debrify/utils/torrent_curation.dart';
import 'package:flutter/foundation.dart';

final class SourceProbing {
  const SourceProbing._();

  static (Torrent?, Torrent?) selectDirect(
    List<Torrent> torrents,
    FilterLadder? ladder,
  ) {
    final tiered = ladder != null && ladder.isActive;
    int? bestPlayableTier;
    for (final t in torrents) {
      final isDirect = SourceCandidateChecks.isDirectCandidate(t);
      final isProbeable =
          t.streamType != StreamType.externalUrl &&
          SourceCandidateChecks.hasAcquisition(t);
      if (!isDirect && !isProbeable) continue;
      if (tiered) bestPlayableTier ??= ladder.tierOf(t);
      if (!isDirect) continue;
      final direct = (!tiered || ladder.tierOf(t) == bestPlayableTier)
          ? t
          : null;
      return (direct, t);
    }
    return (null, null);
  }

  /// Probe budget for one play. PikPak is ALWAYS 1 — every probe queues a
  /// real download that can't be cheaply undone — and beats every floor.
  /// Otherwise the user's try-multiple setting (clamped 1–10 so a corrupted
  /// pref can never yield 0 probes), raised to [minAttempts] (the pack-top
  /// safety's 2-attempt floor).
  @visibleForTesting
  static int probeAttemptCount(
    String prov, {
    required bool tryMultiple,
    required int maxRetries,
    int minAttempts = 1,
  }) {
    if (prov == 'pikpak') return 1;
    final base = tryMultiple ? maxRetries.clamp(1, 10) : 1;
    return base < minAttempts ? minAttempts : base;
  }

  /// Pack coverage types — the only tops the pack-top safety rescues from.
  static const Set<String> _packCoverageTypes = {
    'seasonPack',
    'multiSeasonPack',
    'completeSeries',
  };

  /// Pack-top safety (QUICK_PLAY_FILTERS_PLAN.md §3.4b.3): when the ladder
  /// promoted a genuine PACK (torrent-typed, pack coverage metadata) above
  /// every exact-episode single, guarantee the best single still gets probed.
  /// Standard providers get it at index 1 plus a 2-attempt floor; PikPak —
  /// which probes exactly ONCE and each probe queues a real, possibly
  /// whole-pack download — gets the single moved to index 0 instead, so its
  /// lone probe is never spent on a pack. Guards (round-2 review): a top
  /// without pack coverage (episode-scoped addon streams, singles whose
  /// names lack S/E tokens) is NOT treated as a pack, and a cam-floored
  /// single is never hoisted (it would defeat §3.3c). Returns the (possibly
  /// copied) list and the minimum probe attempts.
  static (List<Torrent>, int) packTopSafety(
    List<Torrent> candidates, {
    required String provider,
    required FilterLadder ladder,
    int? season,
    int? episode,
  }) {
    if (season == null || episode == null || candidates.length < 2) {
      return (candidates, 1);
    }
    final top = candidates.first;
    if (top.streamType != StreamType.torrent ||
        !_packCoverageTypes.contains(top.coverageType) ||
        nameHasExactEpisode(top.name, season, episode)) {
      return (candidates, 1);
    }
    final singleIdx = candidates.indexWhere(
      (t) =>
          nameHasExactEpisode(t.name, season, episode) &&
          ladder.tierOf(t) < ladder.tierCount, // never hoist a cam-floor single
    );
    if (singleIdx <= 0) return (candidates, 1);
    final list = List.of(candidates);
    final single = list.removeAt(singleIdx);
    if (provider == 'pikpak') {
      list.insert(0, single);
      return (list, 1);
    }
    list.insert(1, single);
    return (list, 2);
  }

  /// Probe [candidates] in order on [prov] until one resolves to an instantly
  /// playable URL — and, when [season]/[episode] are both set, actually
  /// contains that episode (a pack that resolved fine but lacks the episode is
  /// skipped and its fresh RD/PikPak entry deleted, matching _playViaBound).
  /// Honors the Quick-Play retry settings: PikPak probes only the top
  /// candidate (each probe queues a real download we can't cheaply clean up);
  /// others try one candidate, or up to the configured max when "try multiple
  /// torrents" is on. Returns the resolution and the winning torrent, or
  /// (null, null) on failure/cancel.
  static Future<(ResolvedSource?, Torrent?)> probeCandidates(
    String prov,
    List<Torrent> candidates, {
    required AutomaticSourceBindings sourceBindings,
    int? season,
    int? episode,
    QuickPlayRules? rules,
    bool Function()? isCancelled,
    // Floor on attempts (the ladder's pack-top safety). PikPak stays at 1 —
    // every probe there queues a real download that can't be cheaply undone.
    int minAttempts = 1,
    // Called as each candidate is about to be probed (ladder narration).
    void Function(Torrent t)? onCandidate,
  }) async {
    Future<(ResolvedSource?, Torrent?)> run() async {
      bool cancelled() =>
          !sourceBindings.isCurrent || (isCancelled?.call() ?? false);
      if (cancelled()) return (null, null);
      final tryMultiple =
          rules?.tryNextOnFailure ??
          await QuickPlayStorage.getQuickPlayTryMultipleTorrents();
      final maxRetries =
          rules?.maxAttempts ?? await QuickPlayStorage.getQuickPlayMaxRetries();
      final maxAttempts = probeAttemptCount(
        prov,
        tryMultiple: tryMultiple,
        maxRetries: maxRetries,
        minAttempts: minAttempts,
      );
      for (final t in candidates.take(maxAttempts)) {
        if (cancelled()) return (null, null);
        logSourceSelection(
          'quick_play_probe',
          source: t,
          season: season,
          episode: episode,
        );
        onCandidate?.call(t);
        try {
          final magnet = await sourceMagnet(t);
          if (magnet == null) {
            logSourceSelection(
              'quick_play_probe_rejected',
              source: t,
              reason: 'no_acquisition',
            );
            continue;
          }
          if (cancelled()) return (null, null);
          final r = await add(
            prov,
            magnet,
            t,
            sourceBindings: sourceBindings,
            canContinue: () => !cancelled(),
          );
          if (cancelled()) return (null, null);
          if (r.playUrl != null && r.playUrl!.isNotEmpty) {
            // For a series episode, don't accept a pack that resolved fine but
            // doesn't actually contain the requested episode (mislabeled or
            // wrong-season result) — mirror _playViaBound instead of letting the
            // player silently start the wrong/first episode. Keep probing the
            // remaining candidates for one that genuinely has it.
            if (season != null &&
                episode != null &&
                !SourceCandidateChecks.resolvedHasEpisode(r, season, episode)) {
              logSourceSelection(
                'quick_play_probe_rejected',
                source: t,
                season: season,
                episode: episode,
                reason: 'episode_not_in_pack',
              );
              // Delete the fresh RD/PikPak entry this probe created so skips
              // don't pile up orphans (TorBox/AllDebrid dedup the add; Premiumize
              // adds nothing), matching _playViaBound's cleanup.
              await cleanupWrongEpisode(
                prov,
                owner: sourceBindings.owner,
                rdTorrentId: r.rdTorrentId,
                pikpakFileId: r.pikpakFileId,
              );
              continue;
            }
            logSourceSelection(
              'quick_play_probe_resolved',
              source: t,
              season: season,
              episode: episode,
            );
            return (r, t);
          }
          logSourceSelection(
            'quick_play_probe_rejected',
            source: t,
            reason: 'no_play_url',
          );
        } on TorrentNotCachedException catch (e) {
          logSourceSelection(
            'quick_play_probe_rejected',
            source: t,
            reason: 'not_cached',
          );
          // Probed torrent is downloading — remove it so RD stays clean.
          await cleanupFailedAutomaticAcquisition(
            e,
            sourceBindings: sourceBindings,
          );
        } on AllDebridTorrentNotReadyException catch (e) {
          logSourceSelection(
            'quick_play_probe_rejected',
            source: t,
            reason: 'not_ready',
          );
          await cleanupFailedAutomaticAcquisition(
            e,
            sourceBindings: sourceBindings,
          );
        } catch (_) {
          logSourceSelection(
            'quick_play_probe_rejected',
            source: t,
            reason: 'provider_error',
          );
          // TorboxSourceNotCached / PremiumizeSourceNotCached / transient — try next.
        }
      }
      return (null, null);
    }

    final scope = sourceBindings.owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(run)
        : ProfileRuntime.withCapturedScope(scope, run);
  }

  /// Delete only the acquisition identified by the provider's not-ready error.
  /// A failed cleanup must not prevent trying another playable source.
  @visibleForTesting
  static Future<void> cleanupFailedAutomaticAcquisition(
    Object error, {
    AutomaticSourceBindings? sourceBindings,
    Future<void> Function(String, String)? deleteRealDebrid,
    Future<void> Function(String, String)? deleteAllDebrid,
  }) => cleanupRejectedSource(
    error,
    owner: sourceBindings?.owner,
    deleteRealDebrid: deleteRealDebrid,
    deleteAllDebrid: deleteAllDebrid,
  );

  // ── Per-provider add + resolve ─────────────────────────────────────────────

  static Future<ResolvedSource> add(
    String provider,
    String magnet,
    Torrent torrent, {
    bool Function()? canContinue,
    AutomaticSourceBindings? sourceBindings,
  }) async {
    final result = await const SourceAcquisition().acquire(
      provider,
      magnet,
      torrent,
      canContinue: canContinue,
      owner: sourceBindings?.owner,
    );
    final VoidCallback? open = switch (provider) {
      'debrid' => () => MainPageBridge.openDebridOptions?.call(
        result.rdFolder!,
      ),
      'torbox' =>
        result.torboxFolder == null
            ? null
            : () => MainPageBridge.openTorboxFolder?.call(result.torboxFolder!),
      'premiumize' => () => MainPageBridge.openPremiumizeFolder?.call(),
      'alldebrid' => () => MainPageBridge.openAllDebridFolder?.call(),
      'pikpak' => () => MainPageBridge.openPikPakFolder?.call(
        result.pikpakFileId!,
        result.title,
      ),
      _ => null,
    };
    return ResolvedSource(
      title: result.title,
      httpHeaders: result.httpHeaders,
      playUrl: result.playUrl,
      downloadUrls: result.downloadUrls,
      playlist: result.playlist,
      startIndex: result.startIndex,
      fileName: result.fileName,
      isRarArchive: result.isRarArchive,
      torboxTorrentId: result.torboxTorrentId,
      rdTorrentId: result.rdTorrentId,
      pikpakFileId: result.pikpakFileId,
      restrictedLink: result.restrictedLink,
      torboxFileId: result.torboxFileId,
      premiumizePath: result.premiumizePath,
      allDebridLink: result.allDebridLink,
      pikpakVideoFileId: result.pikpakVideoFileId,
      openInTab: open,
    );
  }
}
