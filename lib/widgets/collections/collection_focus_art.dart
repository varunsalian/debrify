import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/app_route_observer.dart';
import '../../services/collection_focus_playback.dart';
import '../hero_trailer_backdrop.dart';
import '../trailer_engine.dart';

/// Mounted only for a focused/hovered folder. The caller keeps its cover below
/// this transparent overlay, including while opening and after video failure.
class CollectionFocusArt extends StatefulWidget {
  final String? gifUrl;
  final String? videoUrl;
  @visibleForTesting
  final Future<TrailerEngine> Function()? engineFactory;

  const CollectionFocusArt({
    super.key,
    this.gifUrl,
    this.videoUrl,
    this.engineFactory,
  });

  @override
  State<CollectionFocusArt> createState() => _CollectionFocusArtState();
}

class _CollectionFocusArtState extends State<CollectionFocusArt>
    with RouteAware, WidgetsBindingObserver {
  final _owner = Object();
  bool _covered = false;
  bool _paused = false;
  bool _failed = false;
  PageRoute<dynamic>? _route;

  bool get _eligible =>
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
    if (oldWidget.videoUrl != widget.videoUrl) {
      _failed = false;
      _syncOwner();
    }
  }

  @override
  void didPushNext() {
    _covered = true;
    _syncOwner();
  }

  @override
  void didPopNext() {
    _covered = false;
    _syncOwner();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
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
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!reduced &&
                widget.gifUrl != null &&
                (widget.videoUrl == null || _failed))
              CachedNetworkImage(
                imageUrl: widget.gifUrl!,
                memCacheWidth: 640,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            if (widget.videoUrl != null && !_failed)
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
  }
}
