import 'package:debrify/features/detail_showcase/presentation/showcase_identity_actions.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_identity_readouts.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:flutter/material.dart';

// ── identity ───────────────────────────────────────────────────────────────

/// Chip, logo (or title), meta line with tracker marks, synopsis, tech line,
/// and a row of at most four buttons.
class ShowcaseIdentity extends StatelessWidget {
  final DetailModel model;
  final FocusNode primaryNode;
  final List<FocusNode> actionNodes;
  final VoidCallback onFocused;

  /// The hero's height: one viewport, less however much of the next band is
  /// deliberately left showing.
  ///
  /// Computed by the layout, which is the only place that knows both the real
  /// viewport and which band comes next. It cannot be derived here: a
  /// `LayoutBuilder` inside a vertical list is handed an unbounded height, and
  /// `MediaQuery` is the screen — including the overscan inset this body sits
  /// inside — so both are the wrong number.
  final double height;

  const ShowcaseIdentity({
    super.key,
    required this.model,
    required this.primaryNode,
    required this.actionNodes,
    required this.onFocused,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final m = model;
    final actions = <Widget>[];
    var i = 0;
    FocusNode next() {
      final n = actionNodes[i.clamp(0, actionNodes.length - 1)];
      i++;
      return n;
    }

    if (m.onToggleMyWatchlist != null && actionNodes.isNotEmpty) {
      actions.add(
        SCircle(
          node: next(),
          icon: m.inMyWatchlist
              ? Icons.bookmark_rounded
              : Icons.bookmark_add_outlined,
          label: m.inMyWatchlist ? 'In Watchlist' : 'Watchlist',
          onTap: m.onToggleMyWatchlist!,
        ),
      );
    }
    if (m.onTrackers != null && actionNodes.isNotEmpty) {
      // The screen assigns Trakt to the primary slot when it is connected;
      // otherwise this callback opens Simkl. Keep the mark coupled to that
      // same rule instead of presenting an ambiguous generic `+`.
      actions.add(
        SCircle.mark(
          node: next(),
          mark: m.hasTrakt
              ? const TraktMark()
              : m.hasSimkl
              ? const SimklMark()
              : const MdblistMark(),
          label: m.hasTrakt ? 'Trakt' : (m.hasSimkl ? 'Simkl' : 'MDBList'),
          onTap: m.onTrackers!,
        ),
      );
    }
    if (m.onTrackersSecondary != null && i < actionNodes.length) {
      // The secondary slot only exists when both are connected. Trakt owns
      // the primary slot above, so this callback always opens Simkl.
      actions.add(
        SCircle.mark(
          node: next(),
          mark: m.hasTrakt && m.hasSimkl
              ? const SimklMark()
              : const MdblistMark(),
          label: m.hasTrakt && m.hasSimkl ? 'Simkl' : 'MDBList',
          onTap: m.onTrackersSecondary!,
        ),
      );
    }
    if (m.onTrackersTertiary != null && i < actionNodes.length) {
      actions.add(
        SCircle.mark(
          node: next(),
          mark: const MdblistMark(),
          label: 'MDBList',
          onTap: m.onTrackersTertiary!,
        ),
      );
    }
    if (m.hasTrailer && i < actionNodes.length) {
      actions.add(
        SCircle(
          node: next(),
          icon: Icons.theaters_rounded,
          label: 'Trailer',
          onTap: m.onTrailer,
        ),
      );
    }
    // The source BROWSE. For a movie: the full searchable list, where a tap
    // plays. For a series: the season-pack search — the same thing the More
    // menu's "Search season packs" row opens, surfaced as its own button.
    // Distinct from the Sources band below, whose cards and "Pin source"
    // tile land on the title-level BINDING manager.
    if (m.onBrowse != null && i < actionNodes.length) {
      actions.add(
        SCircle(
          node: next(),
          icon: Icons.layers_rounded,
          label: m.isMovie ? 'Sources' : 'Season packs',
          onTap: m.onBrowse!,
        ),
      );
    }
    if (m.onMetadataExplore != null && i < actionNodes.length) {
      actions.add(
        SCircle(
          node: next(),
          icon: Icons.explore_outlined,
          label: 'Explore',
          onTap: m.onMetadataExplore!,
        ),
      );
    }
    if (m.onAppMenu != null && i < actionNodes.length) {
      actions.add(
        SCircle(
          node: next(),
          icon: Icons.more_horiz_rounded,
          label: 'More',
          onTap: m.onAppMenu!,
        ),
      );
    }

    // A FIRST SCREENFUL, not a block in the flow.
    //
    // The reference opens on key art with the identity at its foot and the next
    // row peeking in at the bottom edge — the tell that the page continues. As
    // an ordinary 150-padded block the identity floated in the middle of the
    // art with three rows already visible under it.
    //
    // Sized from the viewport the list actually has (`constraints.maxHeight`),
    // not `MediaQuery`: the body is already inside the overscan `SafeArea`, so
    // the screen height overstates it by the top AND bottom insets and the peek
    // would be pushed off the bottom.
    //
    // Compact: the height is a MINIMUM, not a fix — the centered stack's
    // synopsis expands in place (MORE), and growing the band is the only
    // honest response; a fixed box would overflow.
    final metrics = ShowcaseMetrics.of(context);
    if (metrics.compact) {
      return Container(
        constraints: BoxConstraints(minHeight: height),
        alignment: Alignment.bottomCenter,
        child: _identityColumnCompact(context, m, actions, metrics),
      );
    }
    return SizedBox(
      height: height,
      child: _identityColumn(context, m, actions),
    );
  }

  /// The phone identity — the Apple phone idiom: everything centered and
  /// stacked, synopsis clamped to two lines with an inline MORE.
  Widget _identityColumnCompact(
    BuildContext context,
    DetailModel m,
    List<Widget> actions,
    ShowcaseMetrics metrics,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(metrics.gutter, 0, metrics.gutter, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SChip(label: m.isMovie ? 'Film' : 'Series'),
          const SizedBox(height: 9),
          SLogoOrTitle(url: m.logo, name: m.name, centered: true),
          const SizedBox(height: 10),
          SMetaLine(model: m),
          const SizedBox(height: 8),
          if (_hasHonors(m)) ...[
            SHonorsLine(model: m),
            const SizedBox(height: 8),
          ],
          if ((m.synopsis ?? '').isNotEmpty) ...[
            SExpandableSynopsis(text: m.synopsis!),
            const SizedBox(height: 10),
          ],
          STechLine(model: m),
          const SizedBox(height: 12),
          // Wrap, not Row: a Resume pill plus four circles can pass 390
          // logical on a long episode code, and a phone identity that
          // overflows sideways is worse than one that wraps.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (m.showPrimary)
                SPrimary(
                  node: primaryNode,
                  label: m.primaryLabel,
                  busy: m.primaryBusy,
                  onTap: m.onPrimary,
                  onLongPress: m.onPrimaryLongPress,
                  onFocused: onFocused,
                ),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }

  Widget _identityColumn(
    BuildContext context,
    DetailModel m,
    List<Widget> actions,
  ) {
    final metrics = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(metrics.gutter, 0, metrics.gutter, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Anchored to the FOOT of the screenful, as the reference is.
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.max,
        children: [
          SChip(label: m.isMovie ? 'Film' : 'Series'),
          const SizedBox(height: 9),
          SLogoOrTitle(url: m.logo, name: m.name),
          const SizedBox(height: 10),
          SMetaLine(model: m),
          const SizedBox(height: 8),
          if (_hasHonors(m)) ...[
            SHonorsLine(model: m),
            const SizedBox(height: 8),
          ],
          if ((m.synopsis ?? '').isNotEmpty)
            SizedBox(
              width: 410 * metrics.k,
              child: Text(
                m.synopsis!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: st(10.5 * metrics.k, a: 0.74).copyWith(height: 1.42),
              ),
            ),
          const SizedBox(height: 11),
          STechLine(model: m),
          const SizedBox(height: 11),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.showPrimary)
                SPrimary(
                  node: primaryNode,
                  label: m.primaryLabel,
                  busy: m.primaryBusy,
                  onTap: m.onPrimary,
                  onLongPress: m.onPrimaryLongPress,
                  onFocused: onFocused,
                ),
              for (final a in actions) ...[const SizedBox(width: 7), a],
            ],
          ),
        ],
      ),
    );
  }
}

bool _hasHonors(DetailModel m) =>
    m.imdbExtra?.top250Rank != null || m.imdbExtra?.meterRank != null;
