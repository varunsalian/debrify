import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

/// A pluggable trailer playback engine behind `HeroTrailerBackdrop`.
///
/// Lets the backdrop's UI/state logic stay identical while the underlying
/// decoder swaps: [MediaKitTrailerEngine] (libmpv) on phones/desktop, and
/// [ExoTrailerEngine] (native ExoPlayer rendered into a Flutter [Texture] or,
/// in underlay mode, onto a native SurfaceView *behind* the Flutter surface)
/// on Android TV, where libmpv stutters on weak SoCs.
///
/// Volume is on media_kit's 0–100 scale throughout (the widget was written
/// against it); the Exo engine rescales to 0–1 internally.
abstract class TrailerEngine {
  /// True when [buildVideo] renders a see-through hole to a native surface
  /// *behind* Flutter instead of Flutter pixels. The backdrop widget must then
  /// invert its crossfade (fade covering content OUT — the video itself can't
  /// fade) and must not wrap the slot in Opacity/filters (a saveLayer would
  /// localize the hole's BlendMode.clear and break the punch-through).
  bool get rendersUnderlay => false;
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;

  /// Fires on a fatal playback error that happens *after* the first frame has
  /// rendered (a dead/expired stream mid-play). The caller should tear down.
  /// Pre-first-frame failures surface via [firstFrameRendered]/[open] instead.
  /// media_kit keeps its original behavior (errors flow through [open]); only
  /// the Exo engine emits here.
  Stream<void> get errorStream;

  /// Completes when the first frame has actually rendered.
  Future<void> get firstFrameRendered;

  /// Open [videoUrl] (muxing [audioUrl] when present), looping when [loop], at
  /// [volume] (0–100), and start playing. Called once. Safe against a [detach]
  /// landing mid-open — it aborts cleanly without leaking a native player.
  ///
  /// [httpHeaders] are sent with every request for this media (IPTV channels
  /// declare per-channel User-Agent/Referer, and panels hard-block requests
  /// without them — the live preview must send exactly what the players send).
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required double volume,
    required bool loop,
    Map<String, String>? httpHeaders,
  });

  Future<void> setVolume(double volume); // 0–100
  Future<void> seek(Duration position);
  Future<void> play();
  Future<void> pause();

  /// Synchronously mark the engine detached so any in-flight [open] and later
  /// control calls become no-ops. Does NOT release the render surface — call
  /// [dispose] (post-frame) for that, so the [Texture]/`Video` unmounts first.
  void detach();

  /// Release all native/player resources. Idempotent; implies [detach].
  Future<void> dispose();

  /// The render surface (media_kit `Video`, a Flutter [Texture], or the
  /// underlay hole). [revealed] only matters for underlay engines: while false
  /// the slot reports its bounds natively but paints nothing, so the covering
  /// UI stays opaque and the native surface stays hidden until first frame.
  Widget buildVideo({required BoxFit fit, bool revealed = true});
}

/// libmpv-backed engine (the original path). Used off-TV.
class MediaKitTrailerEngine implements TrailerEngine {
  MediaKitTrailerEngine() {
    // Idempotent; the main player also initializes it, but guard in case the
    // trailer is the first media_kit surface in this session.
    mk.MediaKit.ensureInitialized();
    _player = mk.Player();
    _controller = mkv.VideoController(_player);
  }

  late final mk.Player _player;
  late final mkv.VideoController _controller;
  bool _disposed = false;
  bool _released = false;

  @override
  bool get rendersUnderlay => false;

  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  // media_kit surfaces open failures by throwing from open(); it has no
  // separate post-first-frame error path (unchanged from the original).
  @override
  Stream<void> get errorStream => const Stream<void>.empty();
  @override
  Future<void> get firstFrameRendered => _controller.waitUntilFirstFrameRendered;

  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required double volume,
    required bool loop,
    Map<String, String>? httpHeaders,
  }) async {
    // Re-check [_disposed] after every await: a detach (URL switch, toggle off)
    // can land mid-sequence, and media_kit throws on use-after-dispose.
    await _player.setVolume(volume);
    if (_disposed) return;
    await _player.setPlaylistMode(
      loop ? mk.PlaylistMode.single : mk.PlaylistMode.none,
    );
    if (_disposed) return;
    await _player.open(
      mk.Media(videoUrl, httpHeaders: httpHeaders),
      play: true,
    );
    if (_disposed) return;
    if (audioUrl != null && audioUrl.isNotEmpty) {
      await _player.setAudioTrack(mk.AudioTrack.uri(audioUrl));
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_disposed) await _player.setVolume(volume);
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_disposed) await _player.seek(position);
  }

  @override
  Future<void> play() async {
    if (!_disposed) await _player.play();
  }

  @override
  Future<void> pause() async {
    if (!_disposed) await _player.pause();
  }

  @override
  void detach() => _disposed = true;

  @override
  Future<void> dispose() async {
    _disposed = true;
    if (_released) return;
    _released = true;
    await _player.dispose();
  }

  @override
  Widget buildVideo({required BoxFit fit, bool revealed = true}) =>
      mkv.Video(controller: _controller, controls: null, fit: fit);
}

