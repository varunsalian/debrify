import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/stream_badge_rules.dart';
import '../services/stream_badge_matcher.dart';
import '../services/stream_badges_service.dart';
import '../services/stream_badge_svg_image.dart';
import '../utils/stream_badge_appearance.dart';
import '../utils/stream_badge_svg.dart';

/// A row of stream badge chips, in ruleset order.
///
/// Uses the preset's fill and border for both text and image chips. Artwork
/// keeps its original colours; labels receive a contrast-safe fallback.
class StreamBadgeStrip extends StatefulWidget {
  final List<StreamBadgeRule> badges;

  /// Chip height; images scale to it, text sizes from it.
  final double height;
  final double spacing;

  const StreamBadgeStrip({
    super.key,
    required this.badges,
    this.height = 16,
    this.spacing = 6,
  });

  @override
  State<StreamBadgeStrip> createState() => _StreamBadgeStripState();
}

class _StreamBadgeStripState extends State<StreamBadgeStrip> {
  final _pending = <String>{};
  Timer? _deadline;
  bool _revealed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _generation++;
    _deadline?.cancel();
    _pending.clear();
    _pending.addAll(widget.badges.map((b) => b.imageUrl).whereType<String>());
    _revealed = _pending.isEmpty;
    if (!_revealed) {
      // A slow or unavailable artwork host must never hide the labels forever.
      _deadline = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _revealed = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant StreamBadgeStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.badges, oldWidget.badges)) _reset();
  }

  void _ready(String url, int generation) {
    if (generation != _generation || !_pending.contains(url)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || !_pending.remove(url)) {
        return;
      }
      if (_pending.isEmpty) {
        _deadline?.cancel();
        setState(() => _revealed = true);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _deadline?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.badges.isEmpty) return const SizedBox.shrink();
    final generation = _generation;
    return Stack(
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: _revealed ? 1 : 0,
          child: Wrap(
            spacing: widget.spacing,
            runSpacing: widget.spacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final b in widget.badges)
                StreamBadgeChip(
                  rule: b,
                  height: widget.height,
                  onImageReady: b.imageUrl == null
                      ? null
                      : () => _ready(b.imageUrl!, generation),
                ),
            ],
          ),
        ),
        if (!_revealed)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The strip for one stream, driven by the live ruleset: rebuilds when a
/// preset is imported, toggled or removed.
///
/// [name] and [description] are the two halves of
/// [StreamBadgeMatcher.matchesFor]; a rule fires when it matches either.
class StreamBadgeStripFor extends StatefulWidget {
  final String name;
  final String? description;
  final double height;
  final double spacing;

  /// Wraps a non-empty strip (e.g. to add padding); not called when there
  /// are no badges, so callers pay no layout for unmatched streams.
  final Widget Function(Widget strip)? builder;

  const StreamBadgeStripFor({
    super.key,
    required this.name,
    this.description,
    this.height = 16,
    this.spacing = 6,
    this.builder,
  });

  @override
  State<StreamBadgeStripFor> createState() => _StreamBadgeStripForState();
}

class _StreamBadgeStripForState extends State<StreamBadgeStripFor> {
  List<StreamBadgeRule>? _renderedBadges;
  Widget? _strip;

  @override
  void didUpdateWidget(covariant StreamBadgeStripFor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.height != widget.height ||
        oldWidget.spacing != widget.spacing ||
        oldWidget.builder != widget.builder) {
      _strip = null;
    }
  }

  Widget _render(List<StreamBadgeRule> badges) {
    if (badges.isEmpty) return const SizedBox.shrink();
    if (!identical(badges, _renderedBadges) || _strip == null) {
      _renderedBadges = badges;
      final strip = StreamBadgeStrip(
        badges: badges,
        height: widget.height,
        spacing: widget.spacing,
      );
      _strip = widget.builder?.call(strip) ?? strip;
    }
    // Focus-only parent rebuilds reuse the actual widget tree, so the image
    // widgets do not need to rebuild or re-resolve their image providers.
    return _strip!;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StreamBadgeMatcher>(
      valueListenable: StreamBadgesService.instance.matcher,
      builder: (context, matcher, _) {
        return _MatchedBadgeStrip(
          key: ValueKey((matcher, widget.name, widget.description)),
          matcher: matcher,
          name: widget.name,
          description: widget.description,
          render: _render,
          loading: () {
            final placeholder = SizedBox(
              height: widget.height,
              width: widget.height * 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
            return widget.builder?.call(placeholder) ?? placeholder;
          },
        );
      },
    );
  }
}

/// One chip. `filled` paints the tag colour, `outlined` draws the border
/// colour (the tag colour when unset) and `filled and bordered` does both.
class StreamBadgeChip extends StatelessWidget {
  final StreamBadgeRule rule;
  final double height;

  final VoidCallback? onImageReady;
  const StreamBadgeChip({
    super.key,
    required this.rule,
    this.height = 16,
    this.onImageReady,
  });

