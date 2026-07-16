import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_route_observer.dart';
import '../services/main_page_bridge.dart';
import '../utils/platform_util.dart';
import '../utils/tv_keys.dart';
import 'trailer_engine.dart';

/// OTT-style "living backdrop": shows the static blurred [imageUrl] and, when
/// [videoUrl] is supplied and enabled, crossfades to an audible, looping trailer in
/// the same full-bleed slot. Sits *behind* the detail page's content and tint —
/// it is purely decorative and never focusable, so DPAD navigation is unaffected.
///
/// It also **promotes to the foreground in place**: set [foreground] true (the
/// Trailer button) and the *same* player unblurs, unmutes and grows to fullscreen
/// with minimal controls — no second decoder, no re-buffer, no restart. The
/// detail page fades its own content out around it; [onRequestClose] fires when
/// the user dismisses the fullscreen trailer.
///
/// Single-decoder discipline (the whole game on weak TV hardware): the trailer
/// player is paused the instant any route is pushed on top (via [appRouteObserver]
/// → [didPushNext]) — e.g. when real content playback launches — and resumes on
/// return. It also pauses when the app backgrounds, and is always disposed.
class HeroTrailerBackdrop extends StatefulWidget {
  /// Static backdrop shown immediately and whenever no trailer is playing.
  final String? imageUrl;

  /// Video stream to play. Usually a video-only YouTube stream (lightest to
  /// decode); pair it with [audioUrl]. Null → static image only.
  final String? videoUrl;

  /// Separate audio track muxed in at playback, matching the main player's
  /// high-res YouTube path. Null when [videoUrl] is already muxed.
  final String? audioUrl;

  /// Master switch (the settings toggle). When false the trailer never loads.
  final bool enabled;

  /// Bring the trailer to the foreground (fullscreen, unmuted, controls).
  final bool foreground;

  /// Fired when the user dismisses the fullscreen trailer (X / tap-scrim). The
  /// parent should flip [foreground] back to false.
  final VoidCallback? onRequestClose;

  /// Fired (post-frame) when the ambient trailer starts producing frames (true)
  /// or is torn down (false). Lets the parent reflect "trailer playing — tap to
  /// watch" state on its Trailer button.
  final ValueChanged<bool>? onPlayingChanged;

  /// Blur applied to the static image (the app's "one lit surface" wash).
  final double imageBlurSigma;

  /// Blur applied to the *ambient* trailer. Kept light so it reads as motion
  /// while the page's dark tint keeps overlaid text legible. Animates to 0 in
  /// the foreground.
  final double videoBlurSigma;

  /// Delay before the trailer starts, so quickly arrowing between titles doesn't
  /// thrash the decoder and the poster is seen first. Also masks resolve latency.
  final Duration startDelay;

  /// Ambient loop volume (0–100). The default sits a notch below full so the
  /// background trailer plays under the UI rather than over it; 0 = muted
  /// ambient (the Home hero's "trailer sound off" setting). Foreground
  /// promotion always raises to full regardless.
  final double ambientVolume;

  /// Shared-element tag: when set, the static image layer is the destination
  /// Hero for the board poster that opened this page (the poster grows into
  /// this full-bleed backdrop). Only the still image participates — the video
  /// layers never re-parent, so trailer state is untouched by the flight.
  final String? heroTag;

  const HeroTrailerBackdrop({
    super.key,
    required this.imageUrl,
    required this.videoUrl,
    this.audioUrl,
    required this.enabled,
    this.foreground = false,
    this.onRequestClose,
    this.onPlayingChanged,
    this.imageBlurSigma = 42,
    this.videoBlurSigma = 8,
    this.startDelay = const Duration(milliseconds: 1400),
    this.ambientVolume = _defaultAmbientVolume,
    this.heroTag,
  });

  /// See [ambientVolume].
  static const double _defaultAmbientVolume = 75;

  @override
  State<HeroTrailerBackdrop> createState() => HeroTrailerBackdropState();
}

