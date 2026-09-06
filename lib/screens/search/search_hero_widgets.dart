part of '../search_screen.dart';



/// Fraction for the LIVE video's left-edge melt — deliberately about half the
/// idle art's `_heroTrailerFeatherFrac` in `hero_spotlight.dart`. The balance (user-tuned): the old
/// full-width feathers read as bleed over the picture, but fully crisp edges
/// read as a legacy boxed player — a slim melt keeps the picture essentially
/// untouched while its edges still dissolve into the stage.
const double _heroTrailerVideoFeatherFrac = 0.16;

/// Slight brightness lift painted flat over the live ambient trailer —
/// trailers are graded dark and the ambient region has no other light on it.
/// Low-alpha white: lifts the mids/shadows a touch without visibly milking
/// the highlights. Works in BOTH engine modes: over the underlay hole it
/// alpha-blends onto the native video via the system compositor; over the
/// texture path it's an ordinary fill. Tune the alpha to taste (0 = off).
const Color _heroTrailerBrightnessLift = Color(0x14FFFFFF);


/// Full-board ambient trailer layer (TV Home board only). Sits ABOVE the hero +
/// rows as an [IgnorePointer] overlay and paints the trailer into a right-
/// anchored REGION of the hero band (see [heroTrailerRegionRect]) — a live,
/// near-untouched picture beside the title, its edges slim-feathered into the
/// darkened stage. The region fades in
/// when a trailer starts resolving and out when it clears; the title/backdrop
/// underneath stay put (no crossfade-to-fullscreen), so the hero keeps its
/// identity. [HeroTrailerBackdrop] cover-fills the region (clipped), and a
/// [GlobalKey] pins the player element across rebuilds; it's replaced per URL so
/// each title still spins a fresh engine.
///
/// Any hero change tears the trailer down (the host nulls the listenable → the
/// video unmounts and the region fades out). A trailer that stops for content
/// playback drops on its own via [HeroTrailerBackdrop.onPlayingChanged](false).
/// The Spotlight shell's floating search button — a frosted circle over the
/// hero, mirroring the approved mock. Deliberately plain Material ink-free
/// (the board underneath is a photograph; a splash reads as damage).
class _SpotlightSearchButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SpotlightSearchButton({required this.onTap});

  /// The button's geometry, named so the trailer layer's status chips can
  /// clear it by DERIVATION — a bare 66 over there would silently regress
  /// the clipped-"AMBIE…" overlap the moment this button moved or grew.
  static const double rightInset = 14;
  static const double diameter = 40;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x8C1E1E20),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: const Icon(
              Icons.search_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroTrailerLayer extends StatefulWidget {
  final ValueListenable<YoutubeResolvedStreams?> trailer;

  /// The hero spotlight's height — sets the region's height (see
  /// [heroTrailerRegionRect]).
  final double heroHeight;

  /// Ambient volume 0–100 (0 = play silently).
  final double volume;

  /// Host "a trailer is resolving/buffering" flag — the region fades in on it
  /// (so it's already there when frames land) and hosts the "Trailer" pill.
  final ValueListenable<bool> loading;

  /// Relayed [HeroTrailerBackdrop.onPlayingChanged] (host pill + lights-off
  /// veils).
  final ValueChanged<bool>? onPlayingChanged;

  /// Retained (unused) takeover hook — the fullscreen promote is gone in the
  /// boxed layout, but the host still wires a notifier; kept for compatibility.
  final ValueNotifier<double>? takeover;

  /// CANVAS mode: the region is the WHOLE board — the underlay hole (which
  /// simply follows this widget's laid-out rect) becomes the full canvas —
  /// and the boxed edge feathers are skipped; the Canvas stage paints its own
  /// scrims ABOVE this layer instead.
  final bool fullBleed;

  /// The HOST's TV verdict (probe-augmented — see main.dart), not
  /// `PlatformUtil.isTelevision`: the two can disagree on an Android TV whose
  /// warm-up probe failed, and the chip corner must follow the same authority
  /// as the layout it sits in.
  final bool isTelevision;

  const _HeroTrailerLayer({
    required this.trailer,
    required this.heroHeight,
    required this.volume,
    required this.loading,
    required this.isTelevision,
    this.onPlayingChanged,
    this.takeover,
    this.fullBleed = false,
  });

  @override
  State<_HeroTrailerLayer> createState() => _HeroTrailerLayerState();
}

class _HeroTrailerLayerState extends State<_HeroTrailerLayer> {
  /// Pins the backdrop's element so its engine/texture survive rebuilds.
  /// Replaced per trailer URL so each title still gets a fresh engine.
  GlobalKey _backdropKey = GlobalKey();
  String? _backdropUrl;

  /// The streams actually being rendered — mirrors `widget.trailer`. Held in
  /// state so a `setState` drives the video mount/unmount as titles change.
  YoutubeResolvedStreams? _held;

  /// True once the video is actually producing frames (not merely resolving /
  /// buffering). The edge-feathers fade in ONLY on this — so while a trailer
  /// loads the poster shows through the region untouched, and the tint dissolve
  /// appears together with the moving picture, never over a still. Reset on any
  /// trailer change so a new title starts clean.
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _held = widget.trailer.value;
    widget.trailer.addListener(_onTrailerChanged);
  }

  @override
  void didUpdateWidget(_HeroTrailerLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.trailer, widget.trailer)) {
      old.trailer.removeListener(_onTrailerChanged);
      widget.trailer.addListener(_onTrailerChanged);
      // We render from _held (not the listenable directly), so re-sync it to
      // the new notifier's current value.
      _held = widget.trailer.value;
      _playing = false;
    }
  }

  @override
  void dispose() {
    widget.trailer.removeListener(_onTrailerChanged);
    super.dispose();
  }

  void _onTrailerChanged() {
    if (!mounted) return;
    // A new trailer arrives (or a null drops it). Either way the feathers go
    // back to hidden until THIS video reports frames — the new poster shows
    // through cleanly meanwhile.
    setState(() {
      _held = widget.trailer.value;
      _playing = false;
    });
  }

  void _onPlaying(bool playing) {
    // Relay to the host — drives the colour bleed under the rows and clears the
    // "Trailer" pill once frames are up.
    widget.onPlayingChanged?.call(playing);
    // Drive the feathers locally: they appear with the picture, not before.
    if (_playing != playing && mounted) setState(() => _playing = playing);
  }

  @override
  Widget build(BuildContext context) {
    final streams = _held;
    if (streams != null &&
        streams.hasPlayable &&
        streams.playUrl != _backdropUrl) {
      _backdropUrl = streams.playUrl;
      _backdropKey = GlobalKey();
    }
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boardH = constraints.maxHeight;
          final boardW = constraints.maxWidth;
          if (!boardH.isFinite ||
              boardH <= 0 ||
              !boardW.isFinite ||
              boardW <= 0) {
            return const SizedBox.shrink();
          }
          final heroH = widget.heroHeight.clamp(0.0, boardH);
          final region = widget.fullBleed
              ? (Offset.zero & Size(boardW, boardH))
              : heroTrailerRegionRect(boardW, heroH);
          if (region == null) return const SizedBox.shrink();

          final hasVideo = streams != null && streams.hasPlayable;
          // Listening to `loading` keeps the region (and its pill) up through
          // the resolve gap so frames land inside it, not a pop.
          return ValueListenableBuilder<bool>(
            valueListenable: widget.loading,
            builder: (context, loading, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // No region-level fade wrapper: it was redundant (`show`
                  // false implies streams == null — the video unmounts
                  // instantly regardless — and the feathers/pill carry their
                  // own fades), and the underlay trailer's punch-through hole
                  // must not sit under an Opacity (its saveLayer would break
                  // the BlendMode.clear against the translucent surface).
                  Positioned.fromRect(
                    rect: region,
                    child: _buildRegion(
                      hasVideo ? streams : null,
                      loading,
                      _playing,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// The trailer region — NO frame; the video cover-fills a right-anchored
  /// slab whose edges melt into the stage via SLIM neutral feathers (see
  /// [_heroTrailerVideoFeatherFrac] for the tuned balance: heavy feathers
  /// read as bleed, none at all read as a legacy boxed player). The right
  /// edge bleeds off screen.
  ///
  /// Under the feathers sits [_heroTrailerBrightnessLift] — a single flat
  /// low-alpha white fill that lifts the ambient video slightly (trailers
  /// are graded dark; a small lift keeps the region alive).
  ///
  /// Weak-TV safe: all overlays are constant fills/baked gradients (no
  /// per-frame ShaderMask / saveLayer), and in underlay mode they composite
  /// over the punch-through hole onto the native video. The video keeps its
  /// own RepaintBoundary so its texture updates never repaint the overlays
  /// or pill.
  ///
  /// [playing] gates the overlays: while the trailer only resolves/buffers
  /// the poster shows through the region untouched, then they fade in with
  /// the picture.
  Widget _buildRegion(
    YoutubeResolvedStreams? streams,
    bool loading,
    bool playing,
  ) {
    final app = AppThemeScope.of(context);
    return ClipRect(
      // Clip the cover-crop so the scaled-up video can't spill left over the
      // title text; the right side simply bleeds off the screen edge.
      child: Stack(
        fit: StackFit.expand,
        children: [
          // imageUrl null: the hero backdrop shows through the region while
          // resolving, and the video fades in over it — no black plate.
          if (streams != null)
            RepaintBoundary(
              child: HeroTrailerBackdrop(
                key: _backdropKey,
                imageUrl: null,
                videoUrl: streams.playUrl,
                audioUrl: streams.audioUrl,
                enabled: true,
                imageBlurSigma: 0,
                videoBlurSigma: 0,
                startDelay: const Duration(milliseconds: 300),
                ambientVolume: widget.volume,
                onPlayingChanged: _onPlaying,
              ),
            ),
          // Overlays on the picture, gated on [playing] so the poster
          // underneath is never touched while the trailer resolves:
          // the flat brightness lift first, then the SLIM neutral edge
          // feathers OVER it — so the melt still lands on the stage's true
          // near-black, not a lifted one.
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: playing ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOut,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: _heroTrailerBrightnessLift),
                  // Boxed-mode edge melts only — Canvas paints its own
                  // constant scrims above this whole layer instead.
                  if (!widget.fullBleed) ...[
                    // Left: melt into the darkened text zone.
                    heroEdgeFeather(
                      Alignment.centerLeft,
                      Alignment.centerRight,
                      app.home.bg,
                      _heroTrailerVideoFeatherFrac,
                    ),
                    // Top: soften the upper edge into the hero.
                    heroEdgeFeather(
                      Alignment.topCenter,
                      Alignment.bottomCenter,
                      app.home.bg,
                      0.10,
                    ),
                    // Bottom: melt down into the darkened rows.
                    heroEdgeFeather(
                      Alignment.bottomCenter,
                      Alignment.topCenter,
                      app.home.bg,
                      0.20,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: _chipTop(context),
            right: _chipRight,
            child: HeroTrailerLoadingPill(visible: loading),
          ),
          // Once frames are up the loading pill yields to the AMBIENT chip —
          // a quiet state affordance so the motion reads as intentional, not
          // a stray video. Same corner, so the two hand over in place.
          Positioned(
            top: _chipTop(context),
            right: _chipRight,
            child: HeroAmbientChip(visible: playing && !loading),
          ),
        ],
      ),
    );
  }

  /// The status corner, per input. TV keeps the shipped 16/22 — it sits
  /// inside a SafeArea and owns the whole corner. The touch Spotlight shell
  /// (phone AND tablet — both float the search button over a full-bleed
  /// board) is `SafeArea(top: false)` — the shipped corner put the chip both
  /// UNDER the status bar and UNDER that button (the clipped "AMBIE…").
  /// Cleared to the button's left, vertically centred on it.
  double _chipTop(BuildContext context) =>
      widget.isTelevision ? 16.0 : MediaQuery.viewPaddingOf(context).top + 16.0;

  double get _chipRight => widget.isTelevision
      ? 22.0
      : _SpotlightSearchButton.rightInset +
            _SpotlightSearchButton.diameter +
            12;
}

/// Live IPTV preview drawn directly inside the active Spotlight card.
///
/// [SpotlightBoard] mounts this only for the pointer-hovered card on desktop
/// or the DPAD-focused card on TV, so a shelf never opens more than one stream
/// while the user browses. Stremio-backed channels retain the same candidate
/// ladder as the full IPTV preview stage; plain M3U/Xtream channels open their
/// declared URL directly. Its audio follows the user's Home ambient-audio
/// setting, so the channel is audible without overriding an intentional mute.
class SpotlightIptvCardPreview extends StatefulWidget {
  final IptvChannel channel;
  final double ambientVolume;

  const SpotlightIptvCardPreview({
    super.key,
    required this.channel,
    required this.ambientVolume,
  });

  @override
  State<SpotlightIptvCardPreview> createState() =>
      _SpotlightIptvCardPreviewState();
}

class _SpotlightIptvCardPreviewState extends State<SpotlightIptvCardPreview> {
  String? _streamUrl;
  List<String>? _candidates;
  int _resolveTicket = 0;

  @override
  void initState() {
    super.initState();
    _resolve(notify: false);
  }

  @override
  void didUpdateWidget(SpotlightIptvCardPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A shelf can reorder/reload while its active card's State is retained.
    // Never carry the previous channel's stream (or a late candidate resolve)
    // into the card that inherited that State slot.
    if (!identical(oldWidget.channel, widget.channel)) _resolve();
  }

  @override
  void dispose() {
    _resolveTicket++;
    super.dispose();
  }

  void _resolve({bool notify = true}) {
    final channel = widget.channel;
    final ticket = ++_resolveTicket;
    _candidates = null;
    if (channel.contentType == 'series') {
      _setStreamUrl(null, notify: notify);
      return;
    }
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) {
      _setStreamUrl(channel.url, notify: notify);
      return;
    }

    _setStreamUrl(null, notify: notify);
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!mounted || ticket != _resolveTicket || found.isEmpty) return;
      _candidates = [for (final candidate in found) candidate.url];
      _setStreamUrl(_candidates!.first);
    });
  }

  void _setStreamUrl(String? value, {bool notify = true}) {
    if (_streamUrl == value) return;
    if (!notify) {
      _streamUrl = value;
      return;
    }
    setState(() => _streamUrl = value);
  }

  void _onPlaybackFailed() {
    final candidates = _candidates;
    final current = _streamUrl;
    if (candidates == null || current == null) return;
    final next = candidates.indexOf(current) + 1;
    if (next <= 0 || next >= candidates.length) {
      StremioIptvService.instance.invalidate(widget.channel.url);
      _setStreamUrl(null);
      return;
    }
    _setStreamUrl(candidates[next]);
  }

  @override
  Widget build(BuildContext context) {
    final url = _streamUrl;
    if (url == null) return const SizedBox.expand();
    final channel = widget.channel;
    return RepaintBoundary(
      child: HeroTrailerBackdrop(
        // A candidate-ladder step needs a fresh player; retaining a dead
        // engine would leave the logo visible forever after its replacement
        // URL was selected.
        key: ValueKey('spotlight-iptv-card-${channel.url}-$url'),
        imageUrl: null,
        videoUrl: url,
        enabled: true,
        live: true,
        httpHeaders: channel.playbackHeaders,
        imageBlurSigma: 0,
        videoBlurSigma: 0,
        // The short dwell filters a pointer sweep / held DPAD move without
        // making a deliberate card preview feel late.
        startDelay: const Duration(milliseconds: 300),
        ambientVolume: widget.ambientVolume,
        onPlaybackFailed: _onPlaybackFailed,
        firstFrameTimeout: StremioIptvService.isStremioChannelUrl(channel.url)
            ? const Duration(seconds: 12)
            : null,
      ),
    );
  }
}

