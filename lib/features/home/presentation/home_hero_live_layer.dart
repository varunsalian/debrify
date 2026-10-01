import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/hero_trailer_backdrop.dart';
import 'home_card_style.dart';
import 'home_hero_surface.dart';

/// The boxed hero video region's IPTV-favourite variant: plays a focused
/// favourite channel's live stream in the SAME right-anchored region
/// the trailer layer uses for catalog trailers, via
/// [HeroTrailerBackdrop]'s `live: true` mode — the exact mechanism the IPTV
/// page's own inline channel preview uses
/// (IptvResultsView._buildPreviewStage). Painted as a sibling ABOVE
/// the trailer layer in the host's Stack and shrinks to nothing when no
/// IPTV favourite has focus, so the catalog trailer shows through unchanged;
/// the two are mutually exclusive in practice because
/// the selecting view tears the catalog trailer down the
/// moment a live feed starts.
///
/// While the stream resolves/buffers, the hero spotlight's idle key art (the
/// previously-focused catalog title's Cinemeta poster) still sits BENEATH
/// this layer — so as soon as [channel] is non-null this paints an opaque
/// floor of the channel's OWN art ([_HeroLiveFloor]) rather than leaving that
/// gap for the stale poster to show through.
class HomeHeroLiveLayer extends StatefulWidget {
  final ValueListenable<IptvChannel?> channel;
  final ValueListenable<String?> streamUrl;
  final double heroHeight;
  final double volume;
  final bool Function(String channelKey) isAddonChannel;
  final ValueChanged<bool>? onPlayingChanged;
  final VoidCallback? onPlaybackFailed;

  /// CANVAS mode — same contract as the trailer layer full-bleed option: the region
  /// (and the underlay hole with it) becomes the whole board and the boxed
  /// edge feathers are skipped; the Canvas scrims above carry the lighting.
  final bool fullBleed;

  const HomeHeroLiveLayer({
    super.key,
    required this.channel,
    required this.isAddonChannel,
    required this.streamUrl,
    required this.heroHeight,
    required this.volume,
    this.onPlayingChanged,
    this.onPlaybackFailed,
    this.fullBleed = false,
  });

  @override
  State<HomeHeroLiveLayer> createState() => _HomeHeroLiveLayerState();
}

class _HomeHeroLiveLayerState extends State<HomeHeroLiveLayer> {
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
  void didUpdateWidget(HomeHeroLiveLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.channel, widget.channel)) {
      oldWidget.channel.removeListener(_onChannelChanged);
      widget.channel.addListener(_onChannelChanged);
      _channel = widget.channel.value;
    }
    if (!identical(oldWidget.streamUrl, widget.streamUrl)) {
      oldWidget.streamUrl.removeListener(_onUrlChanged);
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
              : homeHeroTrailerRegionRect(boardW, heroH);
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
  /// the trailer layer region, plus the channel-art floor and a
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
                firstFrameTimeout: widget.isAddonChannel(channel.url)
                    ? const Duration(seconds: 12)
                    : null,
              ),
            ),
          IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: homeHeroTrailerBrightnessLift),
                // Boxed-mode edge melts only — Canvas paints its own constant
                // scrims above this whole layer instead.
                if (!widget.fullBleed) ...[
                  homeHeroEdgeFeather(
                    Alignment.centerLeft,
                    Alignment.centerRight,
                    app.home.bg,
                    homeHeroTrailerVideoFeatherFrac,
                  ),
                  homeHeroEdgeFeather(
                    Alignment.topCenter,
                    Alignment.bottomCenter,
                    app.home.bg,
                    0.10,
                  ),
                  homeHeroEdgeFeather(
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
/// the Home poster card uses for its card, so the region reads as "this channel is
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
/// the trailer loading/ambient pills, with a red dot (matching
/// the Home poster card's own LIVE badge) instead of the trailer pills' amber one.
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
              color: homeCardProgressRed,
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