  /// Fallback surface when the preset does not supply a filled background.
  static const Color imageBacking = StreamBadgeAppearance.darkBacking;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: rule.name,
      image: rule.imageUrl != null,
      child: ExcludeSemantics(
        child: Tooltip(
          message: rule.name,
          // Mouse hover still works; touch gestures belong to the source row.
          triggerMode: TooltipTriggerMode.manual,
          excludeFromSemantics: true,
          child: _buildChip(),
        ),
      ),
    );
  }

  Widget _buildChip() {
    final image = rule.imageUrl;
    final appearance = StreamBadgeAppearance(rule);
    if (image == null) return _textChip(appearance);
    final inner = height - 4;
    // The image and its fallback share one slot; decoding cannot reflow Wrap.
    final slotWidth = (rule.name.runes.length * height * .34)
        .clamp(inner * 1.5, height * 7)
        .toDouble();
    // No alignment on this container: with one set it would expand to the
    // row's full width instead of hugging the image.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appearance.background,
        borderRadius: BorderRadius.circular(height * 0.23),
        border: Border.all(color: appearance.outline, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: slotWidth,
            maxWidth: slotWidth,
            minHeight: inner,
            maxHeight: inner,
          ),
          child: isBadgeSvgUrl(image)
              ? _svgImage(image, inner, appearance)
              : CachedNetworkImage(
                  imageUrl: image,
                  height: inner,
                  fit: BoxFit.contain,
                  memCacheHeight: (inner * 3).round(),
                  fadeInDuration: Duration.zero,
                  imageBuilder: (_, provider) {
                    onImageReady?.call();
                    return Image(
                      image: provider,
                      height: inner,
                      fit: BoxFit.contain,
                    );
                  },
                  placeholder: (_, __) => _imageLabel(appearance),
                  // The backing already frames the fallback; no second chip.
                  errorWidget: (_, __, ___) => isBadgeBitmapUrl(image)
                      ? _failedImage(appearance)
                      : _svgImage(image, inner, appearance),
                ),
        ),
      ),
    );
  }

  Widget _svgImage(
    String url,
    double inner,
    StreamBadgeAppearance appearance,
  ) => Image(
    image: StreamBadgeSvgImage(
      url,
      maxWidth: (height * 7 * 3).round(),
      maxHeight: (inner * 3).round(),
    ),
    height: inner,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    frameBuilder: (_, child, frame, synchronous) {
      if (frame == null) return _imageLabel(appearance);
      onImageReady?.call();
      return child;
    },
    errorBuilder: (_, __, ___) => _failedImage(appearance),
  );

  Widget _failedImage(StreamBadgeAppearance appearance) {
    onImageReady?.call();
    return _imageLabel(appearance);
  }

  Widget _imageLabel(StreamBadgeAppearance appearance) => Align(
    widthFactor: 1,
    heightFactor: 1,
    child: _text(appearance, fontSize: height * 0.55),
  );

  Widget _textChip(StreamBadgeAppearance appearance) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * 0.35),
      constraints: BoxConstraints(maxWidth: height * 10),
      decoration: BoxDecoration(
        color: appearance.background,
        borderRadius: BorderRadius.circular(height * 0.23),
        border: Border.all(color: appearance.outline, width: 1),
      ),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: _text(appearance, fontSize: height * 0.6, letterSpacing: 0.3),
      ),
    );
  }

  Text _text(
    StreamBadgeAppearance appearance, {
    required double fontSize,
    double letterSpacing = 0,
  }) => Text(
    rule.name.toUpperCase(),
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: appearance.foreground,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1,
      letterSpacing: letterSpacing,
    ),
  );
}

class _MatchedBadgeStrip extends StatefulWidget {
  const _MatchedBadgeStrip({
    super.key,
    required this.matcher,
    required this.name,
    required this.description,
    required this.render,
    required this.loading,
  });
  final StreamBadgeMatcher matcher;
  final String name;
  final String? description;
  final Widget Function(List<StreamBadgeRule>) render;
  final Widget Function() loading;
  @override
  State<_MatchedBadgeStrip> createState() => _MatchedBadgeStripState();
}

class _MatchedBadgeStripState extends State<_MatchedBadgeStrip> {
  List<StreamBadgeRule> _badges = const [];
  Timer? _retry;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final cached = widget.matcher.cachedMatchesFor(
      name: widget.name,
      description: widget.description,
    );
    if (cached != null) {
      _badges = cached;
      _loading = false;
    } else {
      _request();
    }
  }

  Future<void> _request() async {
    final result = await widget.matcher.matchResultFor(
      name: widget.name,
      description: widget.description,
    );
    if (!mounted) return;
    if (result.status == StreamBadgeMatchStatus.deferred) {
      _retry = Timer(const Duration(milliseconds: 250), _request);
    } else if (result.status == StreamBadgeMatchStatus.resolved) {
      setState(() {
        _badges = result.badges;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _loading && !widget.matcher.isEmpty
      ? widget.loading()
      : widget.render(_badges);
}