/// Immutable render state for the Exo texture (id + intrinsic video size).
class _ExoRender {
  final int? textureId;
  final double width;
  final double height;
  const _ExoRender(this.textureId, this.width, this.height);
}

/// Native ExoPlayer, Android-TV only. Reuses the app's proven video-only +
/// audio MergingMediaSource merge (built natively) so high-res YouTube
/// trailers play with hardware decode. Two render modes:
///
///  - Texture (default): frames land in a Flutter [Texture]; Flutter
///    re-composites the scene at video framerate (the historical TV stutter).
///  - [underlay]: frames land on a native SurfaceView *behind* a translucent
///    Flutter surface (its own hardware overlay plane — Flutter never touches
///    them). [buildVideo] then renders a punched-through hole that reports its
///    bounds to the native side instead of a Texture. Requires MainActivity's
///    TV transparency mode (same setting gates both).
class ExoTrailerEngine implements TrailerEngine {
  ExoTrailerEngine({this.maxHeight = 0, this.underlay = false});

  /// Cap the render texture to this height (0 = uncapped). Trims per-frame GPU
  /// upload on weak TV GPUs; decode stays hardware-cheap regardless. Unused in
  /// [underlay] mode (there is no per-frame upload to trim).
  final int maxHeight;

  /// Render behind Flutter on a native hardware overlay plane. See class doc.
  final bool underlay;

  @override
  bool get rendersUnderlay => underlay;

  int? _textureId;
  bool _disposed = false;
  bool _released = false;
  bool _polling = false;
  Timer? _pollTimer;

  final _playingCtl = StreamController<bool>.broadcast();
  final _positionCtl = StreamController<Duration>.broadcast();
  final _durationCtl = StreamController<Duration>.broadcast();
  final _errorCtl = StreamController<void>.broadcast();
  final _firstFrame = Completer<void>();
  // 16:9 placeholder until the real video size arrives (cover-fit tolerates it).
  final _render = ValueNotifier<_ExoRender>(const _ExoRender(null, 1280, 720));

