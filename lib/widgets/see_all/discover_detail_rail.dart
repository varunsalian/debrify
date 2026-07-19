import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/app_route_observer.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_service.dart';
import '../../services/youtube_service.dart';
import '../home/home_theme.dart';
import 'see_all_theme.dart';

/// The fixed left pane of the Discover two-pane layout (TV). It never takes
/// focus — it purely *reacts* to whichever grid tile the DPAD is on, showing a
/// backdrop, title, metadata and plot for that title.
///
/// List items are metadata-poor (usually just poster + name), so the rail draws
/// what it has instantly and then, after a short dwell, fetches the enriched
/// `/meta` details (backdrop, plot, rating, runtime, genres) and fades them in —
/// the same enrichment the board hero uses, cached in [StremioService], so
/// re-focusing a title is free. Rapid arrowing never triggers a fetch: the
/// debounce only fires once the remote rests on a card.
class DiscoverDetailRail extends StatefulWidget {
  /// The currently DPAD-focused item, or null before anything is focused.
  final StremioMeta? item;

  /// Resolved trailer streams are published here (not rendered by the rail): the
  /// full-screen [DiscoverTrailerStage] over the two-pane consumes them so the
  /// window can grow to a fullscreen takeover. The rail still owns all the
  /// *decisions* (dwell, resolve, suppression) — it just writes the result out.
  final ValueNotifier<YoutubeResolvedStreams?> trailerStreams;

  /// Shared loading flag for the "Trailer" pill (rail sets true while resolving;
  /// the stage drops it when frames land).
  final ValueNotifier<bool> trailerLoading;

  /// Shared ambient volume (rail writes it once the setting loads; the stage
  /// reads it when it mounts the player).
  final ValueNotifier<double> trailerVolume;

  /// The enriched title behind the current trailer — the stage's fullscreen
  /// takeover overlay reads it for the name/meta. Kept in lock-step with
  /// [trailerStreams] (set on publish, nulled on teardown).
  final ValueNotifier<StremioMeta?> trailerMeta;

  /// What the rail is actually rendering (focused item merged with enrichment)
  /// — published so the host's full-frame glass stage can draw this title's
  /// backdrop behind both panes. Written post-frame (the rail adopts items
  /// during build, when marking the already-built stage dirty would assert).
  final ValueNotifier<StremioMeta?> shownItem;

  const DiscoverDetailRail({
    super.key,
    required this.item,
    required this.trailerStreams,
    required this.trailerLoading,
    required this.trailerVolume,
    required this.trailerMeta,
    required this.shownItem,
  });

  @override
  State<DiscoverDetailRail> createState() => _DiscoverDetailRailState();
}

