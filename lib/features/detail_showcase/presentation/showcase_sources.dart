import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/services/series_source_service.dart' show SeriesSource;
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/material.dart';

// ── sources ────────────────────────────────────────────────────────────────

/// The Sources band — this page's "How to Watch".
///
/// Painted from BOUND sources, which are a SharedPreferences read, so the band
/// costs no network on open. Bind stops being a mystery button in the identity
/// row and becomes an action on the card it applies to.
class ShowcaseSources extends StatelessWidget {
  final List<SeriesSource> sources;
  final List<FocusNode> nodes;
  final VoidCallback? onOpen;

  /// The full browse/search source list (movies: a tap there PLAYS) or the
  /// season-pack search (series). When non-null the band gets a second entry
  /// card after "Pin source", and the layout supplies one extra node —
  /// topology always matches rendering.
  final VoidCallback? onBrowseAll;

  /// What that second entry card says — the layout words it per type,
  /// because a series' browse lands on the pack search, not "all sources".
  final String browseAllLabel;

  const ShowcaseSources({
    super.key,
    required this.sources,
    required this.nodes,
    required this.onOpen,
    this.onBrowseAll,
    this.browseAllLabel = '⌕  Browse all',
  });

  @override
  Widget build(BuildContext context) => SBand(
    title: 'Sources',
    height: 96 * ShowcaseMetrics.of(context).k,
    child: ListView.separated(
      clipBehavior: Clip.none,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(
        horizontal: ShowcaseMetrics.of(context).gutter,
      ),
      itemCount: 2 + (onBrowseAll != null ? 1 : 0),
      separatorBuilder: (_, __) =>
          SizedBox(width: ShowcaseMetrics.of(context).srcGap),
      itemBuilder: (context, i) {
        if (i == 1) {
          return _SourceCard(node: nodes[i], onTap: onOpen, add: true);
        }
        if (i == 2) {
          return _SourceCard(
            node: nodes[i],
            onTap: onBrowseAll,
            add: true,
            addLabel: browseAllLabel,
          );
        }
        return _SourceCard(
          node: nodes[i],
          onTap: onOpen,
          sourceCount: sources.length,
        );
      },
    ),
  );
}

class _SourceCard extends StatefulWidget {
  final FocusNode node;
  final int sourceCount;
  final bool add;

  /// The add-style card's label. Defaults to the binding manager's wording —
  /// a tap there PINS a source to the title, it doesn't play one, so the tile
  /// says "Pin source"; "Find sources" oversold it as a search.
  final String addLabel;
  final VoidCallback? onTap;

  const _SourceCard({
    required this.node,
    required this.onTap,
    this.sourceCount = 0,
    this.add = false,
    this.addLabel = '＋  Pin source',
  });

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final mm = ShowcaseMetrics.of(context);
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      onKeyEvent: (_, e) => sActivate(e, widget.onTap),
      child: SHover(
        builder: (context, hovered) => GestureDetector(
          onTap: widget.onTap,
          // Same reason as `_Poster`: the Sources band is 96 tall to leave
          // the lift room, and the tight cross-axis constraint would stretch
          // this 66pt card to fill it.
          child: Align(
            child: ParallaxFocus(
              focused: _f || hovered,
              shape: ParallaxShape.sourceCard,
              radius: BorderRadius.circular(7 * mm.k),
              child: Container(
                // Wide keeps the shipped 280/150 (k-scaled off TV); compact
                // grows the bound card to 75% of the width (the mock's
                // source card) and the add chip a touch for fingers.
                width: () {
                  if (!mm.compact) {
                    return (widget.add ? 150.0 : 280.0) * mm.k;
                  }
                  return widget.add ? 160.0 : mm.srcW;
                }(),
                height: 66 * mm.k,
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * mm.k,
                  vertical: 9 * mm.k,
                ),
                decoration: BoxDecoration(
                  color: widget.add ? null : sInk.withValues(alpha: 0.07),
                  border: Border.all(
                    color: sInk.withValues(alpha: widget.add ? 0.22 : 0.09),
                  ),
                  borderRadius: BorderRadius.circular(7 * mm.k),
                ),
                child: widget.add
                    ? Center(
                        child: Text(
                          widget.addLabel,
                          style: st(10.5 * mm.k, a: 0.66),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Pinned sources (${widget.sourceCount})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: st(10.5 * mm.k, w: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.sourceCount == 0
                                      ? 'Pin a source to get started'
                                      : 'View and manage sources',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: st(9.5 * mm.k, a: 0.58),
                                ),
                              ],
                            ),
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