/// The boxed hero video region's IPTV-favourite variant: plays a focused
/// favourite channel's live stream in the SAME right-anchored region
/// [_HeroTrailerLayer] uses for catalog trailers, via
/// [HeroTrailerBackdrop]'s `live: true` mode — the exact mechanism the IPTV
/// page's own inline channel preview uses
/// (IptvResultsView._buildPreviewStage). Painted as a sibling ABOVE
/// [_HeroTrailerLayer] in the host's Stack and shrinks to nothing when no
/// IPTV favourite has focus, so the catalog trailer shows through unchanged;
/// the two are mutually exclusive in practice because
/// [_SearchScreenState._setHeroLiveIptv] tears the catalog trailer down the
/// moment a live feed starts.
///
/// While the stream resolves/buffers, [HeroSpotlight]'s idle key art (the
/// previously-focused catalog title's Cinemeta poster) still sits BENEATH
/// this layer — so as soon as [channel] is non-null this paints an opaque
/// floor of the channel's OWN art ([_HeroLiveFloor]) rather than leaving that
/// gap for the stale poster to show through.
class _HeroLiveLayer extends StatefulWidget {
  final ValueListenable<IptvChannel?> channel;
  final ValueListenable<String?> streamUrl;
  final double heroHeight;
  final double volume;
  final ValueChanged<bool>? onPlayingChanged;
  final VoidCallback? onPlaybackFailed;

