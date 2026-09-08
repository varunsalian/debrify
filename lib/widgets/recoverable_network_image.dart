import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Retries a failed mounted image twice. A scroll/remount must not be required
/// to recover from a transient download or corrupt cached image.
class RecoverableNetworkImage extends StatefulWidget {
  const RecoverableNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.cacheManager,
    this.memCacheWidth,
    this.color,
    this.colorBlendMode,
    this.fadeInDuration = const Duration(milliseconds: 180),
    this.fadeOutDuration = const Duration(milliseconds: 100),
    required this.placeholder,
    required this.errorWidget,
  });
  final String imageUrl;
  final BoxFit? fit;
  final BaseCacheManager? cacheManager;
  final int? memCacheWidth;
  final Color? color;
  final BlendMode? colorBlendMode;
  final Duration fadeInDuration, fadeOutDuration;
  final PlaceholderWidgetBuilder placeholder;
  final LoadingErrorWidgetBuilder errorWidget;
  @override
  State<RecoverableNetworkImage> createState() =>
      _RecoverableNetworkImageState();
}

class _RecoverableNetworkImageState extends State<RecoverableNetworkImage> {
  Timer? _timer;
  int _attempt = 0;
  int _generation = 0;
  int _imageKey = 0;
  void _failed(Object error) {
    if (!mounted || _timer != null || _attempt >= 2) return;
    final generation = _generation;
    final url = widget.imageUrl;
    _timer = Timer(Duration(seconds: ++_attempt * 2), () async {
      try {
        // Transport failures need a fresh read, not deletion of a good file
        // another consumer may have downloaded in the meantime. Decode errors
        // can come from corrupt disk data and do require eviction.
        if (error is! HttpException &&
            error is! SocketException &&
            error is! TimeoutException) {
          await CachedNetworkImage.evictFromCache(
            url,
            cacheManager: widget.cacheManager,
          ).timeout(const Duration(seconds: 2));
        }
      } catch (_) {}
      if (!mounted || generation != _generation) return;
      _timer = null;
      setState(() => _imageKey++);
    });
  }

  @override
  void didUpdateWidget(RecoverableNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.cacheManager != widget.cacheManager) {
      _generation++;
      _timer?.cancel();
      _timer = null;
      _attempt = 0;
      _imageKey++;
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    key: ValueKey((widget.imageUrl, _imageKey)),
    imageUrl: widget.imageUrl,
    fit: widget.fit,
    cacheManager: widget.cacheManager,
    memCacheWidth: widget.memCacheWidth,
    color: widget.color,
    colorBlendMode: widget.colorBlendMode,
    fadeInDuration: widget.fadeInDuration,
    fadeOutDuration: widget.fadeOutDuration,
    placeholder: widget.placeholder,
    errorWidget: widget.errorWidget,
    errorListener: _failed,
  );
}
