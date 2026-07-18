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

  const DiscoverDetailRail({
    super.key,
    required this.item,
    required this.trailerStreams,
    required this.trailerLoading,
    required this.trailerVolume,
    required this.trailerMeta,
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
    if (m != null && cached == null) _scheduleEnrich(m);
    _evaluateTrailer();
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
    final streams = await YoutubeService.resolveStreams(ytId);
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
      );

  @override
  Widget build(BuildContext context) {
    final item = _shown;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kSeeAllBg,
        border: Border(
          right: BorderSide(color: kSeeAllLine, width: 1),
        ),
      ),
      // Swap instantly, no crossfade: a saveLayer over the whole rail on every
      // DPAD move is the exact jank the grid avoids by disabling its own
      // per-poster fade on TV. The backdrop still eases in on its own (once,
      // post-dwell) via CachedNetworkImage's fadeInDuration.
      child: item == null ? const _RailEmpty() : _RailContent(item: item),
    );
  }
}

class _RailContent extends StatelessWidget {
  final StremioMeta item;

  const _RailContent({required this.item});

  @override
  Widget build(BuildContext context) {
    final backdrop = item.background ?? item.poster;
    final rating = item.imdbRating;
    final runtime = item.runtimeDisplay;
    final year = item.year;
    final genres = item.genres ?? const [];

    final meta = <Widget>[
      if (year != null && year.isNotEmpty) _MetaText(year),
      if (rating != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFACC15)),
          const SizedBox(width: 3),
          _MetaText(rating.toStringAsFixed(1)),
        ]),
      if (runtime != null) _MetaText(runtime),
      _MetaText(item.type == 'series' ? 'Series' : 'Movie'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Backdrop stage.
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop != null && backdrop.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: backdrop,
                      fit: BoxFit.cover,
                      memCacheWidth: 640,
                      fadeInDuration: const Duration(milliseconds: 200),
                      placeholder: (_, __) => const _BackdropFallback(),
                      errorWidget: (_, __, ___) => const _BackdropFallback(),
                    )
                  else
                    const _BackdropFallback(),
                  // The trailer itself is rendered by the full-screen
                  // DiscoverTrailerStage layered over the two-pane (so it can
                  // grow to a fullscreen takeover). It sits exactly over this box
                  // while ambient — this still shows through until its video
                  // fades in, then it takes over the box.
                  // Bottom fade so the backdrop marries into the panel.
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xE60D0B1A)],
                            stops: [0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          // Metadata row, dot-separated.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < meta.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6B6386),
                      shape: BoxShape.circle,
                    ),
                  ),
                meta[i],
              ],
            ],
          ),
          const SizedBox(height: 14),
          // Plot + genres fill the remaining height. The genre block is bottom
          // content but the lower priority, so it gets a fixed, clipped budget
          // (two wrapped rows) and the plot's line count is computed from
          // whatever's left — so the chips are never shoved under the fold and
          // the plot ellipsis-truncates to fit. The outer ClipRect guarantees no
          // overflow stripes even if font metrics round a line over budget.
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
                      .clamp(1, 40);
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
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13.5,
                              height: 1.5,
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

class _BackdropFallback extends StatelessWidget {
  const _BackdropFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kSeeAllPanel2, kSeeAllBg],
          ),
        ),
        child: Center(
          child: Icon(Icons.movie_rounded, size: 34, color: Color(0x33FFFFFF)),
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