  @override
  Stream<bool> get playingStream => _playingCtl.stream;
  @override
  Stream<Duration> get positionStream => _positionCtl.stream;
  @override
  Stream<Duration> get durationStream => _durationCtl.stream;
  @override
  Stream<void> get errorStream => _errorCtl.stream;
  @override
  Future<void> get firstFrameRendered => _firstFrame.future;

  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required double volume,
    required bool loop,
    Map<String, String>? httpHeaders,
  }) async {
    final id = await _TvTrailerChannel.instance.create(
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      maxHeight: maxHeight,
      volume: (volume / 100).clamp(0.0, 1.0),
      loop: loop,
      underlay: underlay,
      httpHeaders: httpHeaders,
    );
    if (_disposed) {
      // A detach raced the native create — release the orphaned player and drop
      // any events that buffered against this id (it was never registered).
      _TvTrailerChannel.instance.unregister(id);
      await _TvTrailerChannel.instance.disposePlayer(id);
      return;
    }
    _textureId = id;
    _render.value = _ExoRender(id, _render.value.width, _render.value.height);
    _TvTrailerChannel.instance.register(id, this);
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Drives positionStream (foreground seekbar + ambient loop-restart detection)
    // and picks up duration. ExoPlayer has no position callback, so we poll.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (_disposed || _polling) return;
      final id = _textureId;
      if (id == null) return;
      _polling = true;
      try {
        final r = await _TvTrailerChannel.instance.getPosition(id);
        if (_disposed || r == null) return;
        _positionCtl.add(
          Duration(milliseconds: (r['positionMs'] as num?)?.toInt() ?? 0),
        );
        final d = (r['durationMs'] as num?)?.toInt() ?? 0;
        if (d > 0) _durationCtl.add(Duration(milliseconds: d));
      } catch (_) {
        // Transient channel hiccup — next tick retries.
      } finally {
        _polling = false;
      }
    });
  }

  /// Dispatch a native → Dart event (routed here by textureId).
  void handleEvent(String method, Map<dynamic, dynamic> args) {
    if (_disposed) return;
    switch (method) {
      case 'firstFrame':
        if (!_firstFrame.isCompleted) _firstFrame.complete();
        break;
      case 'playing':
        _playingCtl.add(args['playing'] == true);
        break;
      case 'duration':
        final d = (args['durationMs'] as num?)?.toInt() ?? 0;
        if (d > 0) _durationCtl.add(Duration(milliseconds: d));
        break;
      case 'videoSize':
        final w = (args['width'] as num?)?.toDouble() ?? 0;
        final h = (args['height'] as num?)?.toDouble() ?? 0;
        if (w > 0 && h > 0) _render.value = _ExoRender(_textureId, w, h);
        break;
      case 'error':
        // Fatal playback error. Before the first frame the widget simply never
        // reveals the video (firstFrameRendered stays pending); either way,
        // errorStream tells the widget to tear down and drop back to the poster.
        _errorCtl.add(null);
        break;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    final id = _textureId;
    if (_disposed || id == null) return;
    await _TvTrailerChannel.instance
        .setVolume(id, (volume / 100).clamp(0.0, 1.0));
  }

  @override
  Future<void> seek(Duration position) async {
    final id = _textureId;
    if (_disposed || id == null) return;
    // Reflect the target immediately so the foreground seekbar tracks a seek
    // even while paused (polling is idle then — see [pause]).
    _positionCtl.add(position);
    await _TvTrailerChannel.instance.seek(id, position.inMilliseconds);
  }

  @override
  Future<void> play() async {
    final id = _textureId;
    if (_disposed || id == null) return;
    _startPolling(); // resume position updates
    await _TvTrailerChannel.instance.play(id);
  }

  @override
  Future<void> pause() async {
    final id = _textureId;
    if (_disposed || id == null) return;
    // Stop the 250ms getPosition round-trips while paused/covered/backgrounded —
    // position isn't advancing, and this keeps the covering screen jank-free.
    _pollTimer?.cancel();
    _pollTimer = null;
    await _TvTrailerChannel.instance.pause(id);
  }

  @override
  void detach() {
    _disposed = true;
    _pollTimer?.cancel();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _pollTimer?.cancel();
    if (_released) return;
    _released = true;
    final id = _textureId;
    if (id != null) {
      _TvTrailerChannel.instance.unregister(id);
      await _TvTrailerChannel.instance.disposePlayer(id);
    }
    await _playingCtl.close();
    await _positionCtl.close();
    await _durationCtl.close();
    await _errorCtl.close();
    _render.dispose();
  }

  @override
  Widget buildVideo({required BoxFit fit, bool revealed = true}) {
    if (underlay) return _UnderlayHole(engine: this, revealed: revealed);
    return ValueListenableBuilder<_ExoRender>(
      valueListenable: _render,
      builder: (context, r, _) {
        final id = r.textureId;
        if (id == null) return const SizedBox.expand();
        // Texture fills its box; wrap it in the video's aspect ratio and
        // cover-fit so BoxFit.cover reads the same as media_kit's Video.
        return ClipRect(
          child: FittedBox(
            fit: fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: r.width,
              height: r.height,
              child: Texture(textureId: id),
            ),
          ),
        );
      },
    );
  }
}

/// The render slot for an underlay [ExoTrailerEngine]: continuously reports its
/// global bounds to the native side and, once [revealed], paints a
/// [BlendMode.clear] rect that punches through every Flutter pixel below it —
/// with the Flutter surface translucent (MainActivity's TV path), the native
/// SurfaceView behind shows through. Content painted *above* this widget
/// (feathers, tints, text, scrims) still composites over the video normally.
///
/// While not [revealed] it paints nothing (the UI above stays opaque, hiding
/// the SurfaceView) but bounds still flow, so the native surface is already
/// sized and rendering when the reveal lands — no black flash, no resize.
class _UnderlayHole extends StatefulWidget {
  final ExoTrailerEngine engine;
  final bool revealed;

  const _UnderlayHole({required this.engine, required this.revealed});

  @override
  State<_UnderlayHole> createState() => _UnderlayHoleState();
}

