import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/dominant_color.dart';
import '../utils/platform_util.dart';
import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../models/playlist_view_mode.dart';
import '../services/analytics_service.dart';
import '../services/app_route_observer.dart';
import '../services/debrify_image_cache.dart';
import '../services/imdb_enrichment_service.dart';
import '../services/imdb_parents_guide_service.dart';
import '../services/storage_service.dart';
import '../services/video_player_launcher.dart';
import '../services/youtube_service.dart';
import '../widgets/hero_trailer_backdrop.dart';
import '../widgets/episodes_panel.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/parents_guide_section.dart';
import '../services/trakt/trakt_service.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import 'episodes_screen.dart' show kCatalogDetailRouteName;

/// Merged series page (experimental, flag-gated): the detail screen and the
/// episode drill-down fused into one Stremio-styled screen. Reached only from
/// the Search tab, only for series, only when
/// `StorageService.getMergedSeriesPageEnabled()` is on. Movies and the flag-off
/// path keep the existing `CatalogItemDetailScreen` → `EpisodesScreen` flow.
///
/// The episode list + playback selection is delegated to [EpisodesPanel] (the
/// proven engine, hosted chromeless), so no playback behavior is re-implemented
/// here. This screen owns only presentation + the same detail-metadata loads
/// the detail screen performs (IMDb enrichment, parents guide, recommendations).
class MergedDetailScreen extends StatefulWidget {
  final StremioMeta item;
  final StremioAddon addon;
  final bool isTelevision;
  final bool showQuickPlay;
  final bool isTraktSource;

  /// Primary play action. Series: resume-and-play (last-played → S01E01).
  /// Movie: play the movie. Mirrors the detail screen's "Play".
  final VoidCallback onResume;

  /// Resolves whether the title has prior progress and, for a series, the
  /// season/episode [onResume] would land on — so the button can read
  /// "Start Watching" vs "Resume · S3E4". Null keeps the static label.
  final Future<({bool started, int? season, int? episode})> Function()?
  resumeInfoLoader;

  /// Movie only: open the Sources list (manual pick). Ignored for series (the
  /// episode list is the picker). When null the Sources button is hidden.
  final VoidCallback? onBrowse;

  /// Episode terminal callbacks — the exact ones the Search tab passes to
  /// `EpisodesScreen` today (`_playSelection` / `_browseSelection`).
  final void Function(AdvancedSearchSelection selection)? onItemSelected;
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;

  /// Host-owned source binding.
  final int Function(StremioMeta show)? boundSourceCount;
  final Future<void> Function(StremioMeta show)? onSelectSource;

  /// Quick-action strip (Trakt / app actions). [traktMenuOptions] is the
  /// initial (status-unknown) set shown until [traktStatusLoader] resolves;
  /// [traktMenuBuilder], when provided, rebuilds the strip against the live
  /// Trakt status so Add ↔ Remove toggles reflect the user's real library.
  final List<TraktMenuOption> traktMenuOptions;
  final List<TraktMenuOption> Function(TraktTitleStatus? status)?
  traktMenuBuilder;
  final Future<void> Function(TraktItemMenuAction action)? onTraktAction;

  /// Resolves the user's Trakt relationship to this title (in watchlist /
  /// collection / watched / rating) so the page can badge it and offer the
  /// right toggles. Null (disconnected / no IMDb id) keeps the add-only menu.
  final Future<TraktTitleStatus?> Function()? traktStatusLoader;

  /// "More Like This" rail + sparse-item meta backfill (same loaders the detail
  /// screen receives).
  final Future<List<StremioMeta>> Function()? recommendationsLoader;
  final void Function(StremioMeta recommendation)? onRecommendationTap;
  final Future<StremioMeta?> Function(String imdbId, String type)? metaEnricher;

  /// Shared-element tag from the board cell that opened this page: the tapped
  /// poster flies into (and back out of) this page's full-bleed backdrop.
  final String? heroTag;

  /// For a series opened at a specific episode (e.g. from the Trakt Calendar):
  /// the episodes panel lands on and scrolls to this season/episode instead of
  /// its usual next-up/last-played target. Ignored for movies.
  final int? initialSeason;
  final int? initialEpisode;

  const MergedDetailScreen({
    super.key,
    required this.item,
    required this.addon,
    required this.onResume,
    this.initialSeason,
    this.initialEpisode,
    this.resumeInfoLoader,
    this.onBrowse,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.isTraktSource = false,
    this.onItemSelected,
    this.onQuickPlay,
    this.boundSourceCount,
    this.onSelectSource,
    this.traktMenuOptions = const [],
    this.traktMenuBuilder,
    this.onTraktAction,
    this.traktStatusLoader,
    this.recommendationsLoader,
    this.onRecommendationTap,
    this.metaEnricher,
    this.heroTag,
  });

  @override
  State<MergedDetailScreen> createState() => _MergedDetailScreenState();
}

