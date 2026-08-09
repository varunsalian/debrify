import 'package:flutter/material.dart';

import '../tv_text_field.dart';

/// Shared search header for the "Browse" sidebar tabs (IPTV, YouTube).
///
/// Matches the styling of the Stremio TV search field. The parent owns the
/// controller/focus node and decides whether to react on [onChanged] (live
/// filtering) or [onSubmitted] (network search).
///
/// The clear (✕) affordance is driven by the controller's actual text — not by
/// any committed query value — so it stays in sync while typing even when the
/// parent only commits the query on submit.
class BrowseSearchHeader extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onClear;

  /// DPAD-down exit from the field (drops into the results/filters).
  final VoidCallback? onDownArrow;

  /// The ink every alpha in this header is struck from: hint text (0.3), the
  /// search glyph (0.35), the clear glyph (0.5), and — unless overridden below
  /// — the focus ring (0.15) and the field fill (0.07).
  ///
  /// Set ONLY by a caller that has landed on the app palette. The default is
  /// the [Colors.white] every literal here used before this widget took
  /// parameters, so a caller that passes nothing renders byte-identically:
  /// that is what lets YouTube and IPTV — both of which reach this header
  /// through `BrowseScreen` — convert on their own schedules, and what keeps
  /// the permanently-legacy player unmoved. The relative alphas are the
  /// widget's own visual hierarchy, not the caller's, so one token carries the
  /// whole set and a light palette gets the same hierarchy in black.
  final Color ink;

  /// Field fill. Null derives [ink] at the shipped 0.07, which is the right
  /// answer for a monochrome palette; pass a colour only when the theme's
  /// field surface is not a tint of its own ink.
  final Color? fillColor;

  /// Focus ring. Null derives [ink] at the shipped 0.15 — pass the theme's
  /// accent to make focus read as focus rather than as a slightly brighter
  /// edge.
  final Color? focusedBorderColor;

  // ───────────────────────────────────── the in-app TV keyboard this raises
  //
  // Pure pass-throughs to [TvTextField]: this header owns none of the
  // keyboard's look, it only forwards the caller's tokens so the panel it
  // raises is themed by the same surface that themes the field. Null on every
  // one — [TvTextField] and [TvKeyboardPanel] then land on the literals that
  // shipped, which is what keeps a caller that passes nothing (and the
  // permanently-legacy player) byte-identical.

  /// The keyboard's filled accent: highlighted keycap, latched shift, mic
  /// disc.
  ///
  /// Distinct from [focusedBorderColor] even though `TvTextField.accent` can
  /// also paint a shell ring: this header always supplies a `focusedBorder`,
  /// so the ring comes from that and this value reaches the keyboard only.
  final Color? accent;

  /// The keyboard panel's ground.
  final Color? keyboardGround;

  /// The keyboard panel's foreground; its alphas ride on top.
  final Color? keyboardInk;

  /// Keycap label ON the filled [accent]. Must be contrast-scored against that
  /// accent, not taken from page ink — light accents make a white label
  /// invisible.
  final Color? keyboardInkOnAccent;

  const BrowseSearchHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onClear,
    this.onChanged,
    this.onSubmitted,
    this.onDownArrow,
    this.ink = Colors.white,
    this.fillColor,
    this.focusedBorderColor,
    this.accent,
    this.keyboardGround,
    this.keyboardInk,
    this.keyboardInkOnAccent,
  });

  @override
  State<BrowseSearchHeader> createState() => _BrowseSearchHeaderState();
}

class _BrowseSearchHeaderState extends State<BrowseSearchHeader> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(BrowseSearchHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    // Rebuild so the clear button appears/disappears with the field contents.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    final ink = widget.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: TvTextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onDownArrow: widget.onDownArrow,
        textInputAction: TextInputAction.search,
        accent: widget.accent,
        keyboardGround: widget.keyboardGround,
        keyboardInk: widget.keyboardInk,
        keyboardInkOnAccent: widget.keyboardInkOnAccent,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(color: ink.withValues(alpha: 0.3)),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: ink.withValues(alpha: 0.35),
          ),
          suffixIcon: hasText
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: ink.withValues(alpha: 0.5),
                  ),
                  onPressed: widget.onClear,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: widget.focusedBorderColor ?? ink.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          filled: true,
          fillColor: widget.fillColor ?? ink.withValues(alpha: 0.07),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
