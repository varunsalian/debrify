import 'package:flutter/material.dart';

/// The swatch a user can choose, stored by **id**.
///
/// Never by hex. A stored `#FF6B35` cannot survive a palette revision, cannot
/// be shown as "Ember" in a list, and makes "which Look am I on" unanswerable —
/// an id can do all three, and an id nobody recognises falls back to the
/// theme's own colour instead of painting something arbitrary.
class Swatch {
  final String id;
  final String label;
  final Color color;

  const Swatch(this.id, this.label, this.color);
}

/// Fifty colours, chosen so that any of them is legible as a MARK on a dark or
/// light ground: nothing below roughly 35% luminance, nothing so pale it
/// disappears on white.
///
/// This palette is deliberately only offered for colours that sit ON surfaces —
/// accent, focus, state, callout. The grounds and the ink are a legibility
/// SYSTEM, not four independent choices, and fifty swatches across four of them
/// is mostly combinations where the text vanishes. Those stay with the Look.
abstract final class ThemePalette {
  static const List<Swatch> all = [
    // Reds and oranges
    Swatch('crimson', 'Crimson', Color(0xFFE23D4C)),
    Swatch('ember', 'Ember', Color(0xFFFF6B35)),
    Swatch('rust', 'Rust', Color(0xFFC65A2E)),
    Swatch('coral', 'Coral', Color(0xFFFF7A6B)),
    Swatch('salmon', 'Salmon', Color(0xFFFF8E7A)),
    Swatch('brick', 'Brick', Color(0xFFB4463C)),
    Swatch('cherry', 'Cherry', Color(0xFFE8455F)),

    // Ambers and yellows
    Swatch('amber', 'Amber', Color(0xFFFFB020)),
    Swatch('gold', 'Gold', Color(0xFFE0A526)),
    Swatch('honey', 'Honey', Color(0xFFF0C15C)),
    Swatch('citrus', 'Citrus', Color(0xFFF5D547)),
    Swatch('sand', 'Sand', Color(0xFFD9BC8C)),
    Swatch('brass', 'Brass', Color(0xFFBE9B5C)),

    // Greens
    Swatch('lime', 'Lime', Color(0xFFA8D84A)),
    Swatch('fern', 'Fern', Color(0xFF6BBF59)),
    Swatch('emerald', 'Emerald', Color(0xFF10B981)),
    Swatch('jade', 'Jade', Color(0xFF35B39B)),
    Swatch('sage', 'Sage', Color(0xFF93B78F)),
    Swatch('moss', 'Moss', Color(0xFF7A9A5B)),
    Swatch('mint', 'Mint', Color(0xFF6FE0B0)),

    // Teals and cyans
    Swatch('teal', 'Teal', Color(0xFF2CB5A0)),
    Swatch('lagoon', 'Lagoon', Color(0xFF3FBFCF)),
    Swatch('cyan', 'Cyan', Color(0xFF4CC9E0)),
    Swatch('aqua', 'Aqua', Color(0xFF6FD8D2)),
    Swatch('slateblue', 'Slate Blue', Color(0xFF6E8CA8)),

    // Blues
    Swatch('azure', 'Azure', Color(0xFF3B9EFF)),
    Swatch('sky', 'Sky', Color(0xFF60A5FA)),
    Swatch('cobalt', 'Cobalt', Color(0xFF4666D6)),
    Swatch('indigo', 'Indigo', Color(0xFF6366F1)),
    Swatch('steel', 'Steel', Color(0xFF7C93B8)),
    Swatch('denim', 'Denim', Color(0xFF5578A8)),
    Swatch('ice', 'Ice', Color(0xFF9BC7E8)),

    // Purples and magentas
    Swatch('violet', 'Violet', Color(0xFF8B5CF6)),
    Swatch('lavender', 'Lavender', Color(0xFFB09CE8)),
    Swatch('orchid', 'Orchid', Color(0xFFC77DD8)),
    Swatch('magenta', 'Magenta', Color(0xFFE056B4)),
    Swatch('fuchsia', 'Fuchsia', Color(0xFFF061A8)),
    Swatch('plum', 'Plum', Color(0xFF9B6FA8)),
    Swatch('mauve', 'Mauve', Color(0xFFC79BC0)),

    // Pinks
    Swatch('rose', 'Rose', Color(0xFFF2789A)),
    Swatch('blush', 'Blush', Color(0xFFE8A0B4)),
    Swatch('peach', 'Peach', Color(0xFFFFB08A)),

    // Neutrals — a mark can legitimately be colourless.
    Swatch('white', 'White', Color(0xFFFFFFFF)),
    Swatch('bone', 'Bone', Color(0xFFEDE7DC)),
    Swatch('silver', 'Silver', Color(0xFFC7CBD1)),
    Swatch('ash', 'Ash', Color(0xFF9AA0A6)),
    Swatch('graphite', 'Graphite', Color(0xFF6E747A)),

    // A few saturated statements
    Swatch('electric', 'Electric', Color(0xFF00E5FF)),
    Swatch('acid', 'Acid', Color(0xFFC6FF00)),
    Swatch('hotpink', 'Hot Pink', Color(0xFFFF2D8A)),
  ];