  /// CANVAS mode — same contract as [_HeroTrailerLayer.fullBleed]: the region
  /// (and the underlay hole with it) becomes the whole board and the boxed
  /// edge feathers are skipped; the Canvas scrims above carry the lighting.
  final bool fullBleed;

  const _HeroLiveLayer({
    required this.channel,
    required this.streamUrl,
    required this.heroHeight,
    required this.volume,
    this.onPlayingChanged,
    this.onPlaybackFailed,
    this.fullBleed = false,
  });

  @override
  State<_HeroLiveLayer> createState() => _HeroLiveLayerState();
}

class _HeroLiveLayerState extends State<_HeroLiveLayer> {
  /// Pins the live backdrop's element so its engine/texture survive rebuilds;
  /// replaced per URL (channel switch, or a candidate-ladder step-down) so
  /// each stream still gets a fresh engine.
  GlobalKey _backdropKey = GlobalKey();
  String? _backdropUrl;
  IptvChannel? _channel;
  String? _url;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel.value;
    _url = widget.streamUrl.value;
    widget.channel.addListener(_onChannelChanged);
    widget.streamUrl.addListener(_onUrlChanged);
  }

  @override
  void didUpdateWidget(_HeroLiveLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.channel, widget.channel)) {
      old.channel.removeListener(_onChannelChanged);
      widget.channel.addListener(_onChannelChanged);
      _channel = widget.channel.value;
    }
    if (!identical(old.streamUrl, widget.streamUrl)) {
      old.streamUrl.removeListener(_onUrlChanged);
      widget.streamUrl.addListener(_onUrlChanged);
      _url = widget.streamUrl.value;
      _playing = false;
    }
  }

  @override
  void dispose() {
    widget.channel.removeListener(_onChannelChanged);
    widget.streamUrl.removeListener(_onUrlChanged);
    super.dispose();
  }

  void _onChannelChanged() {
    if (!mounted) return;
    setState(() => _channel = widget.channel.value);
  }

  void _onUrlChanged() {
    if (!mounted) return;
    setState(() {
      _url = widget.streamUrl.value;
      _playing = false;
    });
  }

  void _onPlaying(bool playing) {
    widget.onPlayingChanged?.call(playing);
    if (_playing != playing && mounted) setState(() => _playing = playing);
  }

  @override
  Widget build(BuildContext context) {
    final channel = _channel;
    if (channel == null) return const SizedBox.shrink();
    final url = _url;
    if (url != null && url != _backdropUrl) {
      _backdropUrl = url;
      _backdropKey = GlobalKey();
    }
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boardH = constraints.maxHeight;
          final boardW = constraints.maxWidth;
          if (!boardH.isFinite ||
              boardH <= 0 ||
              !boardW.isFinite ||
              boardW <= 0) {
            return const SizedBox.shrink();
          }
          final heroH = widget.heroHeight.clamp(0.0, boardH);
          final region = widget.fullBleed
              ? (Offset.zero & Size(boardW, boardH))
              : heroTrailerRegionRect(boardW, heroH);
          if (region == null) return const SizedBox.shrink();
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fromRect(
                rect: region,
                child: _buildRegion(channel, url),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Same clip/feather/brightness-lift treatment as
  /// [_HeroTrailerLayerState._buildRegion], plus the channel-art floor and a
  /// LIVE/TUNING status chip in place of the trailer's TRAILER/AMBIENT pills.
  /// Unlike the catalog trailer (whose feathers only appear once playing —
  /// its OWN idle art beneath already carries them), the melt here is
  /// unconditional: the floor is opaque from the first frame this builds, so
  /// there's always something to feather.
  Widget _buildRegion(IptvChannel channel, String? url) {
    final app = AppThemeScope.of(context);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Opaque floor: the channel's own art, so the previously-focused
          // catalog title's poster never shows through the resolve/buffer
          // gap. Crossfades out once real frames land.
          AnimatedOpacity(
            opacity: _playing ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOut,
            child: _HeroLiveFloor(channel: channel),
          ),
          if (url != null)
            RepaintBoundary(
              child: HeroTrailerBackdrop(
                key: _backdropKey,
                imageUrl: null,
                videoUrl: url,
                enabled: true,
                live: true,
                imageBlurSigma: 0,
                videoBlurSigma: 0,
                startDelay: const Duration(milliseconds: 300),
                ambientVolume: widget.volume,
                onPlayingChanged: _onPlaying,
                onPlaybackFailed: widget.onPlaybackFailed,
                // Only a Stremio-addon favourite has a ladder to fall back
                // on — bound its wait so a dead candidate doesn't stall
                // forever. A plain M3U/Xtream favourite has just the one
                // URL, so give it an unbounded wait instead of abandoning an
                // otherwise-valid but slow-to-buffer stream (matches
                // IptvResultsView._buildPreviewStage's own timeout choice).
                firstFrameTimeout:
                    StremioIptvService.isStremioChannelUrl(channel.url)
                    ? const Duration(seconds: 12)
                    : null,
              ),
            ),
          IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: _heroTrailerBrightnessLift),
                // Boxed-mode edge melts only — Canvas paints its own constant
                // scrims above this whole layer instead.
                if (!widget.fullBleed) ...[
                  heroEdgeFeather(
                    Alignment.centerLeft,
                    Alignment.centerRight,
                    app.home.bg,
                    _heroTrailerVideoFeatherFrac,
                  ),
                  heroEdgeFeather(
                    Alignment.topCenter,
                    Alignment.bottomCenter,
                    app.home.bg,
                    0.10,
                  ),
                  heroEdgeFeather(
                    Alignment.bottomCenter,
                    Alignment.topCenter,
                    app.home.bg,
                    0.20,
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            top: 16,
            right: 22,
            child: _HeroLiveChip(playing: _playing),
          ),
        ],
      ),
    );
  }
}

