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
class StreamBadgeStrip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final b in badges) StreamBadgeChip(rule: b, height: height),
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

  const StreamBadgeChip({super.key, required this.rule, this.height = 16});

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
            minWidth: inner,
            maxWidth: height * 7,
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
                  placeholder: (_, __) => _imageLabel(appearance),
                  // The backing already frames the fallback; no second chip.
                  errorWidget: (_, __, ___) => isBadgeBitmapUrl(image)
                      ? _imageLabel(appearance)
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
    frameBuilder: (_, child, frame, synchronous) =>
        frame == null ? _imageLabel(appearance) : child,
    errorBuilder: (_, __, ___) => _imageLabel(appearance),
  );

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
  });
  final StreamBadgeMatcher matcher;
  final String name;
  final String? description;
  final Widget Function(List<StreamBadgeRule>) render;
  @override
  State<_MatchedBadgeStrip> createState() => _MatchedBadgeStripState();
}

class _MatchedBadgeStripState extends State<_MatchedBadgeStrip> {
  List<StreamBadgeRule> _badges = const [];
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    final cached = widget.matcher.cachedMatchesFor(
      name: widget.name,
      description: widget.description,
    );
    if (cached != null) {
      _badges = cached;
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
      setState(() => _badges = result.badges);
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.render(_badges);
}
