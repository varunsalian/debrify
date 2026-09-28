import 'package:flutter/widgets.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/playback_meta.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/trakt_continue_watching_item.dart';
import '../../../services/torrent_playback_service.dart'
    show TorrentPlaybackService;
import '../data/home_catalog_episode_identity.dart';
import '../data/home_catalog_origin_repository.dart';
import '../data/home_catalog_playback_resolver.dart';
import '../data/home_tracking_policy_repository.dart';
import '../models/home_catalog_origin.dart';
import '../models/home_series_resume_signals.dart';
import 'home_playback_artwork.dart';

typedef HomeCatalogResolvingLoader =
    VoidCallback Function(
      BuildContext context, {
      required PlaybackMeta meta,
      required String title,
      required VoidCallback onCancel,
    });

/// Per-action presentation orchestration. Data policies and shared artwork are
/// borrowed; each invocation owns only its loader and cancellation flag.
class HomeCatalogPlayAction {
  const HomeCatalogPlayAction({
    required this.origin,
    required this.policies,
    required this.targets,
    required this.identity,
    required this.artwork,
    this.showLoader = _showLoader,
    required this.log,
  });
  final HomeCatalogOriginRepository origin;
  final HomeTrackingPolicyRepository policies;
  final HomeCatalogPlaybackResolver targets;
  final HomeCatalogEpisodeIdentity identity;
  final HomePlaybackArtwork artwork;
  final HomeCatalogResolvingLoader showLoader;
  final void Function(String) log;

  static VoidCallback _showLoader(
    BuildContext context, {
    required PlaybackMeta meta,
    required String title,
    required VoidCallback onCancel,
  }) => TorrentPlaybackService.showResolvingOverlay(
    context,
    meta: meta,
    title: title,
    onCancel: onCancel,
  ).dismiss;