/// The IPTV favourite's own art, filling the boxed region while its stream
/// resolves/buffers (and behind it, briefly, while frames settle) — the
/// channel's logo over the same purple gradient + live-tv glyph fallback
/// [ArtPoster] uses for its card, so the region reads as "this channel is
/// tuning in" rather than an unrelated leftover poster.
class _HeroLiveFloor extends StatelessWidget {
  final IptvChannel channel;

  const _HeroLiveFloor({required this.channel});

  @override
  Widget build(BuildContext context) {
    final logo = channel.logoUrl;
    final hasLogo = logo != null && logo.isNotEmpty;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1D5C), Color(0xFF1A1440), Color(0xFF0D0B1A)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Center(
        child: hasLogo
            ? Padding(
                padding: const EdgeInsets.all(56),
                child: CachedNetworkImage(
                  imageUrl: logo,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const _HeroLiveGlyph(),
                ),
              )
            : const _HeroLiveGlyph(),
      ),
    );
  }
}

class _HeroLiveGlyph extends StatelessWidget {
  const _HeroLiveGlyph();

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Icon(
      Icons.live_tv_rounded,
      size: 64,
      color: app.fade(app.home.chromeAccent, 0.85),
    );
  }
}

/// Small "LIVE"/"TUNING" status pill for the boxed hero region while an IPTV
/// favourite plays there — same glass-capsule language as
/// [HeroTrailerLoadingPill]/[HeroAmbientChip], with a red dot (matching
/// [ArtPoster]'s own LIVE badge) instead of the trailer pills' amber one.
class _HeroLiveChip extends StatelessWidget {
  final bool playing;

