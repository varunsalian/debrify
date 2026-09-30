import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import 'home_media_bindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/youtube_resolved_streams.dart';
import '../../../utils/tvos_device.dart';
import '../application/home_trailer_preferences_controller.dart';
import '../models/home_catalog_session.dart';
import '../models/home_trailer_preferences.dart';
import 'home_hero_preview_policy.dart';

typedef HomeHeroPreviewDeps = ({
  HomeMediaBindings Function() media,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() stageActive,
  bool Function() stageWantsAmbient,
  String Function() homeStyle,
  bool Function() hasFavoriteFocus,
  bool Function() hasLiveChannel,
  String? Function() spotlightHeroId,
});

/// Hero trailer eligibility, preferences, dwell scheduling and playback signals.
class HomeHeroPreview {
  HomeHeroPreview(this._deps, this._heroItem);
  final ValueNotifier<StremioMeta?> _heroItem;
  final HomeHeroPreviewDeps _deps;

  void startPreferences(WidgetRef ref, HomeCatalogSession homeSession) {
    heroTrailerPreferencesSubscription = ref.listenManual(
      homeTrailerPreferencesProvider(homeSession),
      (previous, next) {},
    );
    heroTrailerPreferencesController = ref.read(
      homeTrailerPreferencesProvider(homeSession).notifier,
    );
  }

  // Hero ambient trailer (Home board, TV only): once DPAD focus RESTS on a
  // card, its trailer crossfades into the hero backdrop — same living-backdrop
  // treatment (and the same HeroTrailerBackdrop machinery: single decoder,
  // route/background pausing) as the detail page. Notifier-driven so a trailer
  // arriving rebuilds only the hero's video layer, never the board.
  final ValueNotifier<YoutubeResolvedStreams?> heroTrailer =
      ValueNotifier<YoutubeResolvedStreams?>(null);

  /// True from the moment the rest-debounce commits to loading a trailer until
  /// either frames are on screen or the attempt dies (no trailer / resolve
  /// failed / hero moved on) — drives the hero's little "Trailer" pill.
  final ValueNotifier<bool> heroTrailerLoading = ValueNotifier<bool>(false);

  /// True while trailer frames are actually on screen. The spotlight fades its
  /// static backdrop image out on this signal (the video plays in the board
  /// layer BENEATH the spotlight, so the image must yield to reveal it — the
  /// crossfade the video's own opacity used to provide when it sat on top).
  final ValueNotifier<bool> heroTrailerShowing = ValueNotifier<bool>(false);

  /// Takeover progress (0 ambient → 1 full-board), published by
  /// [HomeHeroTrailerLayer] as its promote animation runs. The board content and
  /// the sidebar rail fade fully OUT on it while the compact info overlay
  /// fades in — the film takes the room.
  final ValueNotifier<double> heroTrailerTakeover = ValueNotifier<double>(0);

  final HomeHeroPreviewPolicy heroPreviewPolicy = HomeHeroPreviewPolicy();

  /// Accepted trailer settings, refreshed on settings and sync notifications.
  late final HomeTrailerPreferencesController heroTrailerPreferencesController;
  late final ProviderSubscription<HomeTrailerPreferences>
  heroTrailerPreferencesSubscription;
  bool get heroTrailerEnabled =>
      heroTrailerPreferencesController.current.enabled;

  /// Effective ambient volume (0–100); zero while the sound toggle is off.
  double get heroTrailerVolume =>
      heroTrailerPreferencesController.current.volume;

  /// Trailers only on the TV Home board's full spotlight — never the Search
  /// tab's compact strip (too small, and results should dominate) or off-TV
  /// (the hero itself isn't rendered there). Low-memory Apple TV generations
  /// are excluded outright: an mpv trailer engine alongside the board's
  /// artwork is exactly the load that jetsam-kills a 3 GB first-gen 4K, and
  /// the probe is warmed pre-runApp so this getter stays constant for the
  /// State's lifetime (the init/dispose registrations must agree).
  bool get heroTrailerActive =>
      _deps.isTelevision() &&
      !_deps.searchMode() &&
      !_deps.discoverMode() &&
      !TvosDevice.isLowMemoryCached;