  /// Surfaces — grounds, panes and fills.
  ///
  /// A SEPARATE set, because [all] is a palette of marks: everything in it is
  /// above 5% luminance so it can be found on a dark ground, which means it
  /// contains nothing you could actually use as a background. Offering it for
  /// Background was offering a choice between fifty bright colours.
  ///
  /// Runs from near-black to off-white deliberately. Light grounds are the
  /// harder case — see `kDetailThemesShipped`, which withholds two themes for
  /// exactly this — so the ink floor in `DetailTheme.withTokens` is what makes
  /// them safe rather than their absence from this list.
  static const List<Swatch> grounds = [
    Swatch('void', 'Void', Color(0xFF000000)),
    Swatch('ink_black', 'Ink', Color(0xFF08080A)),
    Swatch('charcoal', 'Charcoal', Color(0xFF121214)),
    Swatch('slate', 'Slate', Color(0xFF17181C)),
    Swatch('gunmetal', 'Gunmetal', Color(0xFF1E2126)),
    Swatch('navy_deep', 'Deep Navy', Color(0xFF0D1420)),
    Swatch('forest_deep', 'Deep Forest', Color(0xFF0D1712)),
    Swatch('wine_deep', 'Deep Wine', Color(0xFF1A0E12)),
    Swatch('espresso', 'Espresso', Color(0xFF171210)),
    Swatch('storm', 'Storm', Color(0xFF262A30)),
    Swatch('stone', 'Stone', Color(0xFF3A3D42)),
    Swatch('putty', 'Putty', Color(0xFF6E6A64)),
    Swatch('linen', 'Linen', Color(0xFFE8E4DC)),
    Swatch('paper', 'Paper', Color(0xFFF4F2ED)),
    Swatch('snow', 'Snow', Color(0xFFFFFFFF)),
  ];

  /// Text. A short list on purpose — ink is a legibility decision with a right
  /// answer per ground, not a palette.
  static const List<Swatch> inks = [
    Swatch('pure_white', 'White', Color(0xFFFFFFFF)),
    Swatch('warm_white', 'Warm White', Color(0xFFF5F0E8)),
    Swatch('cool_white', 'Cool White', Color(0xFFEDF2F7)),
    Swatch('near_black', 'Near Black', Color(0xFF0E0E10)),
    Swatch('soft_black', 'Soft Black', Color(0xFF1C1A18)),
  ];

  static final Map<String, Swatch> _byId = {
    for (final s in [...all, ...grounds, ...inks]) s.id: s,
  };

  /// The colour for [id], or null when nothing matches.
  ///
  /// Null rather than a default: the caller knows what the theme's own value
  /// is, and falling back to THAT is what keeps a dropped swatch invisible
  /// instead of turning the accent an arbitrary colour.
  static Color? colorOf(String? id) => id == null ? null : _byId[id]?.color;

  static Swatch? byId(String? id) => id == null ? null : _byId[id];
}