  const _HeroLiveChip({required this.playing});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        // Glassy page ink — 0.8 of the opaque bg pins the legacy 0xCC alpha.
        color: app.fade(app.home.bg, 0.8),
        borderRadius: app.shape.brPill,
        border: Border.all(color: app.fade(app.core.tx, 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _kCwProgressRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            playing ? 'LIVE' : 'TUNING',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: app.core.tx,
            ),
          ),
        ],
      ),
    );
  }
}


/// One-shot entrance for a board row: fade in + rise ~10px, started after
/// [delayMs] so consecutive rows stagger. When [play] is false (row mounted
/// long after the board landed, reduced motion, or beyond the first screenful)
/// it renders the child directly with zero overhead. The controller runs once
/// and stays idle after — no sustained per-frame cost.
class _EntranceReveal extends StatefulWidget {
  final Widget child;
  final bool play;
  final int delayMs;

  const _EntranceReveal({
    super.key,
    required this.child,
    required this.play,
    this.delayMs = 0,
  });

  @override
  State<_EntranceReveal> createState() => _EntranceRevealState();
}

class _EntranceRevealState extends State<_EntranceReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _fx;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (widget.play) {
      _fx = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
      if (widget.delayMs == 0) {
        _fx!.forward();
      } else {
        _delay = Timer(Duration(milliseconds: widget.delayMs), () {
          if (mounted) _fx?.forward();
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: land settled immediately.
    if (_fx != null && MediaQuery.of(context).disableAnimations) {
      _delay?.cancel();
      _fx!.value = 1.0;
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _fx?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fx = _fx;
    if (fx == null) return widget.child;
    final curved = CurvedAnimation(parent: fx, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, inner) => Transform.translate(
          offset: Offset(0, 12 * (1 - curved.value)),
          child: inner,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Small pill next to a catalog-row header marking it as Movies / Series / etc.
/// An optional leading [icon] lets a pill carry meaning beyond the label (e.g.
/// a star on the Debrify TV "Favorites" pill).
class _CategoryTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  const _CategoryTag(this.label, {this.icon});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: app.fade(app.home.chromeAccent, 0.16),
        borderRadius: app.shape.br(8),
        border: Border.all(color: app.fade(app.home.chromeAccent, 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: const Color(0xFFB9A9FF)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB9A9FF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a Continue Watching row's entries live — drives the long-press menu's
/// wording, since "remove" means a different write per source (local store,
/// Trakt playback API, Simkl status/session, IPTV watch history).