class _DiscoverDetailRailState extends State<DiscoverDetailRail>
    with RouteAware, WidgetsBindingObserver {
  final StremioService _stremio = StremioService.instance;

  /// What's actually rendered — the focused item merged with any enrichment.
  StremioMeta? _shown;
  Timer? _enrichDebounce;

  /// Titles already enriched this session, keyed by imdbId, so re-focusing one
  /// paints its full detail immediately instead of flashing back to the
  /// metadata-poor list item while a fresh (cached) fetch round-trips. Keyed by
  /// imdbId — not the display `id`, which can be empty or non-unique across
  /// sources — and only enrichable items (which always have an imdbId) land
  /// here. FIFO-capped so a long browse can't grow it without bound.
  static const int _cacheCap = 128;
  final Map<String, StremioMeta> _enriched = {};

  StremioMeta? _cachedFor(StremioMeta? m) =>
      m?.imdbId == null ? null : _enriched[m!.imdbId];

  // ── Ambient trailer ────────────────────────────────────────────────────────
  // Once a card is rested (dwell), its trailer resolves; the rail publishes the
  // streams to the full-screen DiscoverTrailerStage (which renders + can promote
  // to fullscreen). The rail owns all the single-decoder discipline: it only
  // publishes a rested card's streams, and nulls them on route-cover /
  // app-background / player-launch, so the stage tears the codec down in step.
  bool _trailerEnabled = false;
  Timer? _trailerDwell;
  Timer? _pillDwell; // surfaces the "Trailer" pill on rest, before the resolve
  Timer? _loadingWatchdog; // bounds the pill if a stream resolves but never plays
  String? _trailerImdb; // imdbId the current trailer / pending dwell is for

  /// Mirror of [widget.trailerStreams.value] — the streams currently published.
  /// Setting it also keeps [widget.trailerMeta] in lock-step so the takeover
  /// overlay always names the title that's actually playing.
  YoutubeResolvedStreams? get _streams => widget.trailerStreams.value;
  set _streams(YoutubeResolvedStreams? v) {
    // Meta first, so the stage's meta listener updates its held copy before its
    // streams listener mounts the player for a new title.
    widget.trailerMeta.value = v == null ? null : _shown;
    widget.trailerStreams.value = v;
  }

  /// Set the instant real playback launches; blocks the trailer (including an
  /// in-flight resolve and any late re-arm) from grabbing the single TV decoder
  /// out from under the player. Cleared when we return (route pop / app resume)
  /// or the user browses to another title, which then re-arms the trailer.
  bool _suppressed = false;

  /// Dwell before a rested card resolves its trailer — long enough that fast
  /// arrowing never spins a resolve, short enough that the video follows the
  /// pill promptly.
  static const Duration _trailerDwellDelay = Duration(milliseconds: 900);

  /// A shorter dwell that just surfaces the "Trailer" loading pill, so a rested
  /// card shows prompt feedback the moment the user settles — the pill is up for
  /// the whole search (dwell → resolve → buffer), not a flash right before the
  /// video. Only fires for cards we already know carry a trailer, so no-trailer
  /// cards never show a false spinner.
  static const Duration _pillDwellDelay = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _adopt(widget.item);
    WidgetsBinding.instance.addObserver(this);
    MainPageBridge.addPlayerLaunchListener(_onPlayerLaunch);
    // Reuse the Home hero's ambient-trailer preference so one toggle governs
    // both living surfaces; volume is 0 when the sound sub-toggle is off.
    Future.wait([
      StorageService.getHomeHeroTrailerEnabled(),
      StorageService.getHomeHeroTrailerAudioEnabled(),
      StorageService.getHomeHeroTrailerVolume(),
    ]).then((v) {
      if (!mounted || !(v[0] as bool)) return;
      _trailerEnabled = true;
      widget.trailerVolume.value = (v[1] as bool) ? (v[2] as int).toDouble() : 0;
      _evaluateTrailer(); // a card may already be rested by the time this lands
    });
  }

  @override
  void didUpdateWidget(covariant DiscoverDetailRail old) {
    super.didUpdateWidget(old);
    // Compare by identity, not id: focus lands on distinct StremioMeta instances,
    // and comparing `id` would miss a move between two items that share an empty
    // or duplicate id.
    if (!identical(widget.item, old.item)) _adopt(widget.item);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  /// The route that covered us (a detail page, or a Flutter-route player) popped
  /// back — we're browsing again, so lift suppression and re-arm the trailer for
  /// the still-focused title (which otherwise never re-evaluates, since focus
  /// stayed on the same tile).
  @override
  void didPopNext() => _unsuppress();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A native TV player pushes no Flutter route, so its return only shows up as
    // an app resume — re-arm here too, but ONLY if Discover is actually back on
    // top. Backing out of a native player to a still-open detail page also
    // resumes the app; re-arming there would mount our decoder under the
    // covering page (which owns one). didPopNext re-arms on the real return.
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      _unsuppress();
    }
  }

  void _unsuppress() {
    if (!_suppressed) return;
    _suppressed = false;
    _evaluateTrailer();
  }

  /// Show the best we have for [m] right now — its already-enriched form if
  /// we've seen it, else the raw list item — then debounce a fetch if it's
  /// still thin.
  void _adopt(StremioMeta? m) {
    // Drop any pending fetch for the title we're leaving.
    _enrichDebounce?.cancel();
    // Direct assignment, not setState: both callers (initState, didUpdateWidget)
    // are always followed by a build, so a rebuild is already scheduled. Only
    // the async enrichment callback — which fires outside a build — needs
    // setState.
    final cached = _cachedFor(m);
    _shown = cached ?? m;
    _publishShown();
    if (m != null && cached == null) _scheduleEnrich(m);
    _evaluateTrailer();
  }

  /// Mirror [_shown] to the host's stage, deferred a frame: _adopt runs during
  /// build (initState/didUpdateWidget), and the stage — built earlier in the
  /// host's Stack — may already be laid out this frame. Reading [_shown] at fire
  /// time means queued callbacks all publish the latest value (idempotent).
  void _publishShown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.shownItem.value = _shown;
    });
  }

  @override
  void dispose() {
    _enrichDebounce?.cancel();
    _trailerDwell?.cancel();
    _pillDwell?.cancel();
    _loadingWatchdog?.cancel();
    MainPageBridge.removePlayerLaunchListener(_onPlayerLaunch);
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  bool _needsEnrich(StremioMeta m) =>
      m.imdbId != null &&
      (m.type == 'movie' || m.type == 'series') &&
      ((m.description?.isEmpty ?? true) ||
          m.background == null ||
          m.imdbRating == null ||
          m.runtime == null ||
          (m.genres?.isEmpty ?? true));

  void _scheduleEnrich(StremioMeta? m) {
    _enrichDebounce?.cancel();
    if (m == null || !_needsEnrich(m)) return;
    _enrichDebounce = Timer(const Duration(milliseconds: 320), () async {
      final enriched = await _stremio.fetchMetaDetails(
        imdbId: m.imdbId!,
        type: m.type,
      );
      if (enriched == null || !mounted) return;
      final merged = _merge(m, enriched);
      final key = m.imdbId!; // _needsEnrich guarantees non-null
      // Evict the oldest entry when full (FIFO — LinkedHashMap keeps insertion
      // order) before inserting a genuinely new title.
      if (_enriched.length >= _cacheCap && !_enriched.containsKey(key)) {
        _enriched.remove(_enriched.keys.first);
      }
      _enriched[key] = merged;
      // Only repaint if the user is still on this title (the cache above is kept
      // either way, so a later revisit still benefits).
      if (widget.item?.imdbId != key) return;
      setState(() => _shown = merged);
      // Async context (Timer) — safe to publish directly; the stage picks up
      // the enriched backdrop.
      widget.shownItem.value = merged;
      // If this title's trailer is already published, refresh the takeover meta
      // with the now-enriched details (the setter only wrote it at publish time,
      // which may have been the thin list item if enrichment landed late).
      if (_streams != null) widget.trailerMeta.value = merged;
      // Enrichment may have supplied the trailer id — (re)arm the dwell now.
      _evaluateTrailer();
    });
  }

  /// Reconcile the trailer to the focused title. Tears down the old trailer when
  /// the title changes, then — if the setting is on and the title is playable —
  /// debounces a resolve→play. Cheap and idempotent, so it's safe to call from
  /// every path that moves [_shown] (focus change, enrichment, settings load).
  void _evaluateTrailer() {
    final m = _shown;
    final imdb = m?.imdbId;
    // Focus moved to a different title (or away): drop the old trailer + dwell.
    // A genuine browse action also means we're no longer sitting behind a player,
    // so lift suppression here (the same-title return case is handled by
    // _unsuppress on route-pop / app-resume).
    if (imdb != _trailerImdb) {
      _trailerDwell?.cancel();
      _pillDwell?.cancel();
      _loadingWatchdog?.cancel();
      _trailerImdb = imdb;
      _suppressed = false;
      widget.trailerLoading.value = false;
      // Publishing null tears the stage's player down (the setter writes the
      // shared notifier — no setState, the rail doesn't render the video).
      _streams = null;
    }
    if (_suppressed || !_trailerEnabled) return;
    if (imdb == null) return; // need an imdbId to look up / play a trailer
    if (_streams != null) return; // already playing this title
    if (_trailerDwell?.isActive ?? false) return; // resolve already pending
    // Two dwells, both reset by arrowing: a short one flips the pill on for a
    // rested card that already has a known trailer id (prompt feedback), and the
    // resolve dwell fires the actual fetch/play. The pill stays up from the first
    // through to playback.
    _pillDwell = Timer(_pillDwellDelay, () {
      if (mounted &&
          !_suppressed &&
          _shown?.imdbId == imdb &&
          (_shown?.trailerYtId?.isNotEmpty ?? false)) {
        widget.trailerLoading.value = true;
      }
    });
    _trailerDwell = Timer(_trailerDwellDelay, () => _resolveAndPlay(imdb));
  }

  /// The card has rested. Surface the loading pill IMMEDIATELY — before the
  /// /meta id lookup and before the stream resolve — so it's up for the whole
  /// search, exactly like the Home hero (which flips its pill on the moment the
  /// attempt commits, not just before frames). Every failure exit clears it;
  /// success hands off to the stage, which drops it once frames land.
  Future<void> _resolveAndPlay(String imdb) async {
    // Moved on / suppressed: whoever caused it already reset the pill (and, if
    // the user browsed on, the new title now owns it) — don't touch it.
    if (!mounted || _suppressed || _shown?.imdbId != imdb) return;
    // A modal/sheet the route observer can't see covered us AFTER the pill dwell
    // turned the spinner on: clear it, since this path arms no watchdog and
    // nothing else would.
    if (ModalRoute.of(context)?.isCurrent != true) {
      widget.trailerLoading.value = false;
      return;
    }

    widget.trailerLoading.value = true; // searching → pill up NOW
    // Failsafe: bound the spinner if a stream resolves yet never starts (dead
    // URL fires no callback). Cancelled on the next title change, so it can
    // never clear a later title's pill.
    _loadingWatchdog?.cancel();
    _loadingWatchdog = Timer(const Duration(seconds: 15), () {
      if (mounted) widget.trailerLoading.value = false;
    });

    bool stale() => !mounted || _suppressed || _shown?.imdbId != imdb;
    void fail() {
      if (mounted && _shown?.imdbId == imdb) widget.trailerLoading.value = false;
    }

    // Trailer id: from the item when the catalog carries it, else the /meta
    // details (the same cached fetch the rail's enrichment uses).
    String? ytId = _shown?.trailerYtId;
    if (ytId == null || ytId.isEmpty) {
      try {
        final full = await _stremio.fetchMetaDetails(
          imdbId: imdb,
          type: _shown?.type ?? 'movie',
        );
        ytId = full?.trailerYtId;
      } catch (_) {
        return fail();
      }
    }
    if (stale()) return; // moved on — the new title owns the pill now
    if (ytId == null || ytId.isEmpty) return fail(); // no trailer for this title
    // Ambient rail backdrop: resolve at a low cap (small box, weak TV).
    final streams = await YoutubeService.resolveStreams(
      ytId,
      maxHeightOverride: YoutubeService.ambientTrailerMaxHeight,
    );
    if (stale()) return;
    if (streams == null || !streams.hasPlayable) return fail();
    // Publish — the stage mounts the player; the pill stays up until the stage
    // reports its first frames (which drops loading).
    _streams = streams;
  }

  /// Real playback is launching (possibly a native TV player that never pushes a
  /// Flutter route the backdrop could observe) — suppress and release the trailer
  /// now so the scarce hardware decoder is free before the player claims it, and
  /// stays free (no in-flight resolve or late re-arm sneaks a decoder back in)
  /// until we return.
  void _onPlayerLaunch() {
    _suppressed = true;
    _trailerDwell?.cancel();
    _pillDwell?.cancel();
    _loadingWatchdog?.cancel();
    widget.trailerLoading.value = false;
    _streams = null;
  }

  /// Keep the list item's own fields when present (its poster/name are the ones
  /// the grid is showing); backfill everything else from the enriched meta.
  StremioMeta _merge(StremioMeta base, StremioMeta enr) => StremioMeta(
        id: base.id,
        imdbId: base.imdbId ?? enr.imdbId,
        type: base.type,
        name: base.name.isNotEmpty ? base.name : enr.name,
        poster: base.poster ?? enr.poster,
        background: base.background ?? enr.background,
        description: (base.description?.isNotEmpty ?? false)
            ? base.description
            : enr.description,
        year: base.year ?? enr.year,
        imdbRating: base.imdbRating ?? enr.imdbRating,
        genres: (base.genres?.isNotEmpty ?? false) ? base.genres : enr.genres,
        runtime: base.runtime ?? enr.runtime,
        sourceAddon: base.sourceAddon ?? enr.sourceAddon,
        trailerYtId: base.trailerYtId ?? enr.trailerYtId,
        logo: base.logo ?? enr.logo,
      );

  @override
  Widget build(BuildContext context) {
    final item = _shown;
    // No panel, no border: the rail is an open glass column floating on the
    // host's full-frame stage (the stage's veils supply the legibility, the
    // host draws the backdrop). Swaps stay instant — no crossfade, a saveLayer
    // over the whole rail on every DPAD move is the exact jank the grid avoids
    // by disabling its own per-poster fade on TV.
    return item == null ? const _RailEmpty() : _RailContent(item: item);
  }
}