class _UnderlayHoleState extends State<_UnderlayHole> {
  Rect? _sentRect;
  int? _sentId;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  /// Re-measures after every rendered frame while mounted. Piggybacks on
  /// frames the app renders anyway (addPostFrameCallback never schedules one),
  /// so scrolls/transitions retarget the native view within a frame while a
  /// fully idle app — including video playing with no UI changes, the whole
  /// point of the underlay — pays nothing.
  void _scheduleReport() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _report();
      _scheduleReport();
    });
  }

  void _report() {
    final id = widget.engine._textureId;
    if (id == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    // Map both corners so ancestor transforms (e.g. the Discover rail's
    // FittedBox scale) land in true screen space — sent as LOGICAL px below.
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
    final rect = Rect.fromPoints(topLeft, bottomRight);
    if (rect == _sentRect && id == _sentId) return;
    _sentRect = rect;
    _sentId = id;
    // LOGICAL px on the wire; the native side multiplies by ITS display
    // density. Deliberately NOT this view's devicePixelRatio: under low-res
    // rendering (weak-GPU TVs) Flutter's dpr is scaled down (e.g. 1.333)
    // while the native window stays in real display space (density 2.0) —
    // multiplying here would land the video at 2/3 size and offset. Flutter
    // logical == Android dp on every device, so this is mode-independent.
    _TvTrailerChannel.instance.setBounds(
      id,
      rect.left,
      rect.top,
      rect.width,
      rect.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.revealed) return const SizedBox.expand();
    return const CustomPaint(
      painter: _HolePunchPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _HolePunchPainter extends CustomPainter {
  const _HolePunchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..blendMode = BlendMode.clear);
  }

  @override
  bool shouldRepaint(_HolePunchPainter oldDelegate) => false;
}

/// Owns the `com.debrify.app/tv_trailer` channel and dispatches native → Dart
/// events to the right [ExoTrailerEngine] by textureId. Lazily constructed the
/// first time an Exo engine is used (never touched off-TV).
class _TvTrailerChannel {
  _TvTrailerChannel._() {
    _channel.setMethodCallHandler(_onCall);
  }

  static final _TvTrailerChannel instance = _TvTrailerChannel._();
  static const MethodChannel _channel =
      MethodChannel('com.debrify.app/tv_trailer');

  final Map<int, ExoTrailerEngine> _engines = {};
  // Events that arrive before their engine registers (race guard) are buffered.
  final Map<int, List<MethodCall>> _pending = {};

  Future<int> create({
    required String videoUrl,
    String? audioUrl,
    required int maxHeight,
    required double volume,
    required bool loop,
    required bool underlay,
    Map<String, String>? httpHeaders,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>('create', {
      'videoUrl': videoUrl,
      'audioUrl': audioUrl,
      'maxHeight': maxHeight,
      'volume': volume,
      'loop': loop,
      'underlay': underlay,
      if (httpHeaders != null && httpHeaders.isNotEmpty)
        'headers': httpHeaders,
    });
    return (res?['textureId'] as num).toInt();
  }

  void register(int id, ExoTrailerEngine engine) {
    _engines[id] = engine;
    final buffered = _pending.remove(id);
    if (buffered != null) {
      for (final c in buffered) {
        engine.handleEvent(c.method, c.arguments as Map);
      }
    }
  }

  void unregister(int id) {
    _engines.remove(id);
    _pending.remove(id);
  }

  // Control calls are fire-and-forget and can land after the native handler is
  // torn down (Activity onDestroy → releaseAll → setMethodCallHandler(null)),
  // which rejects with MissingPluginException. Swallow it so it doesn't surface
  // as an unhandled async error.
  Future<void> _safeInvoke(String method, Map<String, dynamic> args) async {
    try {
      await _channel.invokeMethod(method, args);
    } on MissingPluginException {
      // Native side gone — nothing to do.
    } on PlatformException {
      // Player already released natively — benign for a fire-and-forget call.
    }
  }

  Future<void> setVolume(int id, double v) =>
      _safeInvoke('setVolume', {'id': id, 'volume': v});
  /// Bounds are LOGICAL px (Flutter logical == Android dp); the native side
  /// converts to window px with its own display density. See _UnderlayHole.
  Future<void> setBounds(
    int id,
    double left,
    double top,
    double width,
    double height,
  ) => _safeInvoke('setBounds', {
    'id': id,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  });
  Future<void> seek(int id, int ms) =>
      _safeInvoke('seek', {'id': id, 'positionMs': ms});
  Future<void> play(int id) => _safeInvoke('play', {'id': id});
  Future<void> pause(int id) => _safeInvoke('pause', {'id': id});
  Future<Map<String, dynamic>?> getPosition(int id) async {
    try {
      return await _channel
          .invokeMapMethod<String, dynamic>('getPosition', {'id': id});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> disposePlayer(int id) => _safeInvoke('dispose', {'id': id});

  Future<dynamic> _onCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map) return null;
    final id = (args['id'] as num?)?.toInt();
    if (id == null) return null;
    final engine = _engines[id];
    if (engine == null) {
      (_pending[id] ??= []).add(call);
    } else {
      engine.handleEvent(call.method, args);
    }
    return null;
  }
}