  Future<void> run(
    BuildContext context,
    StremioMeta item,
    StremioAddon addon, {
    required bool Function() isCurrent,
    required HomeResumeAvailability Function() availability,
    required TraktContinueWatchingItem? Function(StremioMeta) cachedTrakt,
    required void Function(String) showMessage,
    required void Function(String) activateAddon,
    required void Function(
      StremioMeta,
      StremioAddon, {
      required bool isTraktSource,
      required bool isMdblistSource,
    })
    openEpisodes,
    required void Function(
      AdvancedSearchSelection, {
      required String metadataAddonId,
      required StremioMeta catalogItem,
    })
    browse,
    required Future<void> Function(
      AdvancedSearchSelection, {
      required String metadataAddonId,
      required StremioMeta catalogItem,
    })
    play,
    bool isTraktSource = false,
    bool isMdblistSource = false,
    bool startFromBeginning = false,
    // Merged series page: episodes are already shown inline, so a no-IMDb
    // series must NOT fall back to pushing a standalone EpisodesScreen (that
    // would stack a duplicate episode list on top). It resolves the resume
    // episode against the raw catalog id and plays via the addon /stream path.
    bool skipEpisodeFallback = false,
    // Merged detail Resume: honour Trakt's paused position for ANY authenticated
    // title (not just Trakt-CW-sourced ones), so Play matches the Trakt-first
    // label from the Resume label. Off elsewhere (Home/row quick-play keep
    // their local-vs-Trakt-CW split untouched).
    bool preferTraktResume = false,
    // The episode the pressed button was promising, when the caller had already
    // resolved one (merged detail). It wins over the series resume resolver: that
    // reconciler only reads resume/CW positions, while the merged page's episode
    // engine also advances off watched state. A show whose progress lives in a
    // tracker's WATCHED list but not its continue-watching list reconciles to the
    // empty-candidates fallback (S01E01) while the label correctly reads S1E2 —
    // and Play would then start the pilot under a "Resume · S1E2" button.
    ({bool started, int season, int episode})? promisedTarget,
    // Primary-button hold: run the exact same target/scrobble reconciliation,
    // but hand the resulting selection to the manual Sources page instead of
    // auto-playing it. Used for series; movies already have a direct Sources
    // callback and do not need to enter this resolver.
    bool browseSourcesOnly = false,
  }) async {
    bool current() => context.mounted && isCurrent();
    if (!current()) return;
    final prepared = await origin.prepare(item, addon, isCurrent: current);
    if (!context.mounted ||
        !current() ||
        prepared.status == HomeCatalogOriginStatus.retired) {
      return;
    }
    if (prepared.status == HomeCatalogOriginStatus.unverified) {
      showMessage('Could not verify series episodes. Please retry.');
      return;
    }
    item = prepared.item;
    final originAddon = prepared.addon;
    if (originAddon == null) {
      showMessage('The addon configuration for this series is unavailable.');
      return;
    }
    addon = originAddon;
    final trackingPolicy = await policies.loadForContent(
      item.progressId,
      isCurrent: current,
    );
    if (!context.mounted || !current() || trackingPolicy == null) return;
    log(
      '[SeriesResume] play-pressed title="${item.name}" '
      'id=${item.progressId ?? item.id} type=${item.type} '
      'traktSource=$isTraktSource mdblistSource=$isMdblistSource '
      'preferTrackerResume=$preferTraktResume',
    );
    // The loader's backdrop/logo/meta line for this title. Captured here (the
    // one play entry point that still holds the catalog meta) and read back in
    // the shared metadata builder, which only ever sees a selection.
    artwork.capture(item);
    var cancelled = false;
    final resolving = preferTraktResume
        ? showLoader(
            context,
            meta: PlaybackMeta.catalog(
              imdbId: item.progressId,
              contentType: item.type,
              title: item.name,
              posterUrl: item.poster,
              year: item.year,
              addonId: addon.id,
              art: artwork.current,
            ),
            title: item.name,
            onCancel: () => cancelled = true,
          )
        : null;
    Future<void> launch(AdvancedSearchSelection selection) async {
      bool current() => context.mounted && !cancelled && isCurrent();
      if (!current()) {
        resolving?.call();
        return;
      }
      final resolved = await identity.resolve(
        selection,
        item,
        addon,
        isCurrent: current,
      );
      if (resolved == null || !current()) {
        resolving?.call();
        return;
      }
      selection = resolved;
      log(
        '[SeriesResume] ${browseSourcesOnly ? 'sources-open' : 'play-launch'} '
        'title="${selection.title}" '
        'id=${selection.imdbId} season=${selection.season} '
        'episode=${selection.episode} trakt=${selection.traktSource} '
        'traktPct=${selection.traktProgressPercent} '
        'simkl=${selection.simklSource} '
        'simklPct=${selection.simklProgressPercent} '
        'mdblist=${selection.mdblistSource} '
        'mdblistPct=${selection.mdblistProgressPercent}',
      );
      resolving?.call();
      if (!current()) return;
      if (browseSourcesOnly) {
        browse(
          selection,
          metadataAddonId: addon.id,
          catalogItem: item.withSourceAddon(addon),
        );
      } else {
        await play(
          selection,
          metadataAddonId: addon.id,
          catalogItem: item.withSourceAddon(addon),
        );
      }
    }

    try {
      // Set the active addon before any early return so a movie play carries the
      // right addon id into meta.addonId (addon-stream resume/next), instead of a
      // stale one left over from a previously-browsed series.
      activateAddon(addon.id);
      final target = await targets.resolve(
        item,
        addon,
        trackingPolicy: trackingPolicy,
        availability: availability,
        cachedTrakt: () => cachedTrakt(item),
        isCurrent: () => current() && !cancelled,
        isTraktSource: isTraktSource,
        isMdblistSource: isMdblistSource,
        startFromBeginning: startFromBeginning,
        skipEpisodeFallback: skipEpisodeFallback,
        preferTraktResume: preferTraktResume,
        promisedTarget: promisedTarget,
      );
      if (!current() || cancelled || target == null) return;
      if (target.openEpisodes) {
        openEpisodes(
          item,
          addon,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
        );
      } else {
        await launch(target.selection!);
      }
    } finally {
      resolving?.call();
    }
  }
}