  /// The hero trailer off-TV: the Spotlight home board's reel, rendered on
  /// phones/tablets/desktop. Deliberately SEPARATE from [heroTrailerActive]
  /// — that getter is the whole TV shell lifecycle (glass scaffold, sidebar
  /// relays, hardware-key takeover, ambient publish), none of which belongs
  /// on a phone. This one means exactly "this instance may resolve and paint
  /// a hero trailer"; the enabled pref (platform-defaulted: TV/desktop on,
  /// phone/tablet off) gates it at schedule time.
  bool get heroTrailerOffTvEligible =>
      !_deps.isTelevision() && !_deps.searchMode() && !_deps.discoverMode();

  /// May THIS instance resolve/render a hero trailer at all.
  bool get heroTrailerRenderable =>
      heroTrailerActive || heroTrailerOffTvEligible;

  Future<void> reloadHeroTrailerPrefs({
    bool initial = false,
    bool Function()? isCurrent,
  }) => heroTrailerPreferencesController.load(
    useHomeAudio: _deps.isTelevision(),
    isCurrent: () => _deps.mounted() && (isCurrent?.call() ?? true),
    onAccepted: (preferences) {
      _deps.setState(() {});
      if (initial) {
        if (!preferences.enabled) return;
        // The board usually seeds the hero before this read lands.
        final current = _heroItem.value;
        if (current != null) scheduleHeroTrailer(current);
      } else if (!preferences.enabled) {
        clearHeroTrailer();
      }
    },
  );

  /// Debounced ambient-trailer load for the spotlighted title. The previous
  /// trailer is torn down IMMEDIATELY on any hero change (a playing trailer
  /// under the wrong title is worse than the static backdrop), then a new one
  /// only starts once focus has RESTED on the card — flying across a row costs
  /// nothing but a timer reset, never a resolve or a decoder spin-up. Both
  /// lookups (Cinemeta /meta for the YouTube id, then the stream resolve) are
  /// cached in their services, so re-resting on a recent card starts fast.
  void scheduleHeroTrailer(StremioMeta item, {bool fromSpotlight = false}) {
    // Search previews belong to the focused result card, never a hidden hero.
    if (_deps.isTelevision() && _deps.searchMode()) return;
    if (item.type == 'folder') return;
    if (!heroPreviewPolicy.admitSchedule(
      item.id,
      fromSpotlight: fromSpotlight,
      renderableAndEnabled: () => heroTrailerRenderable && heroTrailerEnabled,
    )) {
      return;
    }
    // Spotlight owns its own hero cadence, so the shared scheduler must not
    // also drive it — two systems interleaving on one hero is how a trailer
    // starts under the wrong title.
    //
    // The guard lives HERE rather than at the call sites: scheduling reaches
    // this method from init, section loads, focus changes, `_heroSection.applyHero`,
    // route return and sidebar return, and a per-site exclusion would miss
    // one. `heroTrailerActive` is deliberately left style-blind — it governs
    // listener registration across an asynchronously loaded style, and gating
    // it leaks or double-registers listeners.
    if (_deps.homeStyle() == 'spotlight' && !fromSpotlight) return;
    // A layout with no place to put moving picture (Mosaic) never resolves a
    // trailer at all — the resolve is a network + engine cost for something
    // that would be invisible under its veil.
    if (_deps.stageActive() && !_deps.stageWantsAmbient()) return;
    // A Canvas favourite owns the stage (or its live feed does): a catalog
    // trailer must never start beneath it. The next catalog/CW focus goes
    // through _heroSection.setHero, which clears both and reschedules. Safe to skip the
    // reset lines below: every fav-focus path already ran clearHeroTrailer.
    if (_deps.hasFavoriteFocus() || _deps.hasLiveChannel()) {
      return;
    }
    if (!fromSpotlight && heroPreviewPolicy.hasAttempted(item.id)) return;
    // Spotlight already owns the stage; other layouts wait for focus to rest.
    _deps.media().trailer.schedule(
      item,
      delay: fromSpotlight ? Duration.zero : const Duration(seconds: 2),
      isCurrent: () => _deps.mounted(),
      reset: () {
        if (heroTrailer.value != null) heroTrailer.value = null;
        if (heroTrailerLoading.value) heroTrailerLoading.value = false;
        if (heroTrailerShowing.value) heroTrailerShowing.value = false;
      },
      begin: () {
        heroPreviewPolicy.recordAttempt(item.id);
        // The layout may have changed during the dwell — a stage with nowhere
        // to put moving picture must not spin up an engine.
        if (_deps.stageActive() && !_deps.stageWantsAmbient()) return false;
        // Covered by ANY modal (bottom sheet, dialog — which never reach the
        // PageRoute-only route observer) or a pushed page: a trailer must not
        // start under it. The cover's dismissal path re-arms where relevant
        // (didPopNext for pages); sheets simply wait for the next hero rest.
        if (ModalRoute.of(_deps.context())?.isCurrent != true) return false;
        // From here the attempt is committed — surface the pill. Every exit
        // below (no trailer, failed resolve, hero moved on) clears it; success
        // keeps it up until the backdrop reports frames (onHeroTrailerPlaying).
        heroTrailerLoading.value = true;
        return true;
      },
      publish: (streams) => heroTrailer.value = streams,
      fail: () => heroTrailerLoading.value = false,
    );
  }

