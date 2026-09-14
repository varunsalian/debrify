import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../services/app_route_observer.dart';
import '../../services/collection_focus_playback.dart';
import '../../services/collection_gif_settings.dart';
import '../../services/main_page_bridge.dart';
import '../hero_trailer_backdrop.dart';
import '../trailer_engine.dart';

/// Collection media over a still cover. Tile GIFs follow the device preference
/// and viewport visibility; videos still require focus or hover.
class CollectionFocusArt extends StatefulWidget {
  final bool focused;
  final bool applyGifPreference;
  final String? gifUrl;
  final String? videoUrl;
  @visibleForTesting
  final Future<TrailerEngine> Function()? engineFactory;

  const CollectionFocusArt({
    super.key,
    this.gifUrl,
    this.focused = true,
    this.applyGifPreference = false,
    this.videoUrl,
    this.engineFactory,
  });

  @override
  State<CollectionFocusArt> createState() => _CollectionFocusArtState();
}

class _CollectionFocusArtState extends State<CollectionFocusArt>
    with RouteAware, WidgetsBindingObserver {
  final _owner = Object();
  final _visibilityKey = UniqueKey();
  bool _visible = false;
  CollectionGifMode? _gifMode;
  int _settingsRead = 0;

  Future<void> _loadGifMode() async {
    if (!widget.applyGifPreference) return;
    final token = ++_settingsRead;
    try {
      final mode = await CollectionGifSettings.read();
      if (mounted && token == _settingsRead) setState(() => _gifMode = mode);
    } catch (_) {
      // Keep the still cover when settings cannot be read.
    }
  }

  void _settingsChanged() => unawaited(_loadGifMode());

  bool _covered = false;
  bool _paused = false;
  bool _failed = false;
  PageRoute<dynamic>? _route;

  bool get _eligible =>
      widget.focused &&
      widget.videoUrl != null &&
      !_covered &&
      !_paused &&
      !_failed &&
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  void _syncOwner() {
    // Widgets can mount/unmount during a board build. Notify sibling heroes
    // only after that frame, and recheck eligibility when the callback runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _eligible) {
        CollectionFocusPlayback.claim(_owner);
      } else {
        CollectionFocusPlayback.release(_owner);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    MainPageBridge.addHomeSettingsListener(_settingsChanged);
    unawaited(_loadGifMode());
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _paused = state != null && state != AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route is PageRoute ? route : null;
      if (_route != null) appRouteObserver.subscribe(this, _route!);
    }
    _covered = route != null && !route.isCurrent;
    _syncOwner();
  }

  @override
  void didUpdateWidget(CollectionFocusArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.applyGifPreference != widget.applyGifPreference) {
      unawaited(_loadGifMode());
    }
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.focused != widget.focused) {
      _failed = false;
      _syncOwner();
    }
  }

  @override
  void didPushNext() {
    setState(() => _covered = true);
    _syncOwner();
  }

  @override
  void didPopNext() {
    setState(() => _covered = false);
    _syncOwner();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _paused = state != AppLifecycleState.resumed);
    if (_paused) {
      // A backgrounded app may produce no more frames. Release synchronously
      // so sibling trailers stop and the child's lifecycle flush can dispose.
      CollectionFocusPlayback.release(_owner);
    } else {
      _syncOwner();
    }
  }

  @override
  void dispose() {
    MainPageBridge.removeHomeSettingsListener(_settingsChanged);
    VisibilityDetectorController.instance.forget(_visibilityKey);
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => CollectionFocusPlayback.release(_owner),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final gifAllowed =
        !widget.applyGifPreference ||
        (_visible &&
            (_gifMode == CollectionGifMode.visible ||
                (_gifMode == CollectionGifMode.focused && widget.focused)));
    final art = IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!reduced &&
                gifAllowed &&
                !_covered &&
                !_paused &&
                widget.gifUrl != null &&
                (!widget.focused || widget.videoUrl == null || _failed))
              CachedNetworkImage(
                imageUrl: widget.gifUrl!,
                memCacheWidth: 640,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            if (widget.focused && widget.videoUrl != null && !_failed)
              HeroTrailerBackdrop(
                key: ValueKey(widget.videoUrl),
                imageUrl: null,
                videoUrl: widget.videoUrl,
                enabled: true,
                focusPreviewOwner: _owner,
                imageBlurSigma: 0,
                videoBlurSigma: 0,
                startDelay: const Duration(milliseconds: 350),
                ambientVolume: 0,
                firstFrameTimeout: const Duration(seconds: 8),
                engineFactory: widget.engineFactory,
                onPlaybackFailed: () {
                  setState(() => _failed = true);
                  _syncOwner();
                },
              ),
          ],
        ),
      ),
    );
    if (!widget.applyGifPreference || widget.gifUrl == null) return art;
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0;
        if (mounted && visible != _visible) setState(() => _visible = visible);
      },
      child: art,
    );
  }
}
