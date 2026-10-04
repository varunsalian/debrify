import 'dart:math' show max;
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_types.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_shelf_title_link.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/home/row_tag_pill.dart';
import 'package:flutter/material.dart';

class SpotlightBoardShelves {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardShelves(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;

  /// The row heading. Off TV it takes the reference's measure — larger,
  /// brighter, bolder than the TV board's quiet labels (there the hero
  /// carries the weight) — and wears the inline chevron when the row has
  /// somewhere to go; DPAD keeps the heading bare of chrome, because a TV
  /// rail paginates as focus walks it — there is nothing to tap. The
  /// provenance pill is the one piece BOTH inputs wear: which addon fills a
  /// row is a fact on every device.
  TextStyle shelfTitleStyle(SpotlightBoardMetrics m) {
    final fontSize = view.dpad
        ? m.title
        : m.compact
        ? 22.0
        : (m.title < 24.0 ? 24.0 : m.title);
    return TextStyle(
      fontSize: fontSize,
      fontWeight: view.dpad ? FontWeight.w600 : FontWeight.w700,
      letterSpacing: view.dpad ? 0.0 : -0.2,
      // The one label on this board that sits on the PAGE rather than
      // on artwork, so it is the one that has to follow the ink. The
      // hero's text, the dots and the card captions all sit over a
      // photograph and stay white whatever the ground is.
      color: AppThemeScope.of(
        _deps.context(),
      ).core.tx.withValues(alpha: view.dpad ? 0.84 : 0.96),
    );
  }

  double shelfExtent(SpotlightShelf section, SpotlightBoardMetrics m) {
    double textHeight(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(_deps.context()).style.merge(style),
        ),
        textDirection: Directionality.of(_deps.context()),
        textScaler: MediaQuery.textScalerOf(_deps.context()),
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var header = 0.0;
    if (section.showHeader) {
      header = textHeight(section.title, _sections.shelves.shelfTitleStyle(m));
      final tag = section.tag;
      if (tag != null && tag.isNotEmpty) {
        final size = view.dpad ? m.title * .72 : 10.0;
        final tagHeight =
            textHeight(tag.toUpperCase(), RowTagPill.textStyle(size)) +
            size * .56 +
            2; // vertical padding and the two 1px borders
        if (tagHeight > header) header = tagHeight;
      }
    }
    final cardHeight = _sections.shelves.shelfCardHeight(section, m);
    return (section.showHeader ? (view.dpad ? 20 : 34) : (view.dpad ? 8 : 14)) +
        header +
        m.liftUpFor(cardHeight) +
        cardHeight +
        m.liftDownFor(cardHeight) +
        (_sections.shelves.shelfHasCaptions(section, m) ? m.captionBlock : 0);
  }

  Widget shelfTitle(SpotlightShelf section, SpotlightBoardMetrics m) {
    final style = _sections.shelves.shelfTitleStyle(m);
    final fontSize = style.fontSize!;
    final onSeeAll = section.onSeeAll;
    final Widget heading = (view.dpad || onSeeAll == null)
        ? Text(
            section.title,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : SpotlightShelfTitleLink(
            title: section.title,
            style: style,
            fontSize: fontSize,
            onTap: onSeeAll,
          );
    final tag = section.tag;
    if (tag == null || tag.isEmpty) return heading;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Only the HEADING flexes. Two Flexibles would split the row 50/50 as
        // max constraints and wrap a heading the pill never needed the room
        // of ("Featured Movies" broke onto two lines exactly that way). The
        // pill takes its intrinsic width under a hard cap instead, so a
        // long addon name ellipsizes inside the pill rather than squeezing
        // the words that matter.
        Flexible(child: heading),
        const SizedBox(width: 9),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: RowTagPill(tag, fontSize: view.dpad ? m.title * 0.72 : 10),
        ),
      ],
    );
  }

  double shelfCardHeight(SpotlightShelf section, SpotlightBoardMetrics m) {
    // Wide cards use their own rail width. Keeping the portrait card's
    // width makes a 16:9 tile too short to read, while keeping its height
    // makes it enormous and leaves only two titles on a TV row. The rule is
    // by ASPECT, so wide title cards and wide channel tiles share one rail;
    // shelves of portrait/square cards retain their native geometry.
    final uniformlyWide =
        section.items.isNotEmpty &&
        section.items.every((item) => item.shape.aspect > 1);
    return uniformlyWide
        ? m.wideCardW / SpotlightCardShape.wide.aspect
        : m.posterH;
  }

  bool shelfHasCaptions(SpotlightShelf section, SpotlightBoardMetrics m) {
    // Caption-free rows off TV (see [SpotlightShelf.captions]); TV keeps its
    // overlay captions everywhere. Compact must also keep a caption whenever
    // a card carries metadata: otherwise portrait mode discards ratings and
    // Continue Watching's season/episode label while landscape shows both.
    final hasCardMetadata = section.items.any(
      (item) =>
          (item.subtitle ?? '').isNotEmpty ||
          (view.showCardTitlesAndRatings && (item.rating ?? 0) > 0),
    );
    final hasVisibleCaptionContent =
        view.showCardTitlesAndRatings || hasCardMetadata;
    return hasVisibleCaptionContent &&
        (view.dpad || section.captions || (m.compact && hasCardMetadata));
  }

  Widget shelf(int i, SpotlightBoardMetrics m) {
    final section = view.sections[i];
    final nodes = section.nodes;
    final cardHeight = _sections.shelves.shelfCardHeight(section, m);
    final captions = _sections.shelves.shelfHasCaptions(section, m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (section.showHeader)
          Padding(
            // The gap under the title is `liftUp`, supplied by the row below —
            // reserved space that is empty at rest and consumed by the lift.
            // Off TV the rows breathe more — the reference's air is half of
            // what makes its rows read as considered rather than stacked.
            padding: EdgeInsets.fromLTRB(
              m.gutter,
              view.dpad ? 20 : 34,
              m.gutter,
              0,
            ),
            child: _sections.shelves.shelfTitle(section, m),
          )
        else
          SizedBox(height: view.dpad ? 8 : 14),
        Padding(
          // The room the lift needs sits OUTSIDE the viewport, as padding.
          //
          // It used to be added to the viewport's own height instead, and that
          // was the bug behind cards reading far too tall: a horizontal
          // ListView constrains its children to the viewport height TIGHTLY,
          // so every card was stretched to `posterH * 1.10 + 24` while its
          // width was still computed from `posterH`. A 2:3 poster drew at
          // 0.53:1. No amount of re-deriving the ratio could have fixed it.
          padding: EdgeInsets.only(
            top: m.liftUpFor(cardHeight),
            bottom: m.liftDownFor(cardHeight),
          ),
          child: SizedBox(
            // The viewport IS the card now, so the tight cross-axis constraint
            // hands each card exactly the height it asked for. On compact the
            // caption strip below the art is part of the card, and the
            // viewport grows by exactly that strip — the art box itself stays
            // at [cardHeight], so the ratio guard still holds.
            height: cardHeight + (captions ? m.captionBlock : 0),
            child: ListView.separated(
              // Now that the board unbuilds far-off shelves, a rebuilt row
              // would otherwise come back rewound to column 0 — PageStorage
              // carries the offset across the unbuild (DPAD re-lands via
              // focus anyway; this is for touch scroll positions).
              key: PageStorageKey('spotlight-row-${section.id ?? i}'),
              // The lift paints into the padding above and below rather than
              // being sliced off at the viewport edge.
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              // Let the last card reach the reading cursor even on short rows.
              padding: EdgeInsets.only(
                left: m.gutter,
                right:
                    _owners.selection.largeCardInteractions &&
                        section.items.isNotEmpty
                    ? max(
                        m.gutter,
                        (_owners.selection.selectionViewport?.width ?? 0) -
                            m.gutter -
                            cardHeight * section.items.last.shape.aspect,
                      )
                    : m.gutter,
              ),
              itemCount: section.items.length,
              separatorBuilder: (_, __) => SizedBox(width: m.gap),
              itemBuilder: (context, c) => SpotlightBoardCard(
                rowId: section.id ?? i,
                largeInteractions: _owners.selection.largeCardInteractions,
                register: _sections.selection.registerCard,
                unregister: _sections.selection.unregisterCard,
                onInteraction: _sections.selection.interactWithCard,
                card: section.items[c],
                node: c < nodes.length ? nodes[c] : null,
                // Every shape shares the ROW's height and takes the width its
                // aspect implies, so a shelf that mixes posters and channel
                // tiles sits on one baseline instead of stepping up and down.
                height: cardHeight,
                expandedHeight: m.wideCardW / SpotlightCardShape.wide.aspect,
                caption: m.caption,
                radius: m.radius,
                captionBelow: m.compact && captions,
                captionBlock: captions ? m.captionBlock : 0,
                showCaption: captions && section.items[c].showCaption,
                showTitleAndRating: view.showCardTitlesAndRatings,
                expandOnFocus:
                    (view.dpad || _owners.selection.largeCardInteractions) &&
                    view.expandFocusedCard,
                forceParallax:
                    view.forceCardParallax ||
                    _owners.selection.largeCardInteractions,
                trailerEnabled: view.trailersEnabled,
                trailerVolume: view.cardTrailerVolume,
                onTrailerStart: view.onTrailerStop,
                hoverable: !view.dpad,
                dpad: view.dpad,
                onDesktopPreviewActivityChanged:
                    _sections.cadence.onDesktopPreviewActivityChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
