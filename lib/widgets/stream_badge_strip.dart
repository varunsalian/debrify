import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/stream_badge_rules.dart';
import '../services/stream_badge_matcher.dart';
import '../services/stream_badges_service.dart';

/// A row of stream badge chips, in ruleset order.
///
/// Rendering follows the Nuvio Badge Studio so a preset looks the same in
/// every client: colours come from the ruleset, never the theme; a rule with
/// an image shows it (its name if the image fails to load), otherwise its
/// name in small bold capitals.
class StreamBadgeStrip extends StatelessWidget {
  final List<StreamBadgeRule> badges;

  /// Chip height; images scale to it, text sizes from it.
  final double height;
  final double spacing;

  const StreamBadgeStrip({
    super.key,
    required this.badges,
    this.height = 16,
    this.spacing = 4,
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
class StreamBadgeStripFor extends StatelessWidget {
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
    this.spacing = 4,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StreamBadgeMatcher>(
      valueListenable: StreamBadgesService.instance.matcher,
      builder: (context, matcher, _) {
        final badges = matcher.matchesFor(name: name, description: description);
        if (badges.isEmpty) return const SizedBox.shrink();
        final strip = StreamBadgeStrip(
          badges: badges,
          height: height,
          spacing: spacing,
        );
        return builder?.call(strip) ?? strip;
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

  /// Dark backing under every image chip — the grey that shields.io-style
  /// badges carry themselves — so transparent artwork stays legible on a
  /// dark row and image and text chips read as one strip.
  static const Color imageBacking = Color(0xFF2A2A2A);

  /// Rulesets are designed for dark source rows, so a rule without a text
  /// colour gets white rather than the theme's foreground.
  static const Color _fallbackTextColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    final image = rule.imageUrl;
    if (image == null) return _textChip();
    final inner = height - 4;
    // No alignment on this container: with one set it would expand to the
    // row's full width instead of hugging the image.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: imageBacking,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: SizedBox(
          height: inner,
          child: CachedNetworkImage(
            imageUrl: image,
            height: inner,
            fit: BoxFit.contain,
            memCacheHeight: (inner * 3).round(),
            fadeInDuration: Duration.zero,
            placeholder: (_, __) => SizedBox(width: inner * 2),
            // The backing already frames the fallback; no second chip.
            errorWidget: (_, __, ___) => _text(fontSize: height * 0.55),
          ),
        ),
      ),
    );
  }

  Widget _textChip() {
    final style = rule.style;
    final fill = style.fills ? rule.tagColor : null;
    final border = style.borders ? (rule.borderColor ?? rule.tagColor) : null;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * 0.35),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(height * 0.25),
        border: border == null ? null : Border.all(color: border, width: 1),
      ),
      child: _text(fontSize: height * 0.6, letterSpacing: 0.3),
    );
  }

  Text _text({required double fontSize, double letterSpacing = 0}) => Text(
    rule.name.toUpperCase(),
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.clip,
    style: TextStyle(
      color: rule.textColor ?? _fallbackTextColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1,
      letterSpacing: letterSpacing,
    ),
  );
}
