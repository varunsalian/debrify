// The shared visual atoms of the sports board: the identity artwork (team
// crest, channel logo), the focus pill every board control is built from, and
// the type ramp they both draw.
//
// Presentation layer. The artwork widgets paint a network image over a neutral
// plate and fall back to text (team abbreviation, channel initials) while the
// image is absent, loading or failed, so a board row never shows an empty hole
// and never waits on the network to lay out; both are decorative and excluded
// from semantics because the row that owns them already announces the name.
// The pill and the label exist so the card and the details panel cannot drift
// apart in focus colour, ink, radius or size ramp.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _tokens = IptvStyleTokens.spotlight;
const _focus = Duration(milliseconds: 120);

/// The smallest control the board accepts: a D-pad target a remote can hit.
const _minControlHeight = 44.0;

/// One line of the board's type ramp, so the card and the panel cannot drift
/// apart in size, weight or emphasis token.
Widget sportsLabelText(
  String data,
  Color color, {
  double size = 13,
  FontWeight weight = FontWeight.w400,
  double? height,
  double? tracking,
  int maxLines = 1,
  bool ellipsize = false,
  bool tabular = false,
}) => Text(
  data,
  maxLines: maxLines,
  overflow: ellipsize ? TextOverflow.ellipsis : TextOverflow.clip,
  style: TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: tracking,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : const [],
  ),
);

/// A circle in the team's own colour holding its logo, or the team's
/// abbreviation while the logo is unavailable (no url, loading, or failed).
class SportsTeamCrest extends StatelessWidget {
  const SportsTeamCrest({super.key, required this.team, this.size = 28});

  final SportsTeam team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill = team.color == null ? _tokens.panel : Color(team.color!);
    final abbreviation = team.abbreviation.trim().isEmpty
        ? team.name
        : team.abbreviation.trim();
    final fallback = FittedBox(
      fit: BoxFit.scaleDown,
      child: sportsLabelText(
        abbreviation,
        _tokens.fg,
        size: size * 0.40,
        weight: FontWeight.w700,
        height: 1,
      ),
    );
    return _ImagePlate(
      side: size,
      radius: size / 2,
      padding: size * 0.16,
      color: fill,
      circle: true,
      fallback: fallback,
      imageUrl: team.logoUrl,
      memCacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round(),
    );
  }
}

/// A channel's logo on a rounded plate, or the channel's initials when the
/// playlist carries no logo.
class SportsChannelLogo extends StatelessWidget {
  const SportsChannelLogo({super.key, required this.name, this.logoUrl});

  final String name;
  final String? logoUrl;

  /// `'Sky Sports Main Event'` → `'SS'`; a one-word name gives its initial.
  static String initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    return words.length == 1
        ? words.first[0].toUpperCase()
        : '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => _ImagePlate(
    side: 40,
    radius: 9,
    padding: 5,
    color: Colors.white.withValues(alpha: 0.06),
    fallback: sportsLabelText(
      initials(name),
      _tokens.fgMid,
      size: 12,
      weight: FontWeight.w700,
    ),
    imageUrl: logoUrl,
    memCacheHeight: 80,
  );
}

/// The plate both logos sit on: circular or rounded, [fallback] underneath,
/// the cached image once it arrives.
class _ImagePlate extends StatelessWidget {
  const _ImagePlate({
    required this.side,
    required this.radius,
    required this.padding,
    required this.color,
    required this.fallback,
    required this.imageUrl,
    required this.memCacheHeight,
    this.circle = false,
  });

