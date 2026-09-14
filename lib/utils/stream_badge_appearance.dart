import 'package:flutter/painting.dart';

import '../models/stream_badge_rules.dart';

/// Shared display colours for Flutter chips and native TV badge payloads.
/// Image pixels keep their original colours; text colour is only for labels.
class StreamBadgeAppearance {
  StreamBadgeAppearance(StreamBadgeRule rule)
    : background = Color.alphaBlend(
        (rule.style.fills ? rule.tagColor : null) ?? darkBacking,
        darkBacking,
      ),
      border = rule.style.borders ? (rule.borderColor ?? rule.tagColor) : null {
    final requested = rule.textColor ?? const Color(0xFFFFFFFF);
    final visible = Color.alphaBlend(requested, background);
    foreground = _contrast(visible, background) >= 4.5
        ? requested
        : _contrast(const Color(0xFF000000), background) >=
              _contrast(const Color(0xFFFFFFFF), background)
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
  }

  // Composite translucent fills against a stable surface so row focus cannot
  // change the contrast of either artwork or its loading/error label.
  static const darkBacking = Color(0xFF2A2A2A);
  final Color background;
  final Color? border;
  late final Color foreground;

  /// A quiet edge keeps light artwork tiles distinct on the white TV cursor.
  Color get outline =>
      border ??
      (background.computeLuminance() > 0.5
          ? const Color(0x24000000)
          : const Color(0x24FFFFFF));

  static double _contrast(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
  }

  Map<String, Object?> nativeBadge(StreamBadgeRule rule) => {
    'label': rule.name,
    if (rule.imageUrl != null) 'imageUrl': rule.imageUrl,
    'textColor': foreground.toARGB32(),
    'fillColor': background.toARGB32(),
    'borderColor': outline.toARGB32(),
  };
}