class HeroTrailerBackdropState extends State<HeroTrailerBackdrop>
    with RouteAware, WidgetsBindingObserver, TickerProviderStateMixin {
  /// Foreground (promoted fullscreen) volume — always full; the ambient level
  /// comes from [HeroTrailerBackdrop.ambientVolume].
  static const double _foregroundVolume = 100;

  /// Trailers almost always open on a distributor/rating card — skip past it so
  /// the ambient loop lands on actual footage (re-applied on each loop).
  static const Duration _introSkip = Duration(seconds: 5);

  /// Cap the ExoPlayer render texture (TV only) — the backdrop never needs full
  /// res, and trimming the per-frame GPU upload is what kills the TV stutter.
  static const int _tvTrailerMaxHeight = 720;

  TrailerEngine? _engine;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _errorSub;
  Timer? _startTimer;

  /// Auto-hides the foreground chrome (pause/seek/mute) a few seconds after the
  /// last interaction; a click/tap brings it back.
  Timer? _controlsTimer;

  /// Drives the backdrop → fullscreen transition (0 = ambient, 1 = foreground).
  late final AnimationController _fg;

  /// True once the trailer has produced frames and is playing — drives the
  /// crossfade from image → video.
  bool _videoVisible = false;

  /// A route is covering us (player pushed on top) — hold playback.
  bool _covered = false;

  /// The app is backgrounded — don't start (or resume) playback until resume.
  bool _appPaused = false;

  /// The user explicitly paused the foreground trailer. Resume paths (route
  /// pop, app resume) must respect this instead of blindly calling play().
  bool _pausedByUser = false;

  /// Desktop only: playback moved to an external player app (VLC/mpv/…). No
  /// Flutter route is pushed for those, and window focus is an unreliable
  /// proxy (refocusing the app mid-movie would resume trailer audio over it),
  /// so the ambient trailer stays off for the rest of this page visit.
  bool _stoppedForExternalPlayback = false;

  /// The real content player (movie/series) was launched from this page. Keep
  /// the ambient trailer off for the rest of *this* page visit so it doesn't
  /// resume behind / after the feature — it plays again next time the page is
  /// opened (fresh state resets this). Set from the central
  /// [MainPageBridge.notifyPlayerLaunching] signal, which fires on every launch
  /// path (in-app route, native TV activity, external app).
  bool _stoppedForContentPlayback = false;

  // Foreground control state.
  bool _userMuted = false;
  bool _playing = true;
  bool _controlsVisible = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Seekbar drag in progress — the position stream must not fight the thumb.
  bool _scrubbing = false;

  /// Previous position sample, for loop-restart detection (to re-skip the intro).
  Duration _lastPos = Duration.zero;

  /// Last value handed to [onPlayingChanged]; only re-notify on real changes.
  bool _lastNotifiedPlaying = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  bool get _canPlay =>
      widget.enabled &&
      widget.videoUrl != null &&
      widget.videoUrl!.isNotEmpty &&
      !_reduceMotion &&
      !_stoppedForExternalPlayback &&
      !_stoppedForContentPlayback;

  /// Whether the ambient trailer is live *with frames on screen* and can be
  /// brought forward. Requires [_videoVisible] so promotion never fades the page
  /// out onto a still-buffering (blurred-poster / black) surface — during the
  /// buffer window the parent falls back to launching the standalone player.
  bool get canPromote => _engine != null && _videoVisible;

  /// TV (Android) gets the native ExoPlayer-into-a-Texture engine — libmpv
  /// stutters decoding the trailer on weak TV SoCs. Everything else keeps the
  /// proven media_kit path.
  TrailerEngine _createEngine() {
    final useExo =
        !kIsWeb && Platform.isAndroid && PlatformUtil.isAndroidTvCached;
    return useExo
        ? ExoTrailerEngine(maxHeight: _tvTrailerMaxHeight)
        : MediaKitTrailerEngine();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MainPageBridge.addExternalPlayerLaunchListener(_onExternalPlayerLaunched);
    MainPageBridge.addPlayerLaunchListener(_onContentPlayerLaunching);
    _fg =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 420),
        )..addListener(() {
          if (mounted) setState(() {});
        });
    // The initial start is kicked off from didChangeDependencies, not here:
    // [_canPlay] reads MediaQuery (reduced-motion), which must not be touched
    // before initState completes.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
    // Handles the first-build-with-a-url case (e.g. a cached stream). The far
    // more common async-arrival case is handled by didUpdateWidget.
    if (_canPlay && _engine == null && _startTimer == null) _scheduleStart();
  }

  @override
  void didUpdateWidget(covariant HeroTrailerBackdrop old) {
    super.didUpdateWidget(old);

    final urlChanged =
        widget.videoUrl != old.videoUrl || widget.audioUrl != old.audioUrl;
    if (urlChanged || widget.enabled != old.enabled) {
      if (!_canPlay) {
        _teardownPlayer();
      } else if (urlChanged && _engine != null) {
        // The URL changed under a live player — restart on the new media.
        _teardownPlayer();
        _scheduleStart();
      } else if (_engine == null) {
        _scheduleStart();
      }
    }

    // Ambient volume retarget (the Home hero's takeover swell) — applied to
    // the live engine without any restart. No-op while foregrounded (full
    // volume) or user-muted; _applyVolume handles both.
    if (widget.ambientVolume != old.ambientVolume && _engine != null) {
      _applyVolume(foreground: widget.foreground);
    }

    // Foreground promotion / demotion.
    if (widget.foreground != old.foreground) {
      if (widget.foreground && _engine != null) {
        _enterForeground();
      } else if (widget.foreground) {
        // Asked to promote with no live player (teardown raced the promote) —
        // back out rather than fade to an empty foreground.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onRequestClose?.call(),
        );
      } else {
        _exitForeground();
      }
      // Promotion/demotion flips whether the trailer counts as "in background".
      _syncPlayingNotification();
    }
  }

  /// Playback handed off to a separate external activity/app. On mobile/TV the
  /// activity lifecycle already sequences the trailer correctly (the app is
  /// paused while the external player runs, and playback has ended by the time
  /// it resumes) — only desktop needs the hard stop, because there the app can
  /// regain focus while the external player is still going.
  void _onExternalPlayerLaunched() {
    final desktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    if (!desktop) return;
    _stoppedForExternalPlayback = true;
    _teardownPlayer();
  }

  /// The real content player (movie/series) is launching from this page. Stop
  /// the ambient trailer now (kill any lingering audio) and latch it off so the
  /// route-pop resume (non-TV) and app-resume path (TV native activity) both
  /// bail via [_canPlay]. Resets when the page is reopened with fresh state.
  void _onContentPlayerLaunching() {
    if (!mounted) return;
    _stoppedForContentPlayback = true;
    _teardownPlayer();
  }

  void _scheduleStart() {
    _startTimer?.cancel();
    _startTimer = Timer(widget.startDelay, () {
      // _appPaused: don't open a stream (play: true) while the app is
      // backgrounded — trailer audio would play over other apps. The resume
      // handler reschedules.
      if (!mounted || !_canPlay || _covered || _appPaused) return;
      _initPlayer();
    });
  }

  Future<void> _initPlayer() async {
    if (_engine != null) return;
    final url = widget.videoUrl;
    if (url == null || url.isEmpty) return;

    final engine = _createEngine();
    _engine = engine;

    // Subscribe synchronously, before any await, so a teardown landing in the
    // await window below cancels these subscriptions instead of orphaning them.
    _playingSub = engine.playingStream.listen((playing) {
      if (!mounted) return;
      setState(() => _playing = playing);
      _syncPlayingNotification();
    });
    // Reveal the video (and tell the parent "playing") only once the first
    // frame has actually RENDERED — `playing` flips true the moment open()
    // starts, long before frames exist, which would kill the loading spinner
    // early and crossfade onto a black/buffering surface.
    engine.firstFrameRendered.then((_) {
      if (!mounted || _engine != engine || _videoVisible) return;
      // Jump past the intro/rating card so the ambient loop shows footage.
      // Skip only when the clip is comfortably longer than the cut (or its
      // duration isn't known yet — trailers are minutes long, so assume it is).
      final dur = _duration;
      final longEnough =
          dur == Duration.zero || dur > const Duration(seconds: 8);
      if (!widget.foreground && longEnough) engine.seek(_introSkip);
      setState(() => _videoVisible = true);
      _syncPlayingNotification();
    });
    // Fatal playback error (dead/expired stream), including mid-play after the
    // trailer was already showing or promoted to fullscreen → tear down so we
    // drop back to the poster (and, if foregrounded, back the user out) rather
    // than freezing on the last frame.
    _errorSub = engine.errorStream.listen((_) {
      if (mounted && _engine == engine) _teardownPlayer();
    });
    _posSub = engine.positionStream.listen((p) {
      // Loop restart (position wrapped back to the start) → skip the intro
      // again. Ambient only: never fight a manual scrub or foreground seek.
      if (!widget.foreground &&
          !_scrubbing &&
          _lastPos > const Duration(seconds: 6) &&
          p < const Duration(seconds: 1)) {
        engine.seek(_introSkip);
      }
      _lastPos = p;
      // Don't snap the thumb back to stale positions mid-drag.
      if (mounted && !_scrubbing) setState(() => _position = p);
    });
    _durSub = engine.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    try {
      // Ambient: audible-but-quiet + looping (sound plays in the backdrop too;
      // the foreground mute chip is the user's off switch). A teardown (URL
      // switch, toggle off) can detach [engine] mid-open; the engine aborts
      // cleanly, and we re-check identity after.
      await engine.open(
        videoUrl: url,
        // YouTube rarely serves a muxed stream anymore, so [url] is usually
        // video-only — mux the separate audio track in for sound (the same
        // path the main player uses for high-res YouTube).
        audioUrl: widget.audioUrl,
        volume: _userMuted ? 0 : widget.ambientVolume,
        loop: true,
      );
      if (_engine != engine) return;
      if (widget.foreground) _applyVolume(foreground: true);
    } catch (_) {
      // Bot-blocked / dead stream → stay on the static poster. Guarded: a
      // STALE engine's error (e.g. its open() aborting after a URL switch
      // already tore it down) must not destroy the replacement engine.
      if (_engine == engine) _teardownPlayer();
    }
  }

  void _teardownPlayer() {
    _startTimer?.cancel();
    _startTimer = null;
    _playingSub?.cancel();
    _playingSub = null;
    _posSub?.cancel();
    _posSub = null;
    _durSub?.cancel();
    _durSub = null;
    _errorSub?.cancel();
    _errorSub = null;
    final engine = _engine;
    _engine = null;
    _lastPos = Duration.zero;
    // Pause intent is player-scoped: a fresh player (URL switch, toggle
    // off→on) always opens with play:true, so a leftover pause from the
    // previous trailer must not suppress the new one's resume paths.
    _pausedByUser = false;
    // Flip the engine's disposed flag NOW (sync) so any in-flight open() bails
    // and stale control calls no-op — but defer the surface release below.
    engine?.detach();
    if (mounted) setState(() => _videoVisible = false);
    // Change-detected: no-ops for a benign teardown that never started a player
    // (so it can't kill the parent's loading spinner), fires false when a live
    // ambient trailer actually stops.
    _syncPlayingNotification();
    // Nothing to dispose / rescue if no player existed.
    if (engine == null) return;
    // If the stream died while foregrounded, the page content is faded out and
    // input-blocked with no controls left to paint — ask the parent to back out
    // so the user isn't stranded on a frozen surface.
    if (widget.foreground) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onRequestClose?.call(),
      );
    }
    // Dispose only after this frame's rebuild has dropped the Video/Texture, so
    // it never renders against a disposed controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => engine.dispose());
  }

  // ── Foreground promotion ────────────────────────────────────────────────────

  void _enterForeground() {
    // Every promotion starts audible (the user tapped Trailer to watch it) and
    // with chrome shown (it auto-hides shortly after).
    setState(() => _userMuted = false);
    _pausedByUser = false;
    _showControlsTemporarily();
    _fg.forward();
    _applyVolume(foreground: true);
    _engine?.play();
  }

  void _exitForeground() {
    _controlsTimer?.cancel();
    _fg.reverse();
    // Settle back to the quiet ambient level (respecting the mute chip).
    _applyVolume(foreground: false);
    // Respect an explicit pause: if the user paused in the player, the ambient
    // backdrop stays paused too (re-tapping Trailer re-promotes and resumes).
    // Only auto-resume the ambient loop when it wasn't paused on purpose.
    if (!_pausedByUser) _engine?.play();
    _syncPlayingNotification();
  }

  /// Show the chrome and arm the auto-hide. Chrome stays up while paused —
  /// hiding controls on a paused frame is disorienting.
  void _showControlsTemporarily() {
    _controlsTimer?.cancel();
    setState(() => _controlsVisible = true);
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !widget.foreground || !_playing) return;
      setState(() => _controlsVisible = false);
    });
  }

  /// Muted → 0; foreground → full; ambient → deliberately low.
  void _applyVolume({required bool foreground}) {
    _engine?.setVolume(
      _userMuted ? 0 : (foreground ? _foregroundVolume : widget.ambientVolume),
    );
  }

  void _toggleMute() {
    setState(() => _userMuted = !_userMuted);
    _applyVolume(foreground: widget.foreground);
    _showControlsTemporarily();
  }

  /// Is the ambient backdrop trailer *actively playing right now* — frames on
  /// screen, playing, and not promoted to fullscreen. This is what the parent
  /// reflects as "trailer playing in background".
  bool get _activelyPlayingAmbient =>
      _engine != null && _videoVisible && _playing && !widget.foreground;

  /// Notify the parent only when the ambient-playing state actually changes.
  /// Change-detection also fixes the loading spinner: a benign teardown (no
  /// player ever started) computes false == false and stays silent.
  void _syncPlayingNotification() {
    final playing = _activelyPlayingAmbient;
    if (playing == _lastNotifiedPlaying) return;
    _lastNotifiedPlaying = playing;
    final cb = widget.onPlayingChanged;
    if (cb == null) return;
    // Post-frame so a teardown running inside a parent build can't re-enter
    // setState on the parent mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(playing);
    });
  }

  void _togglePlay() {
    final p = _engine;
    if (p == null) return;
    if (_playing) {
      _pausedByUser = true;
      p.pause();
    } else {
      _pausedByUser = false;
      p.play();
    }
    _showControlsTemporarily();
  }

  // ── Single-decoder discipline ──────────────────────────────────────────────

  /// On Android TV the trailer decodes through native ExoPlayer, which holds a
  /// hardware H.264 codec even while merely paused. Real playback launches a
  /// *separate* ExoPlayer (the fullscreen torrent activity), and weak TV SoCs
  /// have a tiny decoder pool — a paused trailer can starve it and black-screen
  /// the real video. So when the trailer is hidden (a route covers us, or the
  /// app backgrounds as the native player takes over), fully release it and
  /// re-create on return. Off-TV (media_kit) keeps the cheaper pause/resume.
  bool get _releaseDecoderWhenHidden =>
      !kIsWeb && Platform.isAndroid && PlatformUtil.isAndroidTvCached;

  @override
  void didPushNext() {
    _covered = true;
    if (_releaseDecoderWhenHidden) {
      _teardownPlayer();
    } else {
      _engine?.pause();
    }
  }

  @override
  void didPopNext() {
    _covered = false;
    if (!_canPlay || _appPaused) return;
    if (_engine != null) {
      // Respect an explicit user pause of the foreground trailer.
      if (!_pausedByUser) _engine!.play();
    } else {
      _scheduleStart();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appPaused = false;
      if (_covered) return;
      if (_engine != null) {
        if (!_pausedByUser) _engine!.play();
      } else if (mounted && _canPlay) {
        // The start timer may have fired (and skipped) while backgrounded —
        // give the trailer another dwell-delayed start now.
        _scheduleStart();
      }
    } else {
      _appPaused = true;
      // Release the hardware decoder on TV so the native fullscreen player can
      // claim it (see [_releaseDecoderWhenHidden]); pause/resume elsewhere.
      if (_releaseDecoderWhenHidden) {
        _teardownPlayer();
      } else {
        _engine?.pause();
      }
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    MainPageBridge.removeExternalPlayerLaunchListener(
      _onExternalPlayerLaunched,
    );
    MainPageBridge.removePlayerLaunchListener(_onContentPlayerLaunching);
    _startTimer?.cancel();
    _controlsTimer?.cancel();
    _playingSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _errorSub?.cancel();
    _fg.dispose();
    _engine?.dispose();
    super.dispose();
  }

  /// The static image layer. Small decode always (see build); the gaussian
  /// only exists on the sigma > 0 (non-TV) path.
  Widget _buildStaticBackdrop() {
    final image = CachedNetworkImage(
      imageUrl: widget.imageUrl!,
      fit: BoxFit.cover,
      // 96px on the filterless TV path (the upscale IS the blur); 480px under
      // a real gaussian, where the filter hides the upscale.
      memCacheWidth: widget.imageBlurSigma <= 0 ? 96 : 480,
      filterQuality: FilterQuality.medium,
      errorWidget: (_, __, ___) => const SizedBox.shrink(),
    );
    if (widget.imageBlurSigma <= 0) return image;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: widget.imageBlurSigma,
        sigmaY: widget.imageBlurSigma,
      ),
      child: image,
    );
  }

  /// Wraps the static image layer in the destination [Hero] when a tag is set.
  /// No flightShuttleBuilder here — the source (poster card) defines one, and
  /// leaving this side null lets the card's builder drive both directions.
  Widget _withHero(Widget child) {
    final tag = widget.heroTag;
    if (tag == null) return child;
    return Hero(tag: tag, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final t = _fg.value; // 0 ambient → 1 foreground
    final videoBlur = lerpDouble(widget.videoBlurSigma, 0, t)!;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Static backdrop — always present, so the crossfade has a floor and a
        // missing/late trailer simply shows the poster. When a heroTag is set
        // this layer doubles as the shared-element destination: the tapped
        // board poster flies into this rect (the flight shuttle shows the
        // poster; see the card-side flightShuttleBuilder).
        //
        // The soft look comes from a TINY decode upscaled by cover-fit, not a
        // runtime gaussian: a full-screen ImageFiltered blur re-rasterises on
        // animated frames (Hero flight, entrance cascade, focus moves) and the
        // full-res source decode alone can stall a 2GB TV box — the "page
        // hangs on open" failure. At sigma 42 every detail below the blur
        // radius is gone anyway, so a small decode is visually equivalent for
        // free. [imageBlurSigma] <= 0 requests an even smaller decode with no
        // filter at all (the weak-TV path); > 0 keeps a light gaussian on top
        // to hide upscale artifacts on capable GPUs.
        if (widget.imageUrl != null) _withHero(_buildStaticBackdrop()),
        // Trailer, crossfaded in once it produces frames. When the widget is
        // CONFIGURED blur-free (TV), the ImageFiltered layer is omitted — it
        // costs a per-frame filter pass over the video surface even at sigma
        // 0. Branch on the static config, never the animated [videoBlur]: a
        // mid-promotion branch flip would re-parent the live Video widget and
        // flash the texture.
        if (engine != null)
          AnimatedOpacity(
            opacity: _videoVisible ? 1 : 0,
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOut,
            child: widget.videoBlurSigma <= 0
                ? engine.buildVideo(fit: BoxFit.cover)
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: videoBlur,
                      sigmaY: videoBlur,
                    ),
                    child: engine.buildVideo(fit: BoxFit.cover),
                  ),
          ),
        // Foreground controls — only interactive/painted while promoted.
        if (t > 0.01 && engine != null) _buildForegroundControls(t),
      ],
    );
  }

  /// DPAD/keyboard handling for the fullscreen trailer. The page content is
  /// focus-excluded while foregrounded, so this node holds focus: OK toggles
  /// play/pause (or reveals hidden chrome first), ←/→ seek ±10s, ↑/↓ are
  /// consumed so focus can't wander. Back is left to bubble into the parent's
  /// PopScope, which demotes the trailer.
  KeyEventResult _onForegroundKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (isActivateOrSpaceKey(key)) {
      if (_controlsVisible) {
        _togglePlay();
      } else {
        _showControlsTemporarily();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final delta = key == LogicalKeyboardKey.arrowRight ? 10 : -10;
      var target = _position + Duration(seconds: delta);
      if (target < Duration.zero) target = Duration.zero;
      _engine?.seek(target);
      _showControlsTemporarily();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildForegroundControls(double t) {
    final interactive = t > 0.98;
    return Opacity(
      opacity: t,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Focus(
          autofocus: true,
          onKeyEvent: _onForegroundKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Tap/click surface: reveal the chrome (re-arming the auto-hide),
              // or hide it immediately if it's already up.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_controlsVisible) {
                    _controlsTimer?.cancel();
                    setState(() => _controlsVisible = false);
                  } else {
                    _showControlsTemporarily();
                  }
                },
                child: const SizedBox.expand(),
              ),
              // Bottom scrim so controls stay legible over bright frames.
              if (_controlsVisible)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ),
              // Close (top-right). Hides with the rest of the chrome — a click
              // brings it back, and hardware/browser Back always exits (PopScope).
              if (_controlsVisible)
                Positioned(
                  top: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _CircleControl(
                        icon: Icons.close_rounded,
                        tooltip: 'Close trailer',
                        onTap: () => widget.onRequestClose?.call(),
                      ),
                    ),
                  ),
                ),
              // Center play/pause.
              if (_controlsVisible)
                Center(
                  child: _CircleControl(
                    icon: _playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: _playing ? 'Pause' : 'Play',
                    large: true,
                    onTap: _togglePlay,
                  ),
                ),
              // Bottom bar: seek + mute.
              if (_controlsVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                      child: Row(
                        children: [
                          Expanded(child: _buildSeekBar()),
                          _CircleControl(
                            icon: _userMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            tooltip: _userMuted ? 'Unmute' : 'Mute',
                            onTap: _toggleMute,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeekBar() {
    final durMs = _duration.inMilliseconds;
    final posMs = _position.inMilliseconds.clamp(0, durMs == 0 ? 1 : durMs);
    final value = durMs == 0 ? 0.0 : posMs / durMs;
    return Row(
      children: [
        Text(_fmt(_position), style: _timeStyle),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChangeStart: durMs == 0
                  ? null
                  : (_) {
                      // Latch: hold the chrome and stop the position stream
                      // from fighting the thumb while dragging.
                      _scrubbing = true;
                      _controlsTimer?.cancel();
                    },
              onChanged: durMs == 0
                  ? null
                  : (v) {
                      final target = Duration(
                        milliseconds: (v * durMs).round(),
                      );
                      setState(() => _position = target);
                      _engine?.seek(target);
                    },
              onChangeEnd: durMs == 0
                  ? null
                  : (_) {
                      _scrubbing = false;
                      _showControlsTemporarily();
                    },
            ),
          ),
        ),
        Text(_fmt(_duration), style: _timeStyle),
      ],
    );
  }

  static const TextStyle _timeStyle = TextStyle(
    color: Colors.white70,
    fontSize: 12,
  );

  static String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }
}

/// A round, focusable control button used in the fullscreen trailer chrome.
class _CircleControl extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool large;

  const _CircleControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 72.0 : 44.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: large ? 40 : 22),
          ),
        ),
      ),
    );
  }
}
