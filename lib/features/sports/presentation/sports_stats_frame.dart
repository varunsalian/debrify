// The shared chrome of the match stats page: the card every section sits in,
// the focusable row a remote walks through, and the two team colours the
// sections draw with.
//
// Presentation layer. Stats rows are read-only, but on a TV the only way to
// scroll a page is to move focus, so every row takes D-pad focus and lights
// a soft tint; Flutter's directional traversal scrolls it into view. The tint only shows in Flutter's
// key highlight mode, so a touch screen never sees the autofocused row lit.
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _focusDuration = Duration(milliseconds: 120);

/// Used when a side sends no colour, or none that reads on the dark panel.
const Color sportsStatsHomeFallback = Color(0xFF0A84FF);
const Color sportsStatsAwayFallback = Color(0xFFFF9F0A);

/// One titled section of the stats page.
class SportsStatsCard extends StatelessWidget {
  const SportsStatsCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
    decoration: BoxDecoration(
      color: _tokens.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _tokens.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Row(
            children: [
              Expanded(
                child: sportsLabelText(
                  title,
                  _tokens.fg,
                  size: 15,
                  weight: FontWeight.w700,
                  maxLines: 2,
                  ellipsize: true,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}

/// A read-only row a D-pad can land on. [label] is what a screen reader
/// announces for the whole row.
class SportsStatsFocusRow extends StatefulWidget {
  const SportsStatsFocusRow({
    super.key,
    required this.label,
    required this.child,
    this.autofocus = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
  });

  final String label;
  final Widget child;
  final bool autofocus;
  final EdgeInsetsGeometry padding;

  @override
  State<SportsStatsFocusRow> createState() => _SportsStatsFocusRowState();
}

class _SportsStatsFocusRowState extends State<SportsStatsFocusRow> {
  bool _focused = false;

  /// Touch focuses the first row too (it autofocuses), but only keys and a
  /// remote should see a row light up: on a phone it reads as a selection.
  bool _keyHighlight = _keysHighlight();

  static bool _keysHighlight() =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode mode) {
    final keys = mode == FocusHighlightMode.traditional;
    if (keys != _keyHighlight && mounted) setState(() => _keyHighlight = keys);
  }

  void _onFocusChange(bool focused) => setState(() => _focused = focused);

  @override
  Widget build(BuildContext context) {
    final lit = _focused && _keyHighlight;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: widget.label,
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: _onFocusChange,
        child: AnimatedContainer(
          duration: _focusDuration,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: lit ? _tokens.focusTint : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: lit ? _tokens.hairline2 : Colors.transparent,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The colours the two sides draw with: each side's own colour when it reads
/// on the dark panel, else its alternate, else a lightened own colour; and an
/// away colour that cannot be mistaken for the home one.
({Color home, Color away}) sportsStatsColors(
  SportsMatchSide home,
  SportsMatchSide away,
) {
  final homeColor =
      _readable([home.color, home.alternateColor]) ?? sportsStatsHomeFallback;
  final awayCandidates = [away.color, away.alternateColor];
  final awayColor =
      _readable(awayCandidates, distinctFrom: homeColor) ??
      (_distinct(sportsStatsAwayFallback, homeColor)
          ? sportsStatsAwayFallback
          : sportsStatsHomeFallback);
  return (home: homeColor, away: awayColor);
}

Color? _readable(List<int?> candidates, {Color? distinctFrom}) {
  final colors = [
    for (final value in candidates)
      if (value != null) Color(value),
  ];
  bool fits(Color c) => distinctFrom == null || _distinct(c, distinctFrom);
  // The candidate that needs the least lightening wins, the side's own
  // colour on a tie: a near-black primary does not wash out to grey when
  // the alternate already reads (Houston's navy loses to its red).
  for (final lift in const [0.0, 0.1, 0.2, 0.3, 0.45, 0.6]) {
    for (final color in colors) {
      final lifted = Color.lerp(color, Colors.white, lift)!;
      if (_readsOnPanel(lifted) && fits(lifted)) return lifted;
    }
  }
  return null;
}

/// Readable as bold text and bars on the dark panel (about 4:1 contrast
/// against its luminance of ~0.009) without being near-white noise.
bool _readsOnPanel(Color color) {
  final luminance = color.computeLuminance();
  return luminance >= 0.18 && luminance <= 0.85;
}

/// Far enough apart in RGB that two bars side by side read as two teams.
bool _distinct(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return dr * dr + dg * dg + db * db >= 90 * 90;
}
