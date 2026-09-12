import 'package:flutter/material.dart';

import '../styles/iptv_style.dart';

const double kSpotlightHeroDenseBreakpoint = 220;

/// Apple-style selected-channel hero around an existing preview subtree.
///
/// [previewSlot] is inserted once, unchanged, behind layout-only widgets. It
/// is never clipped, faded, decorated, stacked over, or placed below an
/// opaque ancestor created by this widget. Native Android TV underlay and
/// tvOS video-output ownership therefore stay with the caller's established
/// preview implementation.
class SpotlightHeroChrome extends StatelessWidget {
  final Widget previewSlot;
  final Widget identitySlot;
  final Widget titleSlot;
  final Widget? metadataSlot;
  final Widget? descriptionSlot;
  final Widget actionsSlot;
  final int informationFlex;
  final int previewFlex;

  const SpotlightHeroChrome({
    super.key,
    required this.previewSlot,
    required this.identitySlot,
    required this.titleSlot,
    required this.actionsSlot,
    this.metadataSlot,
    this.descriptionSlot,
    this.informationFlex = 10,
    this.previewFlex = 13,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A standard 896x540 TV leaves roughly 170px for this hero once its
        // search, controls, and timeline are present. The editorial stack
        // needs a genuinely tall desktop window.
        final dense = constraints.maxHeight < kSpotlightHeroDenseBreakpoint;
        final minimal = constraints.maxHeight < 140;
        final gap = dense ? 6.0 : 8.0;
        final usableWidth = constraints.maxWidth > gap
            ? constraints.maxWidth - gap
            : 0.0;
        final previewWidthByFlex =
            usableWidth * previewFlex / (informationFlex + previewFlex);
        final previewWidthByHeight = constraints.maxHeight * 16 / 9;
        final previewWidth = previewWidthByFlex < previewWidthByHeight
            ? previewWidthByFlex
            : previewWidthByHeight;
        return Row(
          key: const ValueKey<String>('spotlight-hero'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: informationFlex,
              child: _information(dense: dense, minimal: minimal),
            ),
            SizedBox(width: gap),
            // Do not add paint, clipping, opacity, or semantics merging here.
            // Align loosens the Row's tight height before AspectRatio chooses
            // the largest 16:9 rect that fits. The caller's preview widget is
            // still inserted unchanged and owns its native-video subtree.
            SizedBox(
              width: previewWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: KeyedSubtree(
                    key: const ValueKey<String>('spotlight-hero-preview-slot'),
                    child: previewSlot,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _information({required bool dense, required bool minimal}) {
    final t = IptvStyleTokens.spotlight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(dense ? 14 : 18),
        border: Border.all(color: t.hairline),
      ),
      child: Semantics(
        container: true,
        label: 'Selected channel',
        child: Padding(
          padding: dense
              ? const EdgeInsets.fromLTRB(11, 7, 10, 7)
              : const EdgeInsets.fromLTRB(18, 15, 16, 14),
          child: dense ? _denseInformation(t, minimal) : _fullInformation(t),
        ),
      ),
    );
  }

  Widget _denseInformation(IptvStyleTokens t, bool minimal) {
    final summary = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: const ValueKey<String>('spotlight-hero-identity-slot'),
          child: identitySlot,
        ),
        const SizedBox(height: 2),
        DefaultTextStyle(
          style: TextStyle(
            color: t.fg,
            fontSize: 15,
            height: 1.08,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: KeyedSubtree(
            key: const ValueKey<String>('spotlight-hero-title-slot'),
            child: titleSlot,
          ),
        ),
        if (!minimal && metadataSlot != null) ...[
          const SizedBox(height: 2),
          DefaultTextStyle(
            style: TextStyle(
              color: t.fgMid,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: KeyedSubtree(
              key: const ValueKey<String>('spotlight-hero-metadata-slot'),
              child: metadataSlot!,
            ),
          ),
        ],
        if (!minimal && descriptionSlot != null) ...[
          const SizedBox(height: 2),
          DefaultTextStyle(
            style: TextStyle(color: t.fgDim, fontSize: 9.5, height: 1.1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: KeyedSubtree(
              key: const ValueKey<String>('spotlight-hero-description-slot'),
              child: descriptionSlot!,
            ),
          ),
        ],
      ],
    );

    // At the compact boundary there is room for one line of icon actions
    // beside the summary. The parent puts every remaining action in More.
    if (minimal) {
      return Row(
        children: [
          Expanded(child: summary),
          const SizedBox(width: 8),
          Flexible(
            child: KeyedSubtree(
              key: const ValueKey<String>('spotlight-hero-actions-slot'),
              child: actionsSlot,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: summary),
        const SizedBox(height: 5),
        KeyedSubtree(
          key: const ValueKey<String>('spotlight-hero-actions-slot'),
          child: actionsSlot,
        ),
      ],
    );
  }

  Widget _fullInformation(IptvStyleTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: const ValueKey<String>('spotlight-hero-identity-slot'),
          child: identitySlot,
        ),
        const SizedBox(height: 8),
        DefaultTextStyle(
          style: TextStyle(
            color: t.fg,
            fontSize: 21,
            height: 1.08,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          child: KeyedSubtree(
            key: const ValueKey<String>('spotlight-hero-title-slot'),
            child: titleSlot,
          ),
        ),
        if (metadataSlot != null) ...[
          const SizedBox(height: 6),
          DefaultTextStyle(
            style: TextStyle(
              color: t.fgMid,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: KeyedSubtree(
              key: const ValueKey<String>('spotlight-hero-metadata-slot'),
              child: metadataSlot!,
            ),
          ),
        ],
        if (descriptionSlot != null) ...[
          const SizedBox(height: 7),
          Flexible(
            child: DefaultTextStyle(
              style: TextStyle(color: t.fgDim, fontSize: 11.5, height: 1.28),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              child: KeyedSubtree(
                key: const ValueKey<String>('spotlight-hero-description-slot'),
                child: descriptionSlot!,
              ),
            ),
          ),
        ] else
          const Spacer(),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: const ValueKey<String>('spotlight-hero-actions-slot'),
          child: actionsSlot,
        ),
      ],
    );
  }
}