  /// The hero backdrop's playing signal: frames on screen (true) or engine
  /// teardown/error (false). Ends the loading pill either way, and drives the
  /// spotlight's image-yield crossfade.
  void onHeroTrailerPlaying(bool playing) {
    if (heroTrailerLoading.value) heroTrailerLoading.value = false;
    if (heroTrailerShowing.value != playing) {
      heroTrailerShowing.value = playing;
    }
  }

  /// Kill any pending/playing hero trailer (hero cleared, board reloading).
  void clearHeroTrailer() {
    _deps.media().trailer.cancel();
    if (heroTrailer.value != null) heroTrailer.value = null;
    if (heroTrailerLoading.value) heroTrailerLoading.value = false;
    if (heroTrailerShowing.value) heroTrailerShowing.value = false;
  }

  /// Content playback launched (see the listener registration in
  /// [initState]): kill the trailer NOW (native activity launches never push
  /// a Flutter route, so RouteAware alone can't catch them all) and keep it
  /// off for this spotlight — it must not resume behind or after the feature.
  void onContentPlayerLaunch() {
    if (!heroTrailerRenderable || !_deps.mounted()) return;
    heroPreviewPolicy.suppressForPlayback(_deps.spotlightHeroId);
    clearHeroTrailer();
  }

  /// Any key while the takeover owns the screen restores the board — the UI
  /// is at opacity 0, so this can't be left to hero-change detection alone
  /// (fav-row tiles and same-title cards never change the hero). Observe-only
  /// (always returns false): the key still does its normal job, so SELECT
  /// both restores the board and opens the showcased title.
  bool onTakeoverKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (heroTrailerTakeover.value <= 0.02) return false;
    clearHeroTrailer();
    return false;
  }

  /// Sidebar focus enter/exit (see the listener registration in [initState]).
  void onTvSidebarFocusChanged(bool focused) {
    if (!heroTrailerActive || !heroTrailerEnabled || !_deps.mounted()) return;
    if (focused) {
      clearHeroTrailer();
    } else {
      final item = _heroItem.value;
      if (item != null) scheduleHeroTrailer(item);
    }
  }
}