class _RailContent extends StatelessWidget {
  final StremioMeta item;

  const _RailContent({required this.item});

  @override
  Widget build(BuildContext context) {
    final rating = item.imdbRating;
    final runtime = item.runtimeDisplay;
    final year = item.year;
    final genres = item.genres ?? const [];

    // year · runtime, dot-separated (the type gets its own badge, the rating
    // its own IMDb chip — mock grammar).
    final facts = <String>[
      if (year != null && year.isNotEmpty) year,
      if (runtime != null && runtime.isNotEmpty) runtime,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sit the identity block in the stage art's clear zone — matches the
          // mock's ~1/5-down anchor on a 540 canvas without starving short
          // canvases (fixed spacer, not proportional: the column never jumps).
          const SizedBox(height: 92),
          _RailTitleArt(item: item),
          const SizedBox(height: 18),
          Wrap(
            spacing: 9,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TypeBadge(item.type == 'series' ? 'SERIES' : 'MOVIE'),
              for (var i = 0; i < facts.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6B6386),
                      shape: BoxShape.circle,
                    ),
                  ),
                _MetaText(facts[i]),
              ],
              if (rating != null) _ImdbChip(rating),
            ],
          ),
          const SizedBox(height: 16),
          // Plot + genres. The genre chips follow the plot directly (mock), and
          // the plot is capped to a readable block rather than filling the
          // column — the stage art behind is part of the design now, not dead
          // space to cover. The ClipRect still guarantees no overflow stripes
          // on short canvases.
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, cons) {
                  final hasGenres = genres.isNotEmpty;
                  const genreGap = 16.0;
                  const genreMaxHeight = 68.0; // ~two wrapped chip rows
                  final reserve = hasGenres ? genreGap + genreMaxHeight : 0.0;
                  // Pad the per-line estimate above the real 20.25px so rounding
                  // never pushes the text past its budget. Guard infinity too —
                  // floor() on it throws.
                  const lineHeight = 21.5;
                  final avail =
                      cons.maxHeight.isFinite ? cons.maxHeight : 400.0;
                  final descLines = ((avail - reserve) / lineHeight)
                      .floor()
                      .clamp(1, 6);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.description != null &&
                          item.description!.isNotEmpty)
                        Flexible(
                          child: Text(
                            item.description!,
                            maxLines: descLines,
                            overflow: TextOverflow.ellipsis,
                            // Shadow: legibility over the trailer, which plays
                            // under a much thinner veil (~.35) than the browse
                            // tint — invisible against the dark browse state.
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13.5,
                              height: 1.5,
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 8),
                              ],
                            ),
                          ),
                        )
                      else
                        Text(
                          'No description available.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      if (hasGenres) ...[
                        const SizedBox(height: genreGap),
                        ClipRect(
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxHeight: genreMaxHeight),
                            child: Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                for (final g in genres.take(6)) _GenreChip(g),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rail's title, IMAGE-FIRST — the same contract as the Home hero's title
/// art: the studio title-treatment when a logo URL is known (from the item, or
/// derived from the IMDb id — metahub serves `/logo/medium/{tt}/img` for
/// almost every title), the plain text title only when art is genuinely
/// unavailable. While art is in flight the slot holds EMPTY, never the text —
/// text-flashing-then-swapping reads as a glitch. Failed URLs are remembered
/// for the session so logo-less titles show text immediately on revisit.
class _RailTitleArt extends StatefulWidget {
  final StremioMeta item;

  const _RailTitleArt({required this.item});

  @override
  State<_RailTitleArt> createState() => _RailTitleArtState();
}

class _RailTitleArtState extends State<_RailTitleArt> {
  /// Session-wide memo of logo URLs that 404'd.
  static final Set<String> _deadLogoUrls = <String>{};

  String? get _logoUrl {
    final item = widget.item;
    if (item.logo?.isNotEmpty == true) return item.logo;
    final imdb =
        item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (imdb == null) return null;
    return 'https://images.metahub.space/logo/medium/$imdb/img';
  }

  @override
  Widget build(BuildContext context) {
    final logo = _logoUrl;
    if (logo == null || _deadLogoUrls.contains(logo)) {
      return SizedBox(
        height: 68,
        width: double.infinity,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            widget.item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.1,
              shadows: [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Fixed-height slot, left-aligned: successive titles keep one anchor as
    // DPAD focus flies. Empty placeholder AND empty errorWidget — the slot
    // stays blank until art lands; a failure flips (via the memo + rebuild) to
    // the full text path above, not a cramped in-slot fallback.
    return SizedBox(
      height: 68,
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: CachedNetworkImage(
            imageUrl: logo,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            memCacheWidth: 480,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
            errorListener: (_) {
              _deadLogoUrls.add(logo);
              if (mounted) setState(() {});
            },
          ),
        ),
      ),
    );
  }
}

/// Hairline-outlined type capsule — "SERIES" / "MOVIE" (mock grammar).
class _TypeBadge extends StatelessWidget {
  final String label;
  const _TypeBadge(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      );
}

/// The gold IMDb mark + rating (mock grammar) — replaces the generic ★.
class _ImdbChip extends StatelessWidget {
  final double rating;
  const _ImdbChip(this.rating);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF5C518),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'IMDb',
              style: TextStyle(
                color: Color(0xFF161616),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}

class _MetaText extends StatelessWidget {
  final String text;
  const _MetaText(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
        ),
      );
}

class _GenreChip extends StatelessWidget {
  final String label;
  const _GenreChip(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: kSeeAllAccent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kSeeAllAccentBorder, width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: kSeeAllAccent2,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _RailEmpty extends StatelessWidget {
  const _RailEmpty();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.travel_explore_rounded,
                  size: 40, color: HomeTheme.focusGold.withValues(alpha: 0.55)),
              const SizedBox(height: 14),
              Text(
                'Browse to preview',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Highlight a title on the right to see its backdrop, plot and details here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
}
