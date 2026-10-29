// The controls of the Sports & leagues sheet: a sport row, a switch row, the
// switch itself and the footer buttons.
//
// Presentation layer. Each control is a [SportsFocusPill], so Select, a tap
// and a click all do the same thing, and each reports one intent upward; the
// sheet owns the focus nodes and the writes.
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_labels.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _switchSlide = Duration(milliseconds: 150);

/// One sport in the sheet's left pane (or its top strip on a phone): icon,
/// name and how many of its leagues are on.
class SportsSheetSportRow extends StatelessWidget {
  const SportsSheetSportRow({
    super.key,
    required this.sport,
    required this.on,
    required this.total,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
    this.autofocus = false,
    this.compact = false,
  });

  final SportKind sport;
  final int on;
  final int total;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final bool autofocus;

  /// Sized to its content, for the phone's horizontal strip.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final name = sportsKindName(sport);
    return SportsFocusPill.row(
      label: '$name, $on of $total on',
      selected: selected,
      focusNode: focusNode,
      autofocus: autofocus,
      outlined: compact,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      onPressed: onPressed,
      builder: (_, ink, subtle) {
        final focused = ink == _tokens.focusInk;
        final nameInk = on == 0 && !focused ? _tokens.fgFaint : ink;
        final children = [
          Icon(sportsKindIcon(sport), size: 18, color: nameInk),
          const SizedBox(width: 10),
          if (compact)
            sportsLabelText(name, nameInk, size: 14, weight: FontWeight.w600)
          else
            Expanded(
              child: sportsLabelText(
                name,
                nameInk,
                size: 14,
                weight: FontWeight.w600,
                ellipsize: true,
              ),
            ),
          const SizedBox(width: 10),
          sportsLabelText(
            '$on/$total',
            subtle,
            size: 11,
            weight: FontWeight.w600,
            tabular: true,
          ),
        ];
        return Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: children,
        );
      },
    );
  }
}

/// A row that turns something on or off: title, optional second line, and
/// the switch. The whole row is the control.
class SportsSheetSwitchRow extends StatelessWidget {
  const SportsSheetSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.focusNode,
    required this.onToggle,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final FocusNode focusNode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => SportsFocusPill(
    label: subtitle == null ? title : '$title, $subtitle',
    toggled: value,
    focusNode: focusNode,
    style: const SportsFocusPillStyle(radius: 10),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    onPressed: onToggle,
    builder: (_, ink, subtle) => Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              sportsLabelText(
                title,
                ink,
                size: 14,
                weight: FontWeight.w600,
                ellipsize: true,
              ),
              if (subtitle case final line?) ...[
                const SizedBox(height: 2),
                sportsLabelText(line, subtle, size: 12, ellipsize: true),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        SportsSwitchGlyph(value: value),
      ],
    ),
  );
}

/// The painted switch: accent track with the knob right when on.
class SportsSwitchGlyph extends StatelessWidget {
  const SportsSwitchGlyph({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final slide = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _switchSlide;
    return AnimatedContainer(
      duration: slide,
      width: 42,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? _tokens.accent : _tokens.hairline2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AnimatedAlign(
        duration: slide,
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: value ? Colors.white : const Color(0xFFC7D1E3),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// A footer or header button; [primary] fills it with the accent.
class SportsSheetButton extends StatelessWidget {
  const SportsSheetButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;

  /// An icon-only button announces [label] instead.
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final pill = SportsFocusPill(
      label: label,
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 16 : 0),
      style: SportsFocusPillStyle(
        radius: 10,
        outlined: !primary,
        restColor: primary ? _tokens.accent : null,
      ),
      onPressed: onPressed,
      builder: (_, ink, _) => Center(
        widthFactor: icon == null ? 1 : null,
        child: icon == null
            ? sportsLabelText(label, ink, weight: FontWeight.w700)
            : Icon(icon, size: 18, color: ink),
      ),
    );
    return icon == null ? pill : SizedBox(width: 44, child: pill);
  }
}