  final double side;
  final double radius;
  final double padding;
  final Color color;
  final Widget fallback;
  final String? imageUrl;
  final int memCacheHeight;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final logo = imageUrl?.trim();
    return Semantics(
      excludeSemantics: true,
      child: Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: color,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: logo == null || logo.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: logo,
                fit: BoxFit.contain,
                memCacheHeight: memCacheHeight,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// How a [SportsFocusPill] paints its four states.
///
/// Colours left null resolve to the Spotlight tokens at build time, so the
/// common row never restates them; the board card overrides only the surface
/// ramp its panel uses.
@immutable
class SportsFocusPillStyle {
  const SportsFocusPillStyle({
    this.radius = 11,
    this.restColor,
    this.hoverColor,
    this.focusedFill,
    this.focusedBorderColor,
    this.focusedBorderWidth = 1,
    this.glow = false,
    this.scale = 1,
    this.outlined = false,
    this.invertInkOnFocus = true,
  });

  /// Guide and follow rows: hairline at rest, solid light fill when focused.
  static const row = SportsFocusPillStyle(outlined: true);

  /// The board card: its own navy ramp, lifted and outlined in white.
  static const card = SportsFocusPillStyle(
    radius: 14,
    restColor: Color(0xFF10243A),
    hoverColor: Color(0xFF122A45),
    focusedFill: Color(0xFF143052),
    focusedBorderColor: Colors.white,
    focusedBorderWidth: 2,
    glow: true,
    scale: 1.035,
    invertInkOnFocus: false,
  );

  final double radius;
  final Color? restColor;
  final Color? hoverColor;
  final Color? focusedFill;
  final Color? focusedBorderColor;
  final double focusedBorderWidth;

  /// Accent bloom behind the surface while focused.
  final bool glow;

  /// Grown while focused, for card-sized surfaces.
  final double scale;

  /// Hairline border at rest, for rows that are not solid panels.
  final bool outlined;

  /// Rows invert their ink on the light fill; dark surfaces keep it.
  final bool invertInkOnFocus;
}

/// The Spotlight focus pill: one focusable, D-pad-activatable surface that
/// copies the spotlight rail's rows — solid light fill and inverted ink when
/// focused, a selected tint behind a 1 px accent hairline, and
/// `Scrollable.ensureVisible` so a focused control is never off-screen.
///
/// [builder] paints itself with the ink the pill state asks for, so every
/// control inverts together under D-pad focus. Key repeats are swallowed
/// rather than re-fired: a held OK activates exactly once.
class SportsFocusPill extends StatefulWidget {
  const SportsFocusPill({
    super.key,
    required this.label,
    required this.onPressed,
    required this.builder,
    this.style = const SportsFocusPillStyle(),
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 11),
  });

  /// One control of the details panel: the 44 px minimum a remote needs, a
  /// hairline at rest and a solid light fill under focus. [outlined] rows keep
  /// that hairline while they are unfilled, which is how the panel separates
  /// confirmed guide rows from merely possible channels.
  SportsFocusPill.row({
    super.key,
    required this.label,
    required this.onPressed,
    required this.builder,
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
    this.height = _minControlHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: 11),
    bool outlined = true,
  }) : style = SportsFocusPillStyle(outlined: outlined);

  /// What a screen reader hears instead of the painted contents.
  final String label;
  final VoidCallback onPressed;
  final Widget Function(BuildContext context, Color ink, Color subtle) builder;
  final SportsFocusPillStyle style;

  /// Supplied by a list that has to keep focus across rebuilds; the pill owns
  /// its own node otherwise.
  final FocusNode? focusNode;
  final bool autofocus;
  final bool selected;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  State<SportsFocusPill> createState() => _SportsFocusPillState();
}

class _SportsFocusPillState extends State<SportsFocusPill> {
  FocusNode? _ownNode;
  bool _focused = false;
  bool _hovered = false;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!isActivateOrSpaceKey(event.logicalKey)) return KeyEventResult.ignored;
    // Repeats are swallowed, not re-fired: a held OK acts once.
    if (event is KeyDownEvent) widget.onPressed();
    return KeyEventResult.handled;
  }

  void _onFocusChange(bool focused) {
    if (mounted) setState(() => _focused = focused);
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: _focus,
      );
    });
  }

  BoxDecoration _decoration() {
    final style = widget.style;
    final base = style.restColor ?? Colors.transparent;
    final fill = style.focusedFill ?? _tokens.focusFill!;
    return BoxDecoration(
      color: _focused
          ? fill
          : _hovered
          ? Color.alphaBlend(style.hoverColor ?? _tokens.focusTint, base)
          : widget.selected
          ? Color.alphaBlend(_tokens.selectedTint, base)
          : base,
      borderRadius: BorderRadius.circular(style.radius),
      boxShadow: _focused && style.glow
          ? [
              BoxShadow(
                color: _tokens.accent.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ]
          : const [],
      border: Border.all(
        width: _focused ? style.focusedBorderWidth : 1,
        color: _focused
            ? (style.focusedBorderColor ?? fill)
            : widget.selected
            ? _tokens.accent.withValues(alpha: 0.5)
            : style.outlined
            ? _tokens.hairline2
            : Colors.transparent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final inverted = _focused && style.invertInkOnFocus;
    final ink = inverted ? _tokens.focusInk! : _tokens.fg;
    return Semantics(
      button: true,
      selected: widget.selected,
      excludeSemantics: true,
      label: widget.label,
      onTap: widget.onPressed,
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onFocusChange: _onFocusChange,
        onKeyEvent: _onKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onPressed,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedScale(
              scale: _focused ? style.scale : 1,
              duration: _focus,
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: _focus,
                height: widget.height,
                padding: widget.padding,
                decoration: _decoration(),
                child: widget.builder(
                  context,
                  ink,
                  inverted
                      ? _tokens.focusInk!.withValues(alpha: 0.75)
                      : _tokens.fgDim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
