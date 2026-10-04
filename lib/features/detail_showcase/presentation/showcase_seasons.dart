import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:debrify/widgets/season_action_region.dart';
import 'package:flutter/material.dart';

// ── seasons ────────────────────────────────────────────────────────────────

class ShowcaseSeasons extends StatelessWidget {
  final EpisodesPanelView view;
  final List<FocusNode> nodes;

  const ShowcaseSeasons({super.key, required this.view, required this.nodes});

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    // Compact: one pill + an anchored popup — Apple's phone idiom, measured
    // off the reference (no scrim, no sheet, the page stays live behind it).
    // The band carries exactly ONE node then, supplied by the layout.
    if (m.compact) {
      return Padding(
        padding: EdgeInsets.only(left: m.gutter, right: m.gutter, top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _SeasonDropdown(view: view, node: nodes.first),
        ),
      );
    }
    return SizedBox(
      height: 34 * m.k,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: view.seasons.length,
        separatorBuilder: (_, __) => SizedBox(width: 7 * m.k),
        itemBuilder: (context, i) {
          final s = view.seasons[i];
          final active = s.number == view.selectedSeasonNumber;
          return _SeasonPill(
            node: nodes[i],
            label: 'Season ${s.number}',
            active: active,
            onTap: () => view.selectSeason(s.number),
            onOptions: view.seasonOptions == null
                ? null
                : () => view.seasonOptions!(s.number),
          );
        },
      ),
    );
  }
}

/// The compact season control: a tinted pill that opens an anchored popup
/// menu at its own position. `showMenu` supplies the parts a hand-rolled
/// overlay always forgets — outside-tap dismissal, Escape/Back, viewport-edge
/// repositioning, an internal scroll past ~8 seasons — and returns focus to
/// the anchor's route when it closes.
class _SeasonDropdown extends StatefulWidget {
  final EpisodesPanelView view;
  final FocusNode node;

  const _SeasonDropdown({required this.view, required this.node});

  @override
  State<_SeasonDropdown> createState() => _SeasonDropdownState();
}

class _SeasonDropdownState extends State<_SeasonDropdown> {
  bool _f = false;

  Future<void> _open() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + 6,
        overlay.size.width - origin.dx - 220,
        0,
      ),
      color: const Color(0xFF1B1B1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      constraints: const BoxConstraints(minWidth: 200, maxHeight: 380),
      items: [
        for (final s in widget.view.seasons)
          PopupMenuItem<int>(
            value: s.number,
            child: Text(
              'Season ${s.number}',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: s.number == widget.view.selectedSeasonNumber
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: s.number == widget.view.selectedSeasonNumber
                    ? AppThemeScope.of(context).core.accent
                    : Colors.white,
              ),
            ),
          ),
      ],
    );
    if (selected != null) widget.view.selectSeason(selected);
  }

  @override
  Widget build(BuildContext context) {
    return SeasonActionRegion(
      onTap: _open,
      onOptions: widget.view.seasonOptions == null
          ? null
          : () => widget.view.seasonOptions!(widget.view.selectedSeasonNumber),
      child: Focus(
        focusNode: widget.node,
        onFocusChange: (v) => setState(() => _f = v),
        onKeyEvent: (_, e) => widget.view.seasonOptions == null
            ? sActivate(e, _open)
            : KeyEventResult.ignored,
        child: GestureDetector(
          onTap: _open,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: sInk.withValues(alpha: _f ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Season ${widget.view.selectedSeasonNumber}',
                  style: st(14, w: FontWeight.w600),
                ),
                const SizedBox(width: 7),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeasonPill extends StatefulWidget {
  final FocusNode node;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onOptions;

  const _SeasonPill({
    required this.node,
    required this.label,
    required this.active,
    required this.onTap,
    this.onOptions,
  });

  @override
  State<_SeasonPill> createState() => _SeasonPillState();
}

class _SeasonPillState extends State<_SeasonPill> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return SeasonActionRegion(
      onTap: widget.onTap,
      onOptions: widget.onOptions,
      child: Focus(
        focusNode: widget.node,
        onFocusChange: (v) {
          setState(() => _f = v);
          if (v) sKeepVisible(context);
        },
        // Selecting on FOCUS would reload the episode list on every step of a
        // walk across the seasons. OK commits; the walk is free.
        onKeyEvent: (_, e) => widget.onOptions == null
            ? sActivate(e, widget.onTap)
            : KeyEventResult.ignored,
        // The wide row is what every TOUCH tablet gets (compact swaps in the
        // dropdown below 600), so the pill needs a finger path too — OK-only
        // left the season control dead under a finger. Opaque: the pill draws
        // no background until it is focused or active, and a bare DecoratedBox
        // defers the hit test to the Text, so the padding would miss.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ParallaxFocus(
            focused: _f,
            shape: ParallaxShape.pill,
            radius: BorderRadius.circular(12.5 * k),
            child: Container(
              height: 25 * k,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: 15 * k),
              decoration: BoxDecoration(
                color: (_f || widget.active)
                    ? sInk.withValues(alpha: _f ? 0.28 : 0.18)
                    : null,
                borderRadius: BorderRadius.circular(12.5 * k),
              ),
              child: Text(
                widget.label,
                style: st(
                  12.5 * k,
                  w: FontWeight.w600,
                  a: widget.active || _f ? 1 : 0.55,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
