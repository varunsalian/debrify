import 'dart:math' as math;

import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_dependencies.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_sections.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/spotlight_timeline_palette.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/spotlight_timeline_parts.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

class SpotlightTimelineFrame {
  final SpotlightTimelineDependencies _deps;
  SpotlightTimelineFrame(this._deps);
  SpotlightTimelineWidgetView get widget => _deps.view;
  SpotlightTimelineOwners get _owners => _deps.owners;
  SpotlightTimelineSections get _sections => _deps.sections();

  Widget build(BuildContext context) {
    final tokens = IptvStyleTokens.spotlight;
    return SizedBox(
      height: widget.height,
      child: Material(
        color: SpotlightTimelinePalette.background,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(14),
        child: Focus(
          focusNode: _sections.selection.focusNode,
          autofocus: widget.autofocus,
          onFocusChange: _sections.cursor.onFocusChange,
          onKeyEvent: _sections.cursor.onKeyEvent,
          child: Semantics(
            container: true,
            label: 'Live television programme guide',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final identityWidth = math.min(
                  widget.identityWidth,
                  math.max(0.0, constraints.maxWidth * 0.45),
                );
                final timelineWidth = math.max(
                  0.0,
                  constraints.maxWidth - identityWidth,
                );
                return Listener(
                  onPointerSignal: (signal) => _sections.window
                      .handlePointerSignal(signal, timelineWidth),
                  child: GestureDetector(
                    onHorizontalDragStart: (_) =>
                        _sections.selection.cancelPointerSelection(),
                    onHorizontalDragUpdate: (details) => _sections.window
                        .panTimeline(-details.delta.dx, timelineWidth),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            _buildRuler(tokens, identityWidth, timelineWidth),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, rowConstraints) {
                                  if (_owners.viewportHeight !=
                                      rowConstraints.maxHeight) {
                                    _owners.viewportHeight =
                                        rowConstraints.maxHeight;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (_deps.mounted())
                                            _sections.loading.armViewportLoad();
                                        });
                                  }
                                  if (widget.channels.isEmpty) {
                                    return _buildEmpty(tokens);
                                  }
                                  return ListView.builder(
                                    key: const ValueKey(
                                      'spotlight-live-timeline-rows',
                                    ),
                                    controller: _owners.verticalController,
                                    itemExtent: _sections.loading.rowHeight,
                                    itemCount: widget.channels.length,
                                    physics: const ClampingScrollPhysics(),
                                    itemBuilder: (context, index) =>
                                        _sections.rows.buildRow(
                                          tokens,
                                          _sections.loading.entryAt(index)!,
                                          index,
                                          identityWidth,
                                          timelineWidth,
                                        ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        _buildPlayhead(identityWidth, timelineWidth, tokens),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuler(
    IptvStyleTokens tokens,
    double identityWidth,
    double timelineWidth,
  ) {
    return SizedBox(
      height: widget.rulerHeight,
      child: Row(
        children: [
          Container(
            width: identityWidth,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: SpotlightTimelinePalette.identityBackground,
              border: Border(
                right: BorderSide(color: tokens.hairline),
                bottom: BorderSide(color: tokens.hairline),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: tokens.live,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: tokens.live.withValues(alpha: 0.45),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _dayHeading(_owners.windowStart),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!_owners.followNow)
                  Focus(
                    canRequestFocus: false,
                    onKeyEvent: _sections.window.onNowKeyEvent,
                    child: TextButton(
                      key: const ValueKey('spotlight-jump-to-now'),
                      focusNode: _owners.nowFocusNode,
                      onFocusChange: (focused) {
                        if (focused) {
                          _sections.selection.cancelPointerSelection();
                          _deps.holdOk().reset();
                          _owners.lastTappedCell = null;
                        }
                        _deps.setState(() {});
                      },
                      onPressed: _sections.window.jumpToNow,
                      style:
                          TextButton.styleFrom(
                            minimumSize: const Size(44, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            foregroundColor: tokens.accent,
                          ).copyWith(
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.focused)
                                  ? tokens.focusInk
                                  : tokens.accent,
                            ),
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.focused)
                                  ? tokens.focusFill
                                  : Colors.transparent,
                            ),
                          ),
                      child: const Text('Now'),
                    ),
                  )
                else
                  Text(
                    '${widget.channels.length}',
                    style: TextStyle(color: tokens.fgFaint, fontSize: 11),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: timelineWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: SpotlightTimelinePalette.timelineBackground,
                border: Border(bottom: BorderSide(color: tokens.hairline)),
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final mark in _sections.track.rulerMarks())
                    Positioned(
                      left: _sections.track.timeX(mark, timelineWidth),
                      top: 0,
                      bottom: 0,
                      child: SpotlightTimelineRulerMark(
                        time: mark,
                        color: tokens.fgDim,
                        lineColor: tokens.hairline,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(IptvStyleTokens tokens) {
    return Container(
      color: SpotlightTimelinePalette.timelineBackground,
      alignment: Alignment.center,
      child: Semantics(
        label: 'No live channels',
        child: Text(
          'No live channels',
          style: TextStyle(color: tokens.fgDim, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildPlayhead(
    double identityWidth,
    double timelineWidth,
    IptvStyleTokens tokens,
  ) {
    final now = widget.now();
    final nowMs = now.millisecondsSinceEpoch;
    final startMs = _owners.windowStart.millisecondsSinceEpoch;
    final endMs = startMs + widget.windowDuration.inMilliseconds;
    if (nowMs < startMs || nowMs > endMs || timelineWidth <= 0) {
      return const SizedBox.shrink();
    }
    final x = identityWidth + _sections.track.timeX(now, timelineWidth);
    return Positioned(
      left: x - 1,
      top: 16,
      bottom: 0,
      child: IgnorePointer(
        child: Semantics(
          label: 'Current time ${SpotlightTimelineTrack.formatTime(now)}',
          child: SizedBox(
            width: 3,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned.fill(
                  left: 1,
                  right: 1,
                  child: ColoredBox(color: tokens.accent),
                ),
                Positioned(
                  top: -3,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tokens.accent.withValues(alpha: 0.65),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _dayHeading(DateTime time) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = time.toLocal();
    final now = widget.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return '${sameDay ? 'Today' : _weekday(local.weekday)} · '
        '${months[local.month - 1]} ${local.day}';
  }

  static String _weekday(int weekday) => const <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ][weekday - 1];
}
