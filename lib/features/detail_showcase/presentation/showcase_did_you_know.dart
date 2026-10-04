import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/services/imdb_enrichment_service.dart'
    show DidYouKnowEntry;
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/material.dart';

// ── did you know ───────────────────────────────────────────────────────────

/// Trivia / goofs / quotes as reading cards — the page's footnote band.
/// Cards are focusable so the ladder can park on them (and the rail can
/// scroll), but SELECT is deliberately inert in v1: this is ambient reading,
/// like the synopsis.
class ShowcaseDidYouKnow extends StatelessWidget {
  final List<DidYouKnowEntry> entries;

  /// The full IMDb count; when it exceeds what's mounted, a terminal "+N"
  /// card says so (and carries the last focus node).
  final int total;
  final String? countLine;
  final List<FocusNode> nodes;

  const ShowcaseDidYouKnow({
    super.key,
    required this.entries,
    required this.total,
    required this.countLine,
    required this.nodes,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final hasMore = total > entries.length;
    return SBand(
      title: 'Did You Know',
      subtitle: countLine,
      height: m.dykH * 1.10 + 18,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: entries.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(width: m.compact ? 13 : 12),
        itemBuilder: (context, i) => i < entries.length
            ? _DykCard(entry: entries[i], node: nodes[i])
            : _DykMoreCard(
                count: total - entries.length,
                node: nodes[entries.length],
              ),
      ),
    );
  }
}

class _DykCard extends StatefulWidget {
  final DidYouKnowEntry entry;
  final FocusNode node;

  const _DykCard({required this.entry, required this.node});

  @override
  State<_DykCard> createState() => _DykCardState();
}

class _DykCardState extends State<_DykCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final e = widget.entry;
    final quote = e.kind == 'Quote';
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      // Basic cursor: ambient reading, SELECT is deliberately inert.
      child: SHover(
        cursor: MouseCursor.defer,
        builder: (context, hovered) => Align(
          child: ParallaxFocus(
            focused: _f || hovered,
            radius: BorderRadius.circular(7 * m.k),
            child: Container(
              width: m.dykW,
              height: m.dykH,
              padding: EdgeInsets.fromLTRB(
                m.compact ? 15 : 13 * m.k,
                m.compact ? 13 : 11 * m.k,
                m.compact ? 15 : 13 * m.k,
                m.compact ? 13 : 11 * m.k,
              ),
              decoration: BoxDecoration(
                color: sInk.withValues(alpha: _f || hovered ? 0.11 : 0.07),
                border: Border.all(color: sInk.withValues(alpha: 0.09)),
                borderRadius: BorderRadius.circular(7 * m.k),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.kind.toUpperCase(),
                    style: st(
                      m.compact ? 10 : 7.5 * m.k,
                      w: FontWeight.w700,
                      a: 0.42,
                    ).copyWith(letterSpacing: 1.2),
                  ),
                  SizedBox(height: m.compact ? 8 : 6),
                  Expanded(
                    child: Text(
                      quote ? '“${e.text}”' : e.text,
                      maxLines: m.compact ? 6 : 7,
                      overflow: TextOverflow.ellipsis,
                      style:
                          st(
                            m.compact ? 12.5 : 9.5 * m.k,
                            a: quote ? 0.88 : 0.8,
                          ).copyWith(
                            height: 1.5,
                            fontStyle: quote
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DykMoreCard extends StatefulWidget {
  final int count;
  final FocusNode node;

  const _DykMoreCard({required this.count, required this.node});

  @override
  State<_DykMoreCard> createState() => _DykMoreCardState();
}

class _DykMoreCardState extends State<_DykMoreCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      // Basic cursor: like its siblings, this card is not activatable.
      child: SHover(
        cursor: MouseCursor.defer,
        builder: (context, hovered) => Align(
          child: ParallaxFocus(
            focused: _f || hovered,
            radius: BorderRadius.circular(7 * m.k),
            child: Container(
              width: m.compact ? 110.0 : 92.0 * m.k,
              height: m.dykH,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sInk.withValues(alpha: _f || hovered ? 0.11 : 0.05),
                border: Border.all(color: sInk.withValues(alpha: 0.09)),
                borderRadius: BorderRadius.circular(7 * m.k),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+${widget.count}',
                    style: st(m.compact ? 20 : 16 * m.k, w: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'ON IMDb',
                    style: st(
                      m.compact ? 9 : 7 * m.k,
                      w: FontWeight.w700,
                      a: 0.4,
                    ).copyWith(letterSpacing: 1.1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
