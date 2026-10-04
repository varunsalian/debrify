import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/services/imdb_parents_guide_service.dart'
    show ParentsGuideResult, ParentsGuideCategory, ParentsGuideItem;
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/material.dart';

// ── parents guide ──────────────────────────────────────────────────────────

List<ParentsGuideItem> _plainOf(ParentsGuideCategory c) => [
  for (final i in c.items)
    if (!i.isSpoiler) i,
];

List<ParentsGuideItem> _spoilersOf(ParentsGuideCategory c) => [
  for (final i in c.items)
    if (i.isSpoiler) i,
];

/// Severity level for the four-segment meter. Unknown wordings render the
/// word with an empty meter rather than guessing a level.
int _severityLevel(String severity) => switch (severity.toLowerCase()) {
  'none' => 1,
  'mild' => 2,
  'moderate' => 3,
  'severe' => 4,
  _ => 0,
};

/// Small-caps severity word plus the segment meter — monochrome, per the
/// approved mock: no traffic-light chips against the artwork.
class _SeverityMark extends StatelessWidget {
  final String severity;

  const _SeverityMark({required this.severity});

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final compact = m.compact;
    final level = _severityLevel(severity);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          severity.toUpperCase(),
          style: st(
            compact ? 9.5 : 7.5 * m.k,
            w: FontWeight.w700,
            a: 0.6,
          ).copyWith(letterSpacing: 1.0),
        ),
        SizedBox(width: compact ? 8 : 6 * m.k),
        for (var i = 1; i <= 4; i++) ...[
          Container(
            width: compact ? 10 : 8 * m.k,
            height: compact ? 3.5 : 3 * m.k,
            decoration: BoxDecoration(
              color: sInk.withValues(alpha: i <= level ? 0.88 : 0.16),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i < 4) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

/// The Parents Guide band — one focus node per category, exactly.
///
/// Wide: a rail of category cards with a plate below that FOLLOWS the
/// selected card (focus on DPAD, tap on pointer) — the season rail's
/// follow-focus pattern. SELECT on the selected card toggles that category's
/// spoiler entries, so expansion never changes the node count.
///
/// Compact: the same categories as full-width accordion rows in the
/// integrated-card style, tap to expand.
///
/// Spoiler entries are WITHHELD, not blurred: a live blur is a per-frame
/// raster cost the Android TV GLES2 path cannot afford, and unrendered text
/// is also the only spoiler treatment that can't be defeated by a screenshot
/// mid-fade. Selection and spoiler state live HERE, not in the layout — the
/// layout owns only the nodes, which is all the DPAD ladder needs.
class ShowcaseGuide extends StatefulWidget {
  final ParentsGuideResult guide;
  final List<FocusNode> nodes;
  final Color accent;

  const ShowcaseGuide({
    super.key,
    required this.guide,
    required this.nodes,
    required this.accent,
  });

  @override
  State<ShowcaseGuide> createState() => _ShowcaseGuideState();
}

class _ShowcaseGuideState extends State<ShowcaseGuide> {
  int _sel = 0;

  /// Wide: spoilers revealed for the SELECTED category; reset on move.
  bool _spoilers = false;

  /// Compact: the one expanded row (-1 none) and its per-category reveals.
  int _open = -1;
  final Set<int> _openSpoilers = {};

  List<ParentsGuideCategory> get _cats => widget.guide.categories;

  @override
  void didUpdateWidget(ShowcaseGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Selection, expansion and spoiler reveals are all INDEX-keyed. A new
    // guide result (the screen re-fetching for a different title, or a
    // reload) renumbers the categories, and carried-over state would reveal
    // the wrong category's spoilers.
    if (!identical(oldWidget.guide, widget.guide)) {
      // Follow LIVE focus, not a blind 0: if a card holds focus through the
      // swap, plate and SELECT must keep describing THAT card.
      final focused = widget.nodes.indexWhere((n) => n.hasFocus);
      _sel = focused >= 0 ? focused.clamp(0, _cats.length - 1) : 0;
      _spoilers = false;
      _open = -1;
      _openSpoilers.clear();
    }
  }

  void _select(int i) {
    if (_sel == i) return;
    setState(() {
      _sel = i;
      _spoilers = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    if (_cats.isEmpty) return const SizedBox.shrink();
    return m.compact ? _compact(context, m) : _wide(context, m);
  }

  // ── wide: card rail + follow-focus plate ─────────────────────────────────

  Widget _wide(BuildContext context, ShowcaseMetrics m) {
    final sel = _sel.clamp(0, _cats.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SBand(
          title: 'Parents Guide',
          height: m.guideH * 1.12 + 18,
          child: ListView.separated(
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: m.gutter),
            itemCount: _cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _GuideCard(
              category: _cats[i],
              node: widget.nodes[i],
              selected: i == sel,
              onSelect: () => _select(i),
              // SELECT on the focused card: reveal/hide that category's
              // spoilers. Null when there are none, so OK stays inert.
              onOk: _spoilersOf(_cats[i]).isNotEmpty
                  ? () => setState(() => _spoilers = !_spoilers)
                  : null,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(m.gutter, 4, m.gutter, 0),
          child: _plate(context, _cats[sel]),
        ),
      ],
    );
  }

  Widget _plate(BuildContext context, ParentsGuideCategory cat) {
    final k = ShowcaseMetrics.of(context).k;
    final spoilers = _spoilersOf(cat);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
      decoration: BoxDecoration(
        color: sInk.withValues(alpha: 0.055),
        border: Border.all(color: sInk.withValues(alpha: 0.07)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(cat.label, style: st(11.5 * k, w: FontWeight.w700)),
              const SizedBox(width: 10),
              _SeverityMark(severity: cat.severity),
              const Spacer(),
              if (cat.totalVotes > 0)
                Text(
                  '${cat.severityVotes} of ${cat.totalVotes} rated '
                  '${cat.severity.toLowerCase()}',
                  style: st(8.5 * k, a: 0.4),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in _plainOf(cat)) _entry(item.text, 10.0 * k),
          if (_spoilers)
            for (final item in spoilers) _entry(item.text, 10.0 * k),
          if (spoilers.isNotEmpty)
            _spoilerRow(spoilers.length, _spoilers, () {
              setState(() => _spoilers = !_spoilers);
            }),
        ],
      ),
    );
  }

  Widget _entry(String text, double size) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: size * 0.55),
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: sInk.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: st(size, a: 0.78).copyWith(height: 1.5)),
        ),
      ],
    ),
  );

  Widget _spoilerRow(int count, bool shown, VoidCallback onToggle) {
    final m = ShowcaseMetrics.of(context);
    final compact = m.compact;
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '$count spoiler ${count == 1 ? 'entry' : 'entries'} '
              '${shown ? 'shown' : 'hidden'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: st(compact ? 11 : 8.5 * m.k, a: 0.5),
            ),
          ),
          const SizedBox(width: 10),
          // A pill, not a node: on DPAD the toggle is SELECT on the focused
          // card; on touch this is the tap target. The accent's one
          // appearance in the band, per the mock.
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 11 : 9 * m.k,
                vertical: compact ? 4 : 2.5 * m.k,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: sInk.withValues(alpha: 0.24)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                shown ? 'HIDE' : 'SHOW',
                style: TextStyle(
                  fontSize: compact ? 10 : 7.5 * m.k,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: widget.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── compact: accordion rows ──────────────────────────────────────────────

  Widget _compact(BuildContext context, ShowcaseMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.only(left: m.gutter, bottom: 10),
          child: Text(
            'Parents Guide',
            style: st(19, w: FontWeight.w600, a: 0.84),
          ),
        ),
        for (var i = 0; i < _cats.length; i++)
          Padding(
            padding: EdgeInsets.fromLTRB(m.gutter, 0, m.gutter, 8),
            child: _accordionRow(context, i),
          ),
      ],
    );
  }

  Widget _accordionRow(BuildContext context, int i) {
    final cat = _cats[i];
    final open = _open == i;
    final spoilers = _spoilersOf(cat);
    final spoilersShown = _openSpoilers.contains(i);
    return Focus(
      focusNode: widget.nodes[i],
      onKeyEvent: (_, e) =>
          sActivate(e, () => setState(() => _open = open ? -1 : i)),
      child: GestureDetector(
        onTap: () => setState(() => _open = open ? -1 : i),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: sInk.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(cat.label, style: st(14, w: FontWeight.w600)),
                  ),
                  _SeverityMark(severity: cat.severity),
                  const SizedBox(width: 10),
                  Text(open ? '▲' : '▼', style: st(10, a: 0.4)),
                ],
              ),
              if (open) ...[
                if (cat.totalVotes > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(
                      '${cat.severityVotes} of ${cat.totalVotes} rated '
                      '${cat.severity.toLowerCase()}',
                      style: st(10.5, a: 0.38),
                    ),
                  ),
                const SizedBox(height: 2),
                for (final item in _plainOf(cat)) _entry(item.text, 12.5),
                if (spoilersShown)
                  for (final item in spoilers) _entry(item.text, 12.5),
                if (spoilers.isNotEmpty)
                  _spoilerRow(spoilers.length, spoilersShown, () {
                    setState(() {
                      if (!_openSpoilers.add(i)) _openSpoilers.remove(i);
                    });
                  }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One wide-tier category card: title, severity mark, entry count.
class _GuideCard extends StatefulWidget {
  final ParentsGuideCategory category;
  final FocusNode node;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onOk;

  const _GuideCard({
    required this.category,
    required this.node,
    required this.selected,
    required this.onSelect,
    required this.onOk,
  });

  @override
  State<_GuideCard> createState() => _GuideCardState();
}

class _GuideCardState extends State<_GuideCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final cat = widget.category;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) {
          widget.onSelect();
          sKeepVisible(context);
        }
      },
      onKeyEvent: (_, e) => sActivate(e, widget.onOk),
      child: SHover(
        builder: (context, hovered) => GestureDetector(
          onTap: widget.onSelect,
          child: Align(
            child: ParallaxFocus(
              focused: _f || hovered,
              radius: BorderRadius.circular(7 * m.k),
              child: Container(
                width: m.guideW,
                height: m.guideH,
                padding: EdgeInsets.fromLTRB(
                  11 * m.k,
                  10 * m.k,
                  11 * m.k,
                  9 * m.k,
                ),
                decoration: BoxDecoration(
                  color: sInk.withValues(alpha: widget.selected ? 0.12 : 0.07),
                  border: Border.all(
                    color: sInk.withValues(
                      alpha: widget.selected ? 0.22 : 0.09,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(7 * m.k),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        cat.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: st(10.5 * m.k, w: FontWeight.w600),
                      ),
                    ),
                    Row(
                      children: [
                        _SeverityMark(severity: cat.severity),
                        const Spacer(),
                        Text(
                          '${cat.items.length}',
                          style: st(8.5 * m.k, w: FontWeight.w600, a: 0.38),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
