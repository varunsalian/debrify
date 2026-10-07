import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_dependencies.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_sections.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/spotlight_timeline_palette.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

class SpotlightTimelineRows {
  final SpotlightTimelineDependencies _deps;
  SpotlightTimelineRows(this._deps);
  SpotlightTimelineWidgetView get widget => _deps.view;
  SpotlightTimelineOwners get _owners => _deps.owners;
  SpotlightTimelineSections get _sections => _deps.sections();

  Widget buildRow(
    IptvStyleTokens tokens,
    SpotlightTimelineEntry entry,
    int row,
    double identityWidth,
    double timelineWidth,
  ) {
    return RepaintBoundary(
      key: ValueKey(('spotlight-row', entry.entryKey)),
      // Signals bubble from the row to ListView. Claim a predominantly
      // horizontal gesture here before its small vertical drift can scroll
      // the channel list; the outer listener also covers the ruler/gaps.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (signal) =>
            _sections.window.handlePointerSignal(signal, timelineWidth),
        child: Row(
          children: [
            SizedBox(
              width: identityWidth,
              child: _buildIdentity(tokens, entry, row),
            ),
            SizedBox(
              width: timelineWidth,
              child: _sections.track.buildProgrammeTrack(
                tokens,
                entry,
                row,
                timelineWidth,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentity(
    IptvStyleTokens tokens,
    SpotlightTimelineEntry entry,
    int row,
  ) {
    final snapshot = _owners.guides[entry.entryKey];
    final programmeIsRefreshing =
        _owners.cursorLane == SpotlightTimelineCursorLane.programme &&
        (snapshot == null ||
            snapshot.status == SpotlightTimelineGuideStatus.loading);
    final current = _owners.cursorRow == row;
    final selected =
        _owners.hasFocus &&
        !_owners.nowFocusNode.hasFocus &&
        current &&
        (_owners.cursorLane == SpotlightTimelineCursorLane.identity ||
            programmeIsRefreshing);
    final channel = entry.channel;
    final guideUnavailable =
        channel.isLive &&
        snapshot?.status == SpotlightTimelineGuideStatus.error;
    return Semantics(
      button: true,
      focusable: true,
      focused: selected,
      selected: current,
      label: [
        if (channel.channelNumber != null) 'Channel ${channel.channelNumber}',
        channel.name,
        if (channel.group != null && channel.group!.isNotEmpty) channel.group!,
        channel.isLive ? 'Live' : 'On demand',
        if (guideUnavailable) 'Guide unavailable',
      ].join(', '),
      hint: guideUnavailable
          ? 'Press OK to play the channel or RIGHT to retry the guide'
          : widget.selectBeforeActivate
          ? 'Tap to preview; tap again to watch'
          : null,
      onTap: () => _sections.selection.tapIdentity(row),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        // Match the existing channel rows: crossing the guide does not churn
        // the preview or steal search focus; resting selects after a dwell.
        onEnter: (_) => _sections.selection.armPointerSelection(
          entry,
          () => _sections.selection.selectIdentity(
            row,
            requestFocus: false,
            fromPointer: true,
          ),
        ),
        onExit: (_) => _sections.selection.cancelPointerSelection(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _sections.selection.tapIdentity(row),
          onLongPress: widget.onChannelActions == null
              ? null
              : () {
                  _sections.selection.selectIdentity(row, fromPointer: true);
                  widget.onChannelActions!(entry);
                },
          child: AnimatedScale(
            scale: selected ? 1.018 : 1,
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              key: ValueKey(('spotlight-identity', entry.entryKey)),
              duration: const Duration(milliseconds: 130),
              margin: EdgeInsets.fromLTRB(
                6,
                widget.dense ? 3 : 5,
                7,
                widget.dense ? 3 : 5,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: selected
                    ? tokens.focusFill
                    : current
                    ? tokens.selectedTint
                    : SpotlightTimelinePalette.identityBackground,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected
                      ? tokens.focusFill!
                      : current
                      ? tokens.accent
                      : tokens.hairline,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: tokens.accent.withValues(alpha: 0.32),
                          blurRadius: 20,
                          spreadRadius: -5,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  SpotlightTimelineChannelMark(
                    logoUrl: channel.logoUrl,
                    size: widget.dense ? 30 : 38,
                    selected: selected,
                    tokens: tokens,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? tokens.focusInk : tokens.fg,
                            fontSize: widget.dense ? 12.5 : 14,
                            height: 1.1,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        if (!widget.dense) ...[
                          const SizedBox(height: 4),
                          Text(
                            _owners.lastTappedCell == (entry.entryKey, null)
                                ? 'Tap again to watch'
                                : channel.channelNumber != null
                                ? 'Channel ${channel.channelNumber}'
                                : channel.isLive
                                ? 'Live television'
                                : 'On demand',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? tokens.focusInk!.withValues(alpha: 0.62)
                                  : tokens.fgFaint,
                              fontSize: 10,
                              height: 1,
                            ),
                          ),
                        ],
                      ],
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

class SpotlightTimelineChannelMark extends StatelessWidget {
  final String? logoUrl;
  final double size;
  final bool selected;
  final IptvStyleTokens tokens;

  const SpotlightTimelineChannelMark({
    required this.logoUrl,
    this.size = 38,
    required this.selected,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.live_tv_rounded,
      size: 19,
      color: selected ? tokens.focusInk : tokens.fgMid,
    );
    final logo = logoUrl?.trim();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: selected
            ? tokens.focusInk!.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(9),
      ),
      child: logo == null || logo.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: logo,
              cacheManager: DebrifyImageCache.iptvLogos,
              fit: BoxFit.contain,
              memCacheHeight: 96,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}
