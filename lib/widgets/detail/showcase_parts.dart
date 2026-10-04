import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/services/debrify_image_cache.dart'
    show DebrifyImageCache;
import 'package:debrify/services/imdb_enrichment_service.dart'
    show UniverseTitle, DidYouKnowEntry;
import 'package:debrify/services/imdb_parents_guide_service.dart'
    show ParentsGuideResult, ParentsGuideCategory, ParentsGuideItem;
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/viewport_artwork_scope.dart';
import 'package:flutter/material.dart';

export 'package:debrify/features/detail_showcase/presentation/showcase_cast.dart'
    show ShowcaseCast;
export 'package:debrify/features/detail_showcase/presentation/showcase_episodes.dart'
    show ShowcaseEpisodeCell, ShowcaseEpisodeCardCompact;
export 'package:debrify/features/detail_showcase/presentation/showcase_grounds.dart'
    show ShowcaseAmbient, ShowcaseBackdropScrim, ShowcaseStickyLogo;
export 'package:debrify/features/detail_showcase/presentation/showcase_identity.dart'
    show ShowcaseIdentity;
export 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart'
    show ShowcaseMetrics, ShowcaseMetricsScope, kShowcaseGutter;
export 'package:debrify/features/detail_showcase/presentation/showcase_recs.dart'
    show ShowcaseRecs;
export 'package:debrify/features/detail_showcase/presentation/showcase_seasons.dart'
    show ShowcaseSeasons;
export 'package:debrify/features/detail_showcase/presentation/showcase_sources.dart'
    show ShowcaseSources;

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

// ── universe ───────────────────────────────────────────────────────────────

/// Franchise connections — a poster card with a relation eyebrow, opening the
/// related title exactly as a More Like This card does.
class ShowcaseUniverse extends StatelessWidget {
  final List<UniverseTitle> items;
  final List<FocusNode> nodes;
  final void Function(UniverseTitle)? onOpen;

  const ShowcaseUniverse({
    super.key,
    required this.items,
    required this.nodes,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final capH = m.compact ? 52.0 : 42.0 * m.k;
    return SBand(
      title: 'Universe',
      height: m.posterH * 1.10 + 24 + capH,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: m.posterGap),
        itemBuilder: (context, i) => _UniverseCard(
          item: items[i],
          node: nodes[i],
          onOpen: onOpen,
          width: m.poster,
          height: m.posterH,
        ),
      ),
    );
  }
}

class _UniverseCard extends StatefulWidget {
  final UniverseTitle item;
  final FocusNode node;
  final void Function(UniverseTitle)? onOpen;
  final double width;
  final double height;

  const _UniverseCard({
    required this.item,
    required this.node,
    required this.onOpen,
    required this.width,
    required this.height,
  });

  @override
  State<_UniverseCard> createState() => _UniverseCardState();
}

class _UniverseCardState extends State<_UniverseCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final u = widget.item;
    final slot = sSlotFill(AppThemeScope.of(context));
    final url = ViewportArtworkScope.enabledOf(context) ? u.posterUrl : null;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      onKeyEvent: (_, e) =>
          sActivate(e, widget.onOpen == null ? null : () => widget.onOpen!(u)),
      child: SHover(
        builder: (context, hovered) => GestureDetector(
          onTap: () => widget.onOpen?.call(u),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: widget.width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ParallaxFocus(
                    focused: _f || hovered,
                    radius: BorderRadius.circular(7),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: SizedBox(
                        width: widget.width,
                        height: widget.height,
                        child: (url != null && url.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                cacheManager: DebrifyImageCache.manager,
                                memCacheWidth: 300,
                                placeholder: (_, __) => ColoredBox(color: slot),
                                errorWidget: (_, __, ___) =>
                                    ColoredBox(color: slot),
                              )
                            : ColoredBox(color: slot),
                      ),
                    ),
                  ),
                  SizedBox(height: m.compact ? 8 : 7),
                  Text(
                    u.relation.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st(
                      m.compact ? 9 : 7 * m.k,
                      w: FontWeight.w700,
                      a: 0.42,
                    ).copyWith(letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    u.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st(
                      m.compact ? 12 : 10 * m.k,
                      w: FontWeight.w600,
                      a: 0.9,
                    ),
                  ),
                  if (u.yearLabel.isNotEmpty)
                    Text(
                      u.yearLabel,
                      style: st(m.compact ? 10.5 : 8.5 * m.k, a: 0.45),
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

/// A band that has nothing to show yet, or could not load.
///
/// Without this a failed episode load reads as the band simply not being
/// there — indistinguishable from a movie, and with no way to retry.
class ShowcaseBandNote extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Supplied by the layout so the chip joins the band ladder. A focusable
  /// control the DPAD map does not know about is a control nobody can reach.
  final FocusNode? actionNode;

  const ShowcaseBandNote({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.actionNode,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(m.gutter, 22, m.gutter, 8),
      child: Row(
        children: [
          Text(text, style: st(11.5 * m.k, a: 0.66)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 12),
            _RetryChip(label: actionLabel!, onTap: onAction!, node: actionNode),
          ],
        ],
      ),
    );
  }
}

class _RetryChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final FocusNode? node;

  const _RetryChip({required this.label, required this.onTap, this.node});

  @override
  State<_RetryChip> createState() => _RetryChipState();
}

class _RetryChipState extends State<_RetryChip> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) => setState(() => _f = v),
      onKeyEvent: (_, e) => sActivate(e, widget.onTap),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 22 * k,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 11 * k),
          decoration: BoxDecoration(
            color: _f ? sInk : sInk.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(11 * k),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 10.5 * k,
              fontWeight: FontWeight.w600,
              color: _f ? Colors.black : sInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Details band — Creator/Country/Language/Studio/Box Office, and awards.
///
/// Reference material, not a row of verbs, so it sits at the very bottom and
/// takes no cursor. Two columns because a single column of five short pairs
/// leaves a screen mostly empty at three metres.
class ShowcaseDetails extends StatelessWidget {
  final List<(String, String)> rows;
  final String? awards;

  const ShowcaseDetails({super.key, required this.rows, required this.awards});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && (awards ?? '').isEmpty) return const SizedBox.shrink();
    final m = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(m.gutter, 26, m.gutter, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Details', style: st(13 * m.k, w: FontWeight.w600, a: 0.84)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 46,
            runSpacing: 7,
            children: [
              for (final r in rows)
                SizedBox(
                  width: 240 * m.k,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 74 * m.k,
                        child: Text(r.$1, style: st(10 * m.k, a: 0.5)),
                      ),
                      Expanded(child: Text(r.$2, style: st(10 * m.k, a: 0.82))),
                    ],
                  ),
                ),
            ],
          ),
          if ((awards ?? '').isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(awards!, style: st(10 * m.k, a: 0.6)),
          ],
        ],
      ),
    );
  }
}