class _MergedDetailScreenState extends State<MergedDetailScreen>
    with RouteAware {
  // ── Stremio-flat palette (neutral glass + gold state) ──
  static const Color _bg = Color(0xFF0B0B0E);
  static const Color _gold = Color(0xFFF5B942);
  static const Color _imdb = Color(0xFFF5C518);
  static Color get _glass2 => Colors.white.withValues(alpha: 0.07);
  static Color get _hair => Colors.white.withValues(alpha: 0.09);

  /// Per-title accent, extracted once from the poster (same cheap 32px decode
  /// the home hero uses). Colors the eyebrow, an ambient wash behind the title
  /// and the Play button's glow, so the page feels made for *this* title rather
  /// than a template with the artwork swapped in. Falls back to [_gold] until a
  /// colorful dominant color is found (or forever, for a B&W poster).
  Color _accent = _gold;

  ImdbEnrichment? _imdbExtra;
  ParentsGuideResult? _parentsGuide;
  List<StremioMeta>? _recommendations;
  StremioMeta? _enriched;

  /// Trailer YouTube ID, resolved from Cinemeta meta. Null until loaded / when
  /// the title has no trailer — the Trailer button only shows once this is set.
  String? _trailerYtId;

  /// Guards against a double-launch while a trailer's streams resolve.
  bool _trailerLoading = false;

  /// Whether OTT-style trailer autoplay behind the backdrop is on (settings).
  /// Always false on Android TV — the Home hero owns ambient trailers there.
  bool _trailerAutoplayEnabled = false;

  /// Ambient loop volume (0–100) from settings; 0 when the sound toggle is off.
  /// Read alongside [_trailerAutoplayEnabled] and applied when the backdrop
  /// opens its engine (which can't happen before the streams resolve), so it's
  /// always in place by then. Promoting to fullscreen still plays at full
  /// volume — the backdrop handles that, muted ambient or not.
  double _trailerAmbientVolume = 70;

  /// Resolved trailer streams, pre-fetched for the ambient backdrop.
  YoutubeResolvedStreams? _trailerStreams;

  /// Handle to the backdrop so the Trailer button can promote the *same* player
  /// to fullscreen in place (seamless — no second decoder, no re-buffer).
  final GlobalKey<HeroTrailerBackdropState> _backdropKey = GlobalKey();

  /// Whether the trailer is currently brought forward to fullscreen.
  bool _trailerForeground = false;

  /// The ambient backdrop trailer is live with frames on screen — the Trailer
  /// button reads "Watch Trailer" to say "it's playing, tap to view".
  bool _trailerAmbientPlaying = false;

  /// Autoplay pipeline in flight (stream resolve → buffer → first frame) — the
  /// Trailer button shows a spinner.
  bool _trailerResolving = false;

  /// Scrolls the left info column. Focus-anchored (see [_ScrollAnchor]) so that
  /// focusing the top action row snaps to the very top (revealing the
  /// title/meta/summary above it), and focusing a lower section brings it fully
  /// into view — fixing the "can't scroll back up to the details" DPAD bug.
  final ScrollController _infoScroll = ScrollController();

  /// The stable LEFT-crossing target for episodes: the info column's primary
  /// action (Play/Resume, or the source pill when Play is hidden). Pressing LEFT
  /// on an episode focuses this instead of a geometry-picked mid-column item.
  final FocusNode _leftEntryFocusNode = FocusNode(
    debugLabel: 'merged-left-entry',
  );

  /// Pane containment (two-pane layout). Each pane lives in its own
  /// [FocusScope]: directional traversal only considers candidates inside the
  /// focused node's nearest scope, so Up/Down can never geometry-jump across
  /// the pane border (DOWN on the last episode used to land on a cast tile in
  /// the info column). Crossing is explicit and horizontal only: LEFT from the
  /// episodes pane → [_leftEntryFocusNode]; RIGHT from the info pane →
  /// [_focusEpisodesPane] (the pane's last-focused row, remembered by its
  /// scope).
  final FocusScopeNode _infoPaneScope = FocusScopeNode(
    debugLabel: 'merged-info-pane',
  );
  final FocusScopeNode _episodesPaneScope = FocusScopeNode(
    debugLabel: 'merged-episodes-pane',
  );

  /// The floating back button — the info pane hands focus here when UP is
  /// pressed at its top (it sits outside the pane scopes, so contained
  /// traversal alone could never reach it).
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'merged-back');

  /// Reaches the hosted panel so [didPopNext] can refresh its watched
  /// ticks/progress after inline playback (episode quick-play, hero Resume)
  /// pops back onto this screen. Single key is safe: only one layout (two-pane
  /// or stacked) builds the panel at a time.
  final GlobalKey<EpisodesPanelState> _episodesPanelKey =
      GlobalKey<EpisodesPanelState>();

  StremioMeta get _item => _enriched ?? widget.item;

  /// Primary-button resume state. Until loaded the button keeps its static
  /// label; once resolved it reads "Start Watching" (no progress) or "Resume"
  /// (+ an "S3E4" tag for series). Re-read when the player pops back.
  bool _resumeLoaded = false;
  bool _resumeStarted = false;
  int? _resumeSeason;
  int? _resumeEpisode;

  /// The user's live Trakt relationship to this title (watchlist / collection /
  /// watched / rating). Null until [traktStatusLoader] resolves — the menu then
  /// falls back to the add-only [traktMenuOptions]. Re-read after a quick action
  /// and when the player pops back.
  TraktTitleStatus? _traktStatus;

  /// The quick-actions strip to render: rebuilt against [_traktStatus] when a
  /// builder was supplied, else the static list passed in.
  List<TraktMenuOption> get _menuOptions =>
      widget.traktMenuBuilder?.call(_traktStatus) ?? widget.traktMenuOptions;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('series_detail');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadEnrichedMeta();
      _loadImdbEnrichment();
      _loadParentsGuide();
      _loadRecommendations();
      _loadTrailer();
      _loadAccent();
      _loadResumeInfo();
      _loadTraktStatus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  /// Playback (Resume, or an inline episode) pushes the player on top of this
  /// screen, so it pops BACK here when playback ends — refresh the label then.
  @override
  void didPopNext() {
    _loadResumeInfo();
    // Watched state (and thus the resume label / badges) may have changed while
    // away — re-read the Trakt status too.
    _loadTraktStatus();
    // And the episode list's ticks/progress: episode quick-play now plays on
    // top of this screen (like Resume), so the list is still alive when the
    // player pops back and must reflect the session that just ended.
    _episodesPanelKey.currentState?.refreshWatchProgress();
  }

  /// Resolve the user's Trakt relationship to this title so the menu shows
  /// Add ↔ Remove toggles and the hero can badge Watchlist/Collection/Watched/
  /// rating. Silent on failure — the menu just stays add-only.
  Future<void> _loadTraktStatus() async {
    final loader = widget.traktStatusLoader;
    if (loader == null) return;
    try {
      final status = await loader();
      if (!mounted || status == null) return;
      setState(() => _traktStatus = status);
    } catch (_) {}
  }

  Future<void> _loadResumeInfo() async {
    final loader = widget.resumeInfoLoader;
    if (loader == null) return;
    try {
      final info = await loader();
      if (!mounted) return;
      setState(() {
        _resumeLoaded = true;
        _resumeStarted = info.started;
        _resumeSeason = info.season;
        _resumeEpisode = info.episode;
      });
    } catch (_) {
      // Non-critical — leave the static label.
    }
  }

  /// The primary-button label: "Start Watching" before any progress, otherwise
  /// "Resume" with an OTT-style "· S3E4" tag for series. Falls back to the
  /// static Play/Resume label until the resume state resolves.
  String get _primaryLabel {
    if (!_resumeLoaded) return _isMovie ? 'Play' : 'Resume';
    if (!_resumeStarted) return _isMovie ? 'Play' : 'Start Watching';
    if (_isMovie || _resumeSeason == null || _resumeEpisode == null) {
      return 'Resume';
    }
    return 'Resume · S${_resumeSeason}E$_resumeEpisode';
  }

  /// Pull a per-title accent from the poster (preferred — posters are more
  /// brand-saturated than backdrops). One tiny 32px decode; silent on failure,
  /// leaving the gold fallback. Extracted from the initial artwork only — a
  /// later enrichment swap isn't worth a second pass.
  Future<void> _loadAccent() async {
    final url = widget.item.poster ?? widget.item.background;
    if (url == null || url.isEmpty) return;
    try {
      final c = await extractDominantColor(CachedNetworkImageProvider(url));
      if (c != null && mounted) setState(() => _accent = c);
    } catch (_) {}
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _infoScroll.dispose();
    _leftEntryFocusNode.dispose();
    _infoPaneScope.dispose();
    _episodesPaneScope.dispose();
    _backButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadEnrichedMeta() async {
    final enrich = widget.metaEnricher;
    final item = widget.item;
    final imdbId = item.effectiveImdbId;
    if (enrich == null || imdbId == null) return;
    final alreadyRich =
        (item.year != null && item.year!.isNotEmpty) ||
        item.imdbRating != null ||
        (item.genres?.isNotEmpty ?? false);
    if (alreadyRich) return;
    try {
      final full = await enrich(imdbId, item.type);
      if (full == null || !mounted) return;
      setState(() {
        _enriched = StremioMeta(
          id: item.id,
          imdbId: item.imdbId,
          type: item.type,
          name: full.name.isNotEmpty ? full.name : item.name,
          poster: full.poster ?? item.poster,
          background: full.background ?? item.background,
          description: (full.description?.isNotEmpty ?? false)
              ? full.description
              : item.description,
          year: full.year ?? item.year,
          imdbRating: full.imdbRating ?? item.imdbRating,
          genres: (full.genres?.isNotEmpty ?? false)
              ? full.genres
              : item.genres,
          sourceAddon: item.sourceAddon,
          trailerYtId: full.trailerYtId ?? item.trailerYtId,
        );
      });
    } catch (_) {}
  }

  /// Resolve the trailer's YouTube ID from Cinemeta. Runs independently of
  /// [_loadEnrichedMeta] (which short-circuits for already-rich items and so
  /// can't be relied on to carry the trailer). The `fetchMetaDetails` result is
  /// cached in [StremioService], so this shares that fetch rather than doubling
  /// network. Silent on failure — the button simply never appears.
  Future<void> _loadTrailer() async {
    // Resolve the trailer id: prefer what the item arrived with, else ask the
    // metadata addon (Cinemeta).
    String? ytId = widget.item.trailerYtId;
    if (ytId == null || ytId.isEmpty) {
      final enrich = widget.metaEnricher;
      final imdbId = widget.item.effectiveImdbId;
      if (enrich != null && imdbId != null) {
        try {
          final full = await enrich(imdbId, widget.item.type);
          ytId = full?.trailerYtId;
        } catch (_) {}
      }
    }
    if (ytId == null || ytId.isEmpty || !mounted) return;
    setState(() => _trailerYtId = ytId);

    // OTT autoplay: honour the setting, then pre-resolve the stream (also reused
    // by the Trailer button). Silent on failure — the poster simply stays.
    final autoplay = await StorageService.getDetailTrailerAutoplayEnabled();
    // The ambient sound pair is shared with the TV hero (one live surface per
    // platform), so off-TV it governs this backdrop. Read unconditionally so
    // all three land in the one setState below — [autoplay] is false on TV
    // anyway, and these are two prefs reads.
    final soundOn = await StorageService.getAmbientTrailerAudioEnabled();
    final volume = await StorageService.getAmbientTrailerVolume();
    if (!mounted) return;
    // The backdrop refuses to autoplay under OS reduced-motion — skip the whole
    // pipeline (no resolve, no spinner) rather than spin forever waiting for a
    // player that will never start.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final willAutoplay = autoplay && !reduceMotion;
    setState(() {
      _trailerAutoplayEnabled = autoplay;
      _trailerAmbientVolume = soundOn ? volume.toDouble() : 0;
      // Spinner from here until the backdrop reports first frames (or fails).
      _trailerResolving = willAutoplay;
    });
    if (!willAutoplay) return;
    YoutubeResolvedStreams? streams;
    try {
      streams = await YoutubeService.resolveStreams(ytId);
    } catch (_) {
      streams = null;
    }
    if (!mounted) return;
    final playable = streams?.playUrl?.isNotEmpty ?? false;
    setState(() {
      _trailerStreams = streams;
      // No playable stream → the backdrop never starts, so stop the spinner
      // here; on success the backdrop's onPlayingChanged(true) clears it once
      // frames actually flow.
      if (!playable) _trailerResolving = false;
    });
    if (!playable) return;
    // Safety net: a stream that opens but never renders a first frame would
    // otherwise leave the spinner up forever.
    Future.delayed(const Duration(seconds: 25), () {
      if (mounted && _trailerResolving) {
        setState(() => _trailerResolving = false);
      }
    });
  }

  void _exitTrailerForeground() {
    if (!_trailerForeground) return;
    setState(() => _trailerForeground = false);
    // TV: the page content was focus-excluded while the trailer was fullscreen,
    // so nothing holds focus now — re-anchor the remote on the primary action.
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The left-entry node only has a holder when Play or the source pill is
        // present; if neither is (edge config), fall back to traversal so the
        // remote isn't stranded rather than no-op on an unattached node.
        if (_leftEntryFocusNode.context != null) {
          _leftEntryFocusNode.requestFocus();
        } else {
          FocusScope.of(context).nextFocus();
        }
      });
    }
  }

  /// Trailer button. Seamless path: if the ambient backdrop trailer is already
  /// playing, bring that *same* player forward (unmute + controls) in place — no
  /// second decoder, no re-buffer. Fallback path (autoplay off / not resolved /
  /// reduced motion): resolve fresh and launch the standalone player as before.
  Future<void> _playTrailer() async {
    if (_backdropKey.currentState?.canPromote ?? false) {
      setState(() => _trailerForeground = true);
      return;
    }

    final ytId = _trailerYtId;
    if (ytId == null || _trailerLoading) return;

    // Always resolve fresh on tap. The autoplay-prefetched [_trailerStreams] is
    // deliberately NOT reused here: googlevideo URLs carry an `expire` param and
    // go dead after a few hours, so a page left open would hand the player a
    // stale URL. Re-resolving costs one request and keeps playback reliable.
    setState(() => _trailerLoading = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading trailer…'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }

    YoutubeResolvedStreams? streams;
    try {
      streams = await YoutubeService.resolveStreams(ytId);
    } catch (_) {
      streams = null;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _trailerLoading = false);

    final playUrl = streams?.playUrl;
    if (playUrl == null || playUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Couldn\'t load trailer')));
      return;
    }

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: playUrl,
        audioUrl: streams?.audioUrl,
        fallbackUrl: streams?.downloadUrl,
        title: '${_item.name} — Trailer',
        viewMode: PlaylistViewMode.sorted,
      ),
      // Watching the trailer must not suppress the ambient trailer backdrop.
      isTrailer: true,
    );
  }

  Future<void> _loadImdbEnrichment() async {
    final imdbId = _item.effectiveImdbId;
    if (imdbId == null) return;
    try {
      final extra = await ImdbEnrichmentService.fetch(imdbId);
      if (mounted) setState(() => _imdbExtra = extra);
    } catch (_) {}
  }

  Future<void> _loadParentsGuide() async {
    final imdbId = _item.effectiveImdbId;
    if (imdbId == null) return;
    try {
      final guide = await ImdbParentsGuideService.fetch(imdbId);
      if (mounted) setState(() => _parentsGuide = guide);
    } catch (_) {}
  }

  Future<void> _loadRecommendations() async {
    final loader = widget.recommendationsLoader;
    if (loader == null) return;
    try {
      final recs = await loader();
      if (mounted) setState(() => _recommendations = recs);
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Two-pane (compact info left | full-height episodes right) on TV + desktop
  /// — episodes get the whole column height, which is the point. Android TV is
  /// only ~540 logical px tall, so a full-width hero would swallow the screen;
  /// the left pane keeps info compact and scrollable instead. Mobile stacks.
  bool get _wide =>
      widget.isTelevision || MediaQuery.of(context).size.width >= 900;

  /// Compact-height screens (TV ~540 logical px): shrink type + spacing.
  bool get _tight => MediaQuery.of(context).size.height < 640;

  bool get _isMovie => _item.type == 'movie';

  @override
  Widget build(BuildContext context) {
    final backdropUrl = _item.background ?? _item.poster;
    return PopScope(
      // While the trailer is fullscreen, Back closes it instead of leaving the
      // page — the same player stays alive and settles back into the backdrop.
      canPop: !_trailerForeground,
      onPopInvoked: (didPop) {
        if (!didPop) _exitTrailerForeground();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // Full-bleed backdrop → the Stremio "one lit surface" feel. When a
            // trailer is available and autoplay is on, it crossfades from this
            // static poster into a looping preview (OTT-style), and the
            // Trailer button promotes this same player to fullscreen in place.
            // Non-focusable and behind all content, so DPAD is unaffected.
            Positioned.fill(
              child: HeroTrailerBackdrop(
                key: _backdropKey,
                heroTag: widget.heroTag,
                imageUrl: backdropUrl,
                // Weak-TV GPU: sigma 0 swaps the runtime gaussian for a tiny
                // decode upscaled by cover-fit (visually equivalent under the
                // dark tint, zero per-frame filter cost), and drops the
                // per-frame blur pass over the ambient trailer video.
                imageBlurSigma: widget.isTelevision ? 0 : 42,
                videoBlurSigma: widget.isTelevision ? 0 : 8,
                videoUrl: _trailerAutoplayEnabled
                    ? _trailerStreams?.playUrl
                    : null,
                audioUrl: _trailerAutoplayEnabled
                    ? _trailerStreams?.audioUrl
                    : null,
                enabled: _trailerAutoplayEnabled,
                ambientVolume: _trailerAmbientVolume,
                foreground: _trailerForeground,
                onRequestClose: _exitTrailerForeground,
                onPlayingChanged: (playing) {
                  if (!mounted) return;
                  setState(() {
                    _trailerAmbientPlaying = playing;
                    _trailerResolving = false;
                  });
                },
              ),
            ),
            // Page content (tint + panes + back button). Fades out and stops
            // taking input while the trailer is foregrounded, revealing the
            // now-fullscreen, unblurred trailer beneath. ExcludeFocus matters
            // on TV: IgnorePointer only blocks pointers — without it, DPAD OK
            // would still activate the invisible Play/episode tiles under the
            // fullscreen trailer.
            Positioned.fill(
              child: ExcludeFocus(
                excluding: _trailerForeground,
                child: IgnorePointer(
                  ignoring: _trailerForeground,
                  child: AnimatedOpacity(
                    opacity: _trailerForeground ? 0 : 1,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOut,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Darker tint so even a bright poster reads as a dark surface.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _bg.withValues(alpha: 0.60),
                                _bg.withValues(alpha: 0.88),
                              ],
                            ),
                          ),
                        ),
                        // Ambient per-title color grade: a soft glow of the
                        // extracted accent in the upper-left, under the content,
                        // so the whole surface is subtly lit by the title's own
                        // color. Animates in when the accent resolves (no pop).
                        // A radial gradient fill is a single cheap paint — no
                        // blur, no layer — so it's safe on the weak TV GPU.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: TweenAnimationBuilder<Color?>(
                              duration: const Duration(milliseconds: 500),
                              tween: ColorTween(
                                end: _accent.withValues(alpha: 0.16),
                              ),
                              builder: (_, color, __) => DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: const Alignment(-0.7, -0.85),
                                    radius: 1.5,
                                    colors: [
                                      color ?? Colors.transparent,
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.7],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          child: _isMovie
                              // A movie has no episode list — one centered,
                              // scrollable Stremio detail column.
                              ? Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 720,
                                    ),
                                    child: _buildInfoPane(),
                                  ),
                                )
                              : (_wide
                                    ? _buildTwoPane(backdropUrl)
                                    : Column(
                                        children: [
                                          _buildHero(),
                                          Expanded(child: _buildStackedBody()),
                                        ],
                                      )),
                        ),
                        // Back button.
                        Positioned(
                          top: 0,
                          left: 0,
                          child: SafeArea(
                            child: Padding(
                              padding: EdgeInsets.all(
                                widget.isTelevision ? 20 : 8,
                              ),
                              child: _circleButton(
                                Icons.arrow_back_rounded,
                                () => Navigator.of(context).maybePop(),
                                tooltip: 'Back',
                                focusNode: _backButtonFocusNode,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Small "trailer playing in background" hint — only while the
            // ambient trailer is actually playing and not promoted. Tapping it
            // brings the trailer forward (same as the Trailer button).
            if (_trailerAmbientPlaying && !_trailerForeground)
              Positioned(
                left: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(widget.isTelevision ? 20 : 12),
                    child: _TrailerPlayingChip(onTap: _playTrailer),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// TV + desktop: left info column (scrollable) + right episode column (full
  /// height). Each pane is its own [FocusScope] so vertical traversal is
  /// contained within it; panes are crossed only horizontally — LEFT from an
  /// episode to the info column's primary action, RIGHT from the info column
  /// back to the pane's remembered episode row.
  Widget _buildTwoPane(String? backdropUrl) {
    final w = MediaQuery.of(context).size.width;
    final leftW = (w * 0.42).clamp(320.0, 480.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left info column, darkened so text stays legible over any backdrop.
        SizedBox(
          width: leftW,
          child: FocusScope(
            node: _infoPaneScope,
            onKeyEvent: _handleInfoPaneKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _bg.withValues(alpha: 0.82),
                    _bg.withValues(alpha: 0.5),
                  ],
                ),
              ),
              child: _buildInfoPane(),
            ),
          ),
        ),
        Expanded(
          child: FocusScope(
            node: _episodesPaneScope,
            onKeyEvent: _handleEpisodesPaneKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0E0B14).withValues(alpha: 0.82),
                border: Border(left: BorderSide(color: _hair)),
              ),
              child: _buildEpisodesPanel(),
            ),
          ),
        ),
      ],
    );
  }

  /// Cross RIGHT into the episodes pane: the scope remembers its last-focused
  /// row, so re-entry lands where the user left off (first traversable —
  /// season header or first row — on a cold entry).
  void _focusEpisodesPane() {
    final scope = _episodesPaneScope;
    FocusNode? target = scope.focusedChild;
    if (target == null) {
      final descendants = scope.traversalDescendants;
      target = descendants.isEmpty ? null : descendants.first;
    }
    target?.requestFocus();
  }

  /// Info-pane key policy. These fire only for keys the focused child ignored
  /// (buttons/tiles don't handle arrows), and always attempt an in-scope
  /// directional move first — so Play → Trailer etc. still work — falling back
  /// to the explicit pane behavior only at the pane's edge:
  ///  • RIGHT at the right edge crosses into the episodes pane;
  ///  • UP at the top goes to the floating back button;
  ///  • DOWN at the bottom is a dead stop (never leaks into episodes).
  KeyEventResult _handleInfoPaneKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      if (!primary.focusInDirection(TraversalDirection.right)) {
        _focusEpisodesPane();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (!primary.focusInDirection(TraversalDirection.up)) {
        _backButtonFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      primary.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Episodes-pane key policy: Up/Down move within the pane only (dead stop at
  /// the first/last row — the scope already contains directional traversal;
  /// handling the key here just stops it from bubbling further). LEFT from the
  /// season header (rows handle their own LEFT) falls through the header
  /// controls and then crosses to the info column's primary action.
  KeyEventResult _handleEpisodesPaneKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      primary.focusInDirection(
        key == LogicalKeyboardKey.arrowUp
            ? TraversalDirection.up
            : TraversalDirection.down,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!primary.focusInDirection(TraversalDirection.left) &&
          _leftEntryFocusNode.context != null) {
        _leftEntryFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildInfoPane() {
    final item = _item;
    final extra = _imdbExtra;
    final t = _tight;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final genres = (item.genres?.isNotEmpty ?? false)
        ? item.genres!
        : (extra?.genres ?? const []);
    final summary = (item.description?.isNotEmpty ?? false)
        ? item.description
        : extra?.plot;

    // No entrance stagger on TV: each _StaggerReveal animates Opacity (a
    // saveLayer per element per frame) during the exact window the page is
    // also hero-flying and resolving the trailer — the weak TV GPU pays for
    // polish nobody perceives at 3m. Same gate as the Home hero's motion.
    final animate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        !widget.isTelevision;
    return SingleChildScrollView(
      controller: _infoScroll,
      padding: EdgeInsets.fromLTRB(
        widget.isTelevision ? 34 : 24,
        // Clear the floating top-left back button (~64px) on TV so the eyebrow
        // and title don't sit under it.
        widget.isTelevision ? 64 : (t ? 46 : 30),
        18,
        22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StaggerReveal(
            key: const ValueKey('rev-eyebrow'),
            delayMs: 0,
            enabled: animate,
            child: Text(
              _isMovie ? 'MOVIE' : 'SERIES',
              style: TextStyle(
                color: _accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          SizedBox(height: t ? 5 : 8),
          _StaggerReveal(
            key: const ValueKey('rev-title'),
            delayMs: 55,
            enabled: animate,
            child: Text(
              item.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: t ? 22 : 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.05,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
              ),
            ),
          ),
          SizedBox(height: t ? 8 : 10),
          _StaggerReveal(
            key: const ValueKey('rev-meta'),
            delayMs: 110,
            enabled: animate,
            child: _buildMetaBar(year, extra, rating),
          ),
          if (_buildTraktStatusChips() case final chips?) ...[
            SizedBox(height: t ? 8 : 10),
            _StaggerReveal(
              key: const ValueKey('rev-trakt-status'),
              delayMs: 140,
              enabled: animate,
              child: chips,
            ),
          ],
          if (genres.isNotEmpty) ...[
            SizedBox(height: t ? 8 : 10),
            _StaggerReveal(
              key: const ValueKey('rev-genres'),
              delayMs: 165,
              enabled: animate,
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [for (final g in genres.take(3)) _pill(g)],
              ),
            ),
          ],
          SizedBox(height: t ? 12 : 16),
          // Focusing the action row snaps the column to the very top so the
          // title / meta / genres above it are revealed (fixes "can't scroll
          // back up to details").
          _StaggerReveal(
            key: const ValueKey('rev-actions'),
            delayMs: 220,
            enabled: animate,
            child: _ScrollAnchor(
              toTop: true,
              active: widget.isTelevision,
              child: _buildActionRow(),
            ),
          ),
          if (summary != null && summary.isNotEmpty) ...[
            SizedBox(height: t ? 16 : 20),
            _sectionLabel('Summary'),
            const SizedBox(height: 8),
            Text(
              summary,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          // Awards / Credits / Cast / Details / Parents Guide / More Like This —
          // all inline & reachable by scrolling (no hidden "Details" sheet).
          ..._referenceSections(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // Mobile-only compact hero (wide/TV uses the left info pane instead).
  Widget _buildHero() {
    final item = _item;
    final extra = _imdbExtra;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final genres = (item.genres?.isNotEmpty ?? false)
        ? item.genres!
        : (extra?.genres ?? const []);

    // No boxed hero image: the page already paints one continuous full-bleed
    // backdrop (HeroTrailerBackdrop + dark tint) behind everything — exactly
    // like the movie layout — so a second inset image here read as an ugly
    // floating card. The hero is now pure content over that shared surface,
    // sized to what it holds (the old fixed 220px box overflowed upward when
    // the action row wrapped, shoving the title under the floating back
    // button). Bonus: with autoplay on, the ambient trailer now owns the whole
    // screen behind the page instead of stopping at a card edge. Top padding
    // clears the 46px floating back button.
    final animate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        !widget.isTelevision;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.isTelevision ? 40 : 24,
        widget.isTelevision ? 20 : 64,
        24,
        14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StaggerReveal(
            key: const ValueKey('rev-h-eyebrow'),
            delayMs: 0,
            enabled: animate,
            child: Text(
              'SERIES',
              style: TextStyle(
                color: _accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _StaggerReveal(
            key: const ValueKey('rev-h-title'),
            delayMs: 55,
            enabled: animate,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _wide ? 34 : 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.02,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _StaggerReveal(
            key: const ValueKey('rev-h-meta'),
            delayMs: 110,
            enabled: animate,
            child: _buildMetaBar(year, extra, rating),
          ),
          if (_buildTraktStatusChips() case final chips?) ...[
            const SizedBox(height: 10),
            _StaggerReveal(
              key: const ValueKey('rev-h-trakt-status'),
              delayMs: 140,
              enabled: animate,
              child: chips,
            ),
          ],
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            _StaggerReveal(
              key: const ValueKey('rev-h-genres'),
              delayMs: 165,
              enabled: animate,
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [for (final g in genres.take(4)) _pill(g)],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _StaggerReveal(
            key: const ValueKey('rev-h-actions'),
            delayMs: 220,
            enabled: animate,
            child: _buildActionRow(),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaBar(String? year, ImdbEnrichment? extra, double? rating) {
    final parts = <Widget>[];
    void add(Widget w) {
      if (parts.isNotEmpty) parts.add(const SizedBox(width: 16));
      parts.add(w);
    }

    final runtime = extra?.runtime;
    if (runtime != null) add(_metaText(runtime));
    if (year != null && year.isNotEmpty) add(_metaText(year));
    final cert = extra?.certificate;
    if (cert != null) {
      add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: _glass2,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _hair),
          ),
          child: Text(
            cert,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    if (rating != null) {
      add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rating.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _imdb,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'IMDb',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: parts);
  }

  /// Small state badges from the live Trakt status (In Watchlist / In
  /// Collection / Watched / ★rating). Renders nothing until the status resolves
  /// or when the title has no tracked state, so the layout doesn't jump.
  Widget? _buildTraktStatusChips() {
    final s = _traktStatus;
    if (s == null) return null;
    final chips = <Widget>[
      if (s.inWatchlist)
        _statusChip(Icons.bookmark_rounded, 'In Watchlist', _gold),
      if (s.inCollection)
        _statusChip(
          Icons.video_library_rounded,
          'In Collection',
          const Color(0xFF7FB2FF),
        ),
      if (s.watched == true)
        _statusChip(
          Icons.visibility_rounded,
          'Watched',
          const Color(0xFF34D399),
        ),
      if (s.rating != null)
        _statusChip(Icons.star_rounded, '${s.rating}/10', _gold),
    ];
    if (chips.isEmpty) return null;
    return Wrap(spacing: 7, runSpacing: 7, children: chips);
  }

  Widget _statusChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
  );

  Widget _metaText(String s) => Text(
    s,
    style: const TextStyle(
      color: Colors.white70,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _buildActionRow() {
    final count = widget.boundSourceCount?.call(_item) ?? 0;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Primary play. Hidden for PikPak-only (can't quick-play — it queues a
        // cloud download), mirroring the detail screen's "Play". Holds the
        // LEFT-entry focus node when present; movies autofocus it on TV (a movie
        // has no episode list to auto-focus).
        if (widget.showQuickPlay)
          _PrimaryButton(
            label: _primaryLabel,
            icon: Icons.play_arrow_rounded,
            onTap: widget.onResume,
            focusNode: _leftEntryFocusNode,
            autofocus: widget.isTelevision && _isMovie,
            glow: _accent,
          ),
        // Trailer — sits right after Play. Only when Cinemeta gave us a YouTube
        // trailer id. Reflects the ambient backdrop's state: spinner while the
        // trailer loads, "Watch Trailer" once it's playing (tap = fullscreen),
        // plain "Trailer" otherwise (tap = resolve & play).
        if (_trailerYtId != null)
          _GhostButton(
            label: _trailerAmbientPlaying ? 'Watch Trailer' : 'Trailer',
            icon: _trailerAmbientPlaying
                ? Icons.play_circle_outline_rounded
                : Icons.movie_outlined,
            busy: _trailerResolving || _trailerLoading,
            onTap: _playTrailer,
          ),
        // Movie: a Sources (manual list) button — the episode list is the
        // picker for series, so this is movie-only.
        if (_isMovie && widget.onBrowse != null)
          _GhostButton(
            label: 'Sources',
            icon: Icons.layers_rounded,
            onTap: widget.onBrowse!,
          ),
        // Source binding. Takes the LEFT-entry focus node only when Play is
        // hidden (PikPak), so LEFT from an episode always lands on a live target.
        if (widget.onSelectSource != null)
          _SourcePill(
            count: count,
            focusNode: widget.showQuickPlay ? null : _leftEntryFocusNode,
            // A movie with Play hidden (PikPak-only) has no episode list to
            // auto-focus and no Play to autofocus — start the remote here.
            autofocus: widget.isTelevision && _isMovie && !widget.showQuickPlay,
            onTap: () async {
              await widget.onSelectSource!(_item);
              if (mounted) setState(() {});
            },
          ),
        // More — opens the labelled quick-actions menu (with descriptions).
        if (_menuOptions.isNotEmpty && widget.onTraktAction != null)
          _RoundIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More options',
            onTap: _showQuickActionsMenu,
          ),
      ],
    );
  }

  /// Human-readable description of each quick action, shown in the More menu.
  static String _descriptionFor(TraktItemMenuAction a) {
    switch (a) {
      case TraktItemMenuAction.selectSource:
        return 'Pin a specific torrent or file as this title\'s source so every '
            'play uses it — no re-searching each time. Change or clear it here.';
      case TraktItemMenuAction.addToStremioTv:
        return 'Add this to your Stremio TV channel so it plays in your '
            'always-on rotation alongside your other picks.';
      case TraktItemMenuAction.playRandomEpisode:
        return 'Skip the browsing and jump straight into a random episode from '
            'this series — handy for background or comfort watching.';
      case TraktItemMenuAction.searchPacks:
        return 'Open a search for full-season and complete-series packs, then '
            'do whatever you want with a result — play it, download it, and more.';
      case TraktItemMenuAction.addToWatchlist:
        return 'Save this to your Trakt watchlist so you can find it later, '
            'synced across every device signed into your account.';
      case TraktItemMenuAction.removeFromWatchlist:
        return 'Take this off your Trakt watchlist — it won\'t appear in your '
            '"to watch" list anymore.';
      case TraktItemMenuAction.addToCollection:
        return 'Mark this as part of your Trakt collection — your library of '
            'everything you own or keep track of.';
      case TraktItemMenuAction.removeFromCollection:
        return 'Remove this from your Trakt collection.';
      case TraktItemMenuAction.markWatched:
        return 'Mark every episode of this title as watched on Trakt and sync '
            'that history across all your devices.';
      case TraktItemMenuAction.markUnwatched:
        return 'Clear this title from your Trakt history so it counts as '
            'unwatched again and can resurface in "up next".';
      case TraktItemMenuAction.rate:
        return 'Give this a 1–10 rating on Trakt. Your ratings sync everywhere '
            'and help shape your recommendations.';
      case TraktItemMenuAction.removeRating:
        return 'Remove the rating you previously gave this on Trakt.';
      case TraktItemMenuAction.addToList:
        return 'Add this to one of your custom Trakt lists — like "Weekend", '
            '"With friends" or anything you\'ve made.';
      case TraktItemMenuAction.removeFromList:
        return 'Remove this from one of your custom Trakt lists.';
      case TraktItemMenuAction.removeFromPlayback:
        return 'Remove this from Continue Watching so it stops showing on your '
            'home rows and resume list.';
      case TraktItemMenuAction.removeFromTraktPlayback:
        return 'Delete this title\'s playback progress (and watch history) on '
            'Trakt so it leaves the Trakt Continue Watching rows.';
    }
  }

  void _showQuickActionsMenu() {
    final options = _menuOptions;
    if (options.isEmpty || widget.onTraktAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      // Same standard sheet chrome as the per-episode ⋮ menu.
      backgroundColor: const Color(0xFF141019),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _QuickActionsMenu(
        title: _item.name,
        options: options,
        isTelevision: widget.isTelevision,
        onSelected: (action) async {
          Navigator.of(sheetCtx).pop();
          await widget.onTraktAction?.call(action);
          // The action likely changed the title's Trakt state (watchlist /
          // collection / watched / rating) — refresh so the menu and badges
          // reflect it on the next open.
          if (mounted) _loadTraktStatus();
        },
      ),
    );
  }

  // ── Bodies ────────────────────────────────────────────────────────────────

  Widget _buildEpisodesPanel() {
    return EpisodesPanel(
      key: _episodesPanelKey,
      show: widget.item,
      addon: widget.addon,
      initialSeason: widget.initialSeason,
      initialEpisode: widget.initialEpisode,
      isTelevision: widget.isTelevision,
      // Match the standalone `_openEpisodes` flow, which does NOT pass
      // showQuickPlay (defaults true) — episode tiles keep quick-play even for
      // PikPak-only. Only the hero Resume (≙ detail "Play") is PikPak-gated.
      showQuickPlay: true,
      isTraktSource: widget.isTraktSource,
      // Sources / fallback-search render in-tab on the Search host, so tear
      // down every merged/detail route first — popUntil the route name because
      // a single pop would leave a *parent* merged screen (series A →
      // recommended series B → pick episode) underneath instead of returning
      // to Search (every merged/detail route shares kCatalogDetailRouteName).
      // Mirrors the standalone EpisodesScreen._popToHost.
      onItemSelected: widget.onItemSelected == null
          ? null
          : (selection) {
              _popToHost();
              widget.onItemSelected!(selection);
            },
      // Quick-play deliberately does NOT pop: the host pushes the player on
      // top of this screen (same as the hero Resume), so playback pops back to
      // the episode list here — didPopNext then refreshes the ticks.
      onQuickPlay: widget.onQuickPlay,
      boundSourceCount: widget.boundSourceCount,
      onSelectSource: widget.onSelectSource,
      showChrome: false,
      compact: true,
      // Null when neither Play nor the source pill exists (no holder for the
      // node) — the episode row then leaves LEFT to directional traversal
      // instead of swallowing it as a dead key.
      onFocusLeftEdge: (widget.showQuickPlay || widget.onSelectSource != null)
          ? () => _leftEntryFocusNode.requestFocus()
          : null,
      onBack: () => Navigator.of(context).maybePop(),
    );
  }

  /// Tear every merged/detail route (any drill-down depth) back down to the
  /// Search host, so a selection it renders in-tab isn't hidden behind them.
  void _popToHost() {
    Navigator.of(
      context,
    ).popUntil((r) => r.settings.name != kCatalogDetailRouteName);
  }

  /// Stacked layout — mobile only. Compact hero (with Play/Bind/More) → a
  /// "Details" opener for cast/ratings/parents/recs → episodes. Quick actions
  /// live behind the hero's More (⋮) button.
  Widget _buildStackedBody() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 16, 4),
            child: TextButton.icon(
              onPressed: _openDetailsSheet,
              icon: const Icon(Icons.info_outline_rounded, size: 18),
              label: const Text('Cast, ratings & more'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ),
        ),
        Expanded(child: _buildEpisodesPanel()),
      ],
    );
  }

  void _openDetailsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Quick actions already shown in the strip; the sheet holds the rest.
            children: _sideRailSections(),
          ),
        ),
      ),
    );
  }

  // ── Side-rail sections (shared by wide rail + narrow details sheet) ─────────

  /// The reference sections that live inline in the TV info column (awards,
  /// credits, cast, details, parents guide, more like this) — no quick actions,
  /// no summary (both already shown above in the info pane).
  List<Widget> _referenceSections() {
    return [
      const SizedBox(height: 20),
      ..._sideRailSections(includeSummary: false),
    ];
  }

  List<Widget> _sideRailSections({bool includeSummary = true}) {
    final item = _item;
    final extra = _imdbExtra;
    final sections = <Widget>[];

    final summary = (item.description?.isNotEmpty ?? false)
        ? item.description
        : extra?.plot;
    if (includeSummary && summary != null && summary.isNotEmpty) {
      sections
        ..add(_sectionLabel('Summary'))
        ..add(const SizedBox(height: 8))
        ..add(
          Text(
            summary,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    // Awards (gold pill) — parity with the detail screen.
    final awardsLine = extra?.hasAwards == true ? extra!.awardsLine : null;
    if (awardsLine != null && awardsLine.isNotEmpty) {
      sections
        ..add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold.withValues(alpha: 0.24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded, size: 15, color: _gold),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    awardsLine,
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    // Credits (director / stars) — parity with the detail screen.
    final creditRows = <(String, String)>[];
    if (extra != null) {
      if (extra.director != null && extra.director!.isNotEmpty) {
        creditRows.add(('Director', extra.director!));
      }
      if (extra.stars.isNotEmpty) {
        creditRows.add(('Stars', extra.stars.take(4).join(', ')));
      }
    }
    if (creditRows.isNotEmpty) {
      sections
        ..add(_sectionLabel('Credits'))
        ..add(const SizedBox(height: 8))
        ..add(_kvBlock(creditRows))
        ..add(const SizedBox(height: 22));
    }

    // Details (country / language / studio / box office) — grouped with the
    // other non-focusable text ABOVE the focusable Cast/Recs/Parents-Guide, so
    // on TV it's revealed while scrolling down to those (never stranded below
    // the last focusable when e.g. Parents Guide is absent).
    final detailRows = <(String, String)>[];
    if (extra != null) {
      if (extra.countries.isNotEmpty) {
        detailRows.add(('Country', extra.countries.take(2).join(', ')));
      }
      if (extra.languages.isNotEmpty) {
        detailRows.add(('Language', extra.languages.take(3).join(', ')));
      }
      if (extra.productionCompany != null) {
        detailRows.add(('Studio', extra.productionCompany!));
      }
      if (extra.boxOffice != null) {
        detailRows.add(('Box Office', extra.boxOffice!));
      }
    }
    if (detailRows.isNotEmpty) {
      sections
        ..add(_sectionLabel('Details'))
        ..add(const SizedBox(height: 8))
        ..add(_kvBlock(detailRows))
        ..add(const SizedBox(height: 22));
    }

    // Cast / More Like This are capped so the rails can build EVERY card up
    // front (see [_focusRail]) without a wall of image fetches — DPAD needs
    // real widgets to walk onto, and a dozen tiny thumbs is plenty of content.
    final cast = (extra?.cast ?? const []).take(12).toList();
    if (cast.isNotEmpty) {
      sections
        ..add(_sectionLabel('Cast'))
        ..add(const SizedBox(height: 12))
        ..add(
          _ScrollAnchor(
            active: widget.isTelevision,
            alignment: 0.35,
            child: SizedBox(
              height: 92,
              child: _focusRail(
                gap: 14,
                cards: [for (final m in cast) _castTile(m)],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    // More Like This — placed high (right after Cast) so it's an easy DPAD-down
    // reach, ahead of the long focusable Parents-Guide list.
    final recs = (_recommendations ?? const <StremioMeta>[]).take(10).toList();
    if (recs.isNotEmpty && widget.onRecommendationTap != null) {
      sections
        ..add(_sectionLabel('More Like This'))
        ..add(const SizedBox(height: 12))
        ..add(
          _ScrollAnchor(
            active: widget.isTelevision,
            alignment: 0.5,
            child: SizedBox(
              height: 168,
              child: _focusRail(
                gap: 11,
                cards: [for (final r in recs) _recCard(r)],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    final guide = _parentsGuide;
    if (guide != null && !guide.isEmpty) {
      sections
        ..add(_sectionLabel('Parents Guide'))
        ..add(const SizedBox(height: 12))
        ..add(
          ParentsGuideSection(
            guide: guide,
            tv: widget.isTelevision,
            dense: true,
          ),
        );
    }

    return sections;
  }

  /// Horizontal DPAD rail (Cast / More Like This). Builds ALL cards in a plain
  /// scrollable Row — a lazy ListView only builds what's near the viewport, so
  /// DPAD-right at the build edge found no next card and the focus jumped clean
  /// out of the rail (into the episodes pane) mid-browse. With every card real,
  /// traversal walks the whole rail and the framework auto-scrolls each focused
  /// card into view. The first card traps LEFT as a dead stop; the last card's
  /// RIGHT crosses deterministically into the episodes pane in the series
  /// two-pane layout (dead stop otherwise) — RIGHT is the sanctioned pane
  /// crossing, so it should work from a rail end too.
  Widget _focusRail({required List<Widget> cards, required double gap}) {
    final crossRight = (!_isMovie && _wide) ? _focusEpisodesPane : null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            _RailEdgeTrap(
              trapLeft: i == 0,
              trapRight: i == cards.length - 1,
              onTrapRight: crossRight,
              child: cards[i],
            ),
          ],
        ],
      ),
    );
  }

  Widget _castTile(CastMember m) => _CastTile(member: m, fallback: _glass2);

  Widget _recCard(StremioMeta rec) => _RecCard(
    rec: rec,
    fallback: _glass2,
    onTap: () => widget.onRecommendationTap?.call(rec),
  );

  Widget _sectionLabel(String s) => Text(
    s.toUpperCase(),
    style: const TextStyle(
      color: Colors.white38,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
    ),
  );

  /// Label→value rows (Credits / Details), matching the detail screen's layout.
  Widget _kvBlock(List<(String, String)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  rows[i].$1,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
              Expanded(
                child: Text(
                  rows[i].$2,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _pill(String s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: _glass2,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _hair),
    ),
    child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 12)),
  );

  Widget _circleButton(
    IconData icon,
    VoidCallback onTap, {
    String? tooltip,
    FocusNode? focusNode,
  }) {
    return _RoundIconButton(
      icon: icon,
      onTap: onTap,
      tooltip: tooltip,
      focusNode: focusNode,
      background: Colors.black.withValues(alpha: 0.35),
    );
  }
}

// ── Small presentational widgets ───────────────────────────────────────────

/// One-shot entrance for a hero-block item: after [delayMs], fades up from
/// transparent while rising 12px, so the detail header assembles itself around
/// the shared-element poster flight instead of popping in fully formed.
///
/// Cheap and TV-safe: a single 340ms opacity+translate on a small widget, run
/// once on mount (the controller never resets, so metadata-load rebuilds don't
/// replay it). [enabled] is false under OS reduced-motion — the child shows
/// immediately with no controller. Late-arriving sections (their own first
/// mount happens when enrichment lands) simply fade in on arrival.
class _StaggerReveal extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final bool enabled;

  const _StaggerReveal({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.enabled = true,
  });

  @override
  State<_StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<_StaggerReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _timer = Timer(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller?.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Gold DPAD focus ring — an in-bounds *foreground* border, exactly like the
/// episode rows in the right pane (and the same [HomeTheme.focusGold] hue, so
/// the cursor doesn't shift color crossing panes). Every interactive element on
/// this screen wraps itself in one — the default InkWell focus overlay is
/// invisible on both the white Play pill and dark glass surfaces, which made
/// the remote cursor untrackable on TV.
///
/// Deliberately NOT a shadow ring: spread shadows paint a *filled* rect behind
/// the child (they bleed through translucent glass surfaces as a solid gold
/// fill), and they paint outside bounds (forcing rails to un-clip and leak
/// scrolled-out tiles). A foreground border stays crisp on any surface, keeps
/// the glass translucency, and never needs `Clip.none`.
class _FocusHalo extends StatelessWidget {
  final bool focused;
  final BorderRadius? radius; // null → circle
  final Widget child;

  const _FocusHalo({required this.focused, required this.child, this.radius});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      // Snap on TV (house focus idiom): a 140ms ring fade per DPAD move makes
      // held-key surfing repaint every element in flight on the weak GPU.
      duration: PlatformUtil.isAndroidTvCached
          ? Duration.zero
          : const Duration(milliseconds: 140),
      foregroundDecoration: BoxDecoration(
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        border: focused
            ? Border.all(color: HomeTheme.focusGold, width: 2.5)
            : null,
      ),
      child: child,
    );
  }
}

/// Wraps a rail's end cards: consumes LEFT on the first / RIGHT on the last so
/// the DPAD cursor stops at the rail's edge instead of escaping to whatever is
/// geometrically nearest (the episodes pane, the back button). A non-focusable
/// ancestor node sees the key on its way up from the focused card, before the
/// app-level shortcuts turn it into a traversal move.
class _RailEdgeTrap extends StatelessWidget {
  final bool trapLeft;
  final bool trapRight;
  final Widget child;

  /// When set, RIGHT on the last card invokes this (pane crossing) instead of
  /// dead-stopping.
  final VoidCallback? onTrapRight;

  const _RailEdgeTrap({
    required this.trapLeft,
    required this.trapRight,
    required this.child,
    this.onTrapRight,
  });

  @override
  Widget build(BuildContext context) {
    if (!trapLeft && !trapRight) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (trapLeft && key == LogicalKeyboardKey.arrowLeft) {
          return KeyEventResult.handled;
        }
        if (trapRight && key == LogicalKeyboardKey.arrowRight) {
          onTrapRight?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// Cast avatar — focusable (no-op tap) so DPAD-down can walk the info column
/// through it, with a visible gold ring while focused.
class _CastTile extends StatefulWidget {
  final CastMember member;
  final Color fallback;
  const _CastTile({required this.member, required this.fallback});

  @override
  State<_CastTile> createState() => _CastTileState();
}

class _CastTileState extends State<_CastTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          _FocusHalo(
            focused: _focused,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {},
                onFocusChange: (f) => setState(() => _focused = f),
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: (m.imageUrl != null && m.imageUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: m.imageUrl!,
                          fit: BoxFit.cover,
                          cacheManager: DebrifyImageCache.manager,
                          // 56 logical px avatar (up to dpr 3 on phones) —
                          // never decode a full-res headshot.
                          memCacheWidth: 180,
                          placeholder: (_, __) =>
                              Container(color: widget.fallback),
                          errorWidget: (_, __, ___) =>
                              Container(color: widget.fallback),
                        )
                      : Container(
                          color: widget.fallback,
                          child: const Icon(
                            Icons.person,
                            color: Colors.white38,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            m.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _focused ? Colors.white : Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// "More Like This" poster card — gold ring + slight scale while focused so the
/// DPAD cursor is unmistakable over artwork.
class _RecCard extends StatefulWidget {
  final StremioMeta rec;
  final Color fallback;
  final VoidCallback onTap;
  const _RecCard({
    required this.rec,
    required this.fallback,
    required this.onTap,
  });

  @override
  State<_RecCard> createState() => _RecCardState();
}

class _RecCardState extends State<_RecCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final rec = widget.rec;
    return SizedBox(
      width: 100,
      child: _FocusHalo(
        focused: _focused,
        radius: BorderRadius.circular(10),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _focused = f),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: (rec.poster != null && rec.poster!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: rec.poster!,
                      fit: BoxFit.cover,
                      cacheManager: DebrifyImageCache.manager,
                      // 100 logical px card (up to dpr 3 on phones) — decode
                      // small so ten posters at once don't lean on a 2GB box.
                      memCacheWidth: 300,
                      placeholder: (_, __) =>
                          Container(color: widget.fallback),
                      errorWidget: (_, __, ___) =>
                          Container(color: widget.fallback),
                    )
                  : Container(color: widget.fallback),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Per-title accent used for the soft glow behind the white pill, so the
  /// primary CTA reads as belonging to this title.
  final Color glow;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.glow = _MergedDetailScreenState._gold,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      // Snap on TV: every frame of the scale pop re-rasters the pill AND its
      // blur-18 glow shadow; instant scale keeps the glow a one-time paint.
      duration: PlatformUtil.isAndroidTvCached
          ? Duration.zero
          : const Duration(milliseconds: 140),
      scale: _focused ? 1.05 : 1.0,
      child: _FocusHalo(
        focused: _focused,
        radius: BorderRadius.circular(999),
        // Soft accent glow behind the pill. A static drop shadow (rasterised
        // once, carried by the AnimatedScale transform) — not a per-frame
        // backdrop blur — so it's safe on the weak TV GPU. Animates its color
        // to the title accent when it resolves.
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 500),
          tween: ColorTween(end: widget.glow.withValues(alpha: 0.45)),
          builder: (_, color, child) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: color ?? Colors.transparent,
                  blurRadius: 18,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: child,
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              onFocusChange: (f) => setState(() => _focused = f),
              borderRadius: BorderRadius.circular(999),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: const Color(0xFF0D0D10), size: 20),
                    const SizedBox(width: 7),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Color(0xFF0D0D10),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle "trailer playing in background" hint pill. An informational hint, not
/// a primary control (the focusable "Watch Trailer" button is the DPAD way to
/// promote), so it's pointer/touch-tappable only — `canRequestFocus: false`
/// keeps it out of DPAD traversal entirely, so it can never steal focus or
/// strand the remote when it appears/disappears as the trailer plays/pauses.
class _TrailerPlayingChip extends StatelessWidget {
  final VoidCallback onTap;
  const _TrailerPlayingChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        canRequestFocus: false,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 7),
              Text(
                'Trailer playing',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Shows a small spinner in place of the icon (e.g. trailer resolving).
  final bool busy;

  const _GhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return _FocusHalo(
      focused: _focused,
      radius: BorderRadius.circular(999),
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                else
                  Icon(widget.icon, color: Colors.white, size: 18),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourcePill extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  const _SourcePill({
    required this.count,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<_SourcePill> createState() => _SourcePillState();
}

class _SourcePillState extends State<_SourcePill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bound = widget.count > 0;
    const gold = _MergedDetailScreenState._gold;
    final label = bound
        ? (widget.count > 1 ? '${widget.count} sources' : '1 source')
        : 'Bind source';
    return _FocusHalo(
      focused: _focused,
      radius: BorderRadius.circular(999),
      child: Material(
        color: bound
            ? gold.withValues(alpha: 0.13)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: bound
                    ? gold.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  bound ? Icons.link_rounded : Icons.link_off_rounded,
                  color: bound ? gold : Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: bound ? gold : Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Auto-scrolls the enclosing scrollable when any descendant gains focus.
///
/// [Focus.onFocusChange] fires when this node *or a descendant* changes focus,
/// so wrapping a section with this (non-focusable, traversal-skipping) node
/// lets us react to a child button/tile being focused via DPAD:
///  • [toTop] snaps the column to offset 0 (reveals the header above the first
///    focusable — the "can't scroll back up to the details" fix);
///  • otherwise it `ensureVisible`s the wrapped section at [alignment].
class _ScrollAnchor extends StatelessWidget {
  final Widget child;
  final bool toTop;
  final double alignment;

  /// Only meaningful on TV (DPAD focus scroll). On pointer/desktop this is a
  /// passthrough so a mouse click doesn't yank the column around.
  final bool active;

  const _ScrollAnchor({
    required this.child,
    this.toTop = false,
    this.alignment = 0.5,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        // Defer so it wins over the framework's own focus-ensureVisible and
        // runs after layout settles.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (toTop) {
            Scrollable.maybeOf(context)?.position.animateTo(
              0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          } else {
            Scrollable.ensureVisible(
              context,
              alignment: alignment,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          }
        });
      },
      child: child,
    );
  }
}

/// Circular translucent icon button used for the hero "More" (⋮) affordance.
class _RoundIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? background;
  final FocusNode? focusNode;
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.background,
    this.focusNode,
  });

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final btn = _FocusHalo(
      focused: _focused,
      child: Material(
        color: widget.background ?? Colors.white.withValues(alpha: 0.08),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(widget.icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? btn
        : Tooltip(message: widget.tooltip!, child: btn);
  }
}

/// The "More" quick-actions menu — a labelled sheet with an icon, name and a
/// one-line description for every action, so users know what each one does.
class _QuickActionsMenu extends StatelessWidget {
  final String title;
  final List<TraktMenuOption> options;
  final bool isTelevision;
  final void Function(TraktItemMenuAction action) onSelected;

  const _QuickActionsMenu({
    required this.title,
    required this.options,
    required this.isTelevision,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Standard sheet chrome (background + drag handle) is provided by
    // showModalBottomSheet — this widget is just the header + clean list, so it
    // reads the same as the per-episode ⋮ menu.
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: options.length,
                itemBuilder: (context, i) => _item(options[i], i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(TraktMenuOption o, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: isTelevision && index == 0,
        // The default focus overlay is invisible on the dark sheet — make the
        // DPAD cursor obvious.
        focusColor: Colors.white.withValues(alpha: 0.12),
        onTap: () => onSelected(o.action),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 18, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(o.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      o.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _MergedDetailScreenState._descriptionFor(o.action),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
