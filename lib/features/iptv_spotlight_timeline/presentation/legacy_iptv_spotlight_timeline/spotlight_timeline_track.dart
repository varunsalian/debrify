import 'dart:math' as math;

import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_dependencies.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_sections.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/spotlight_timeline_palette.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/spotlight_timeline_parts.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

/// Pixel geometry for the intersection of a programme and the visible window.
@immutable
class SpotlightProgrammeGeometry {
  final double left;
  final double width;

  const SpotlightProgrammeGeometry({required this.left, required this.width});
}

/// Maps absolute epoch times into a shared timeline viewport.
///
/// Returns null when the programme does not intersect the window. Using epoch
/// milliseconds keeps widths correct across timezone and daylight-saving
/// transitions.
@visibleForTesting
SpotlightProgrammeGeometry? spotlightProgrammeGeometry({
  required DateTime programmeStart,
  required DateTime programmeStop,
  required DateTime windowStart,
  required Duration windowDuration,
  required double viewportWidth,
}) {
  final windowStartMs = windowStart.millisecondsSinceEpoch;
  final windowDurationMs = windowDuration.inMilliseconds;
  if (windowDurationMs <= 0 || viewportWidth <= 0) return null;

  final windowEndMs = windowStartMs + windowDurationMs;
  final startMs = programmeStart.millisecondsSinceEpoch;
  final stopMs = programmeStop.millisecondsSinceEpoch;
  if (stopMs <= startMs || stopMs <= windowStartMs || startMs >= windowEndMs) {
    return null;
  }

  final clippedStart = math.max(startMs, windowStartMs);
  final clippedStop = math.min(stopMs, windowEndMs);
  return SpotlightProgrammeGeometry(
    left: (clippedStart - windowStartMs) / windowDurationMs * viewportWidth,
    width: (clippedStop - clippedStart) / windowDurationMs * viewportWidth,
  );
}

/// Returns half-hour ruler instants aligned to local :00/:30 wall-clock marks.
///
/// Epoch-aligned half hours are incorrect in quarter-hour time zones: for
/// example, Nepal would render :15/:45 labels. [utcOffset] is exposed only so
/// the wall-clock calculation can be tested independently of the host zone.
@visibleForTesting
List<DateTime> spotlightRulerMarks({
  required DateTime windowStart,
  required Duration windowDuration,
  Duration? utcOffset,
}) {
  const stepMs = 30 * Duration.millisecondsPerMinute;
  final offset = utcOffset ?? windowStart.toLocal().timeZoneOffset;
  final offsetMs = offset.inMilliseconds;
  final startMs = windowStart.millisecondsSinceEpoch;
  final endMs = startMs + windowDuration.inMilliseconds;
  final localStartMs = startMs + offsetMs;
  final remainder = localStartMs % stepMs;
  var localMarkMs = remainder == 0
      ? localStartMs
      : localStartMs + stepMs - remainder;
  final result = <DateTime>[];
  while (localMarkMs - offsetMs <= endMs) {
    result.add(
      DateTime.fromMillisecondsSinceEpoch(
        localMarkMs - offsetMs,
        isUtc: windowStart.isUtc,
      ),
    );
    localMarkMs += stepMs;
  }
  return result;
}

class SpotlightTimelineTrack {
  final SpotlightTimelineDependencies _deps;
  SpotlightTimelineTrack(this._deps);
  SpotlightTimelineWidgetView get widget => _deps.view;
  SpotlightTimelineOwners get _owners => _deps.owners;
  SpotlightTimelineSections get _sections => _deps.sections();

  List<DateTime> rulerMarks() => spotlightRulerMarks(
    windowStart: _owners.windowStart,
    windowDuration: widget.windowDuration,
  );

  double timeX(DateTime time, double width) =>
      (time.millisecondsSinceEpoch -
          _owners.windowStart.millisecondsSinceEpoch) /
      widget.windowDuration.inMilliseconds *
      width;

  Widget buildProgrammeTrack(
    IptvStyleTokens tokens,
    SpotlightTimelineEntry entry,
    int row,
    double width,
  ) {
    if (!entry.channel.isLive) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: SpotlightTimelinePalette.timelineBackground,
          border: Border(
            bottom: BorderSide(color: tokens.hairline),
            left: BorderSide(color: tokens.hairline),
          ),
        ),
        child: SpotlightTimelineGuideMessage(
          label: 'On demand  ·  Press OK to open',
          color: tokens.fgFaint,
          leading: Icon(
            Icons.play_circle_outline_rounded,
            size: 15,
            color: tokens.fgDim,
          ),
          onTap: () => _sections.selection.tapIdentity(row),
        ),
      );
    }
    final snapshot = _owners.guides[entry.entryKey];
    final status = snapshot?.status ?? SpotlightTimelineGuideStatus.loading;
    final retrySelected =
        _owners.hasFocus &&
        !_owners.nowFocusNode.hasFocus &&
        _owners.cursorRow == row &&
        _owners.cursorLane == SpotlightTimelineCursorLane.retry &&
        status == SpotlightTimelineGuideStatus.error;
    final visible =
        <
          ({
            int index,
            EpgProgramme programme,
            SpotlightProgrammeGeometry geometry,
          })
        >[];
    if (status == SpotlightTimelineGuideStatus.ready) {
      for (var index = 0; index < snapshot!.programmes.length; index++) {
        final programme = snapshot.programmes[index];
        final geometry = spotlightProgrammeGeometry(
          programmeStart: programme.start,
          programmeStop: programme.stop,
          windowStart: _owners.windowStart,
          windowDuration: widget.windowDuration,
          viewportWidth: width,
        );
        if (geometry != null) {
          visible.add((index: index, programme: programme, geometry: geometry));
        }
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: SpotlightTimelinePalette.timelineBackground,
        border: Border(
          bottom: BorderSide(color: tokens.hairline),
          left: BorderSide(color: tokens.hairline),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (final mark in rulerMarks())
            Positioned(
              left: timeX(mark, width),
              top: 0,
              bottom: 0,
              child: Container(width: 1, color: tokens.hairline),
            ),
          if (status == SpotlightTimelineGuideStatus.loading)
            SpotlightTimelineGuideMessage(
              key: ValueKey(('spotlight-loading', entry.entryKey)),
              label: 'Loading guide…',
              color: tokens.fgFaint,
              leading: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: tokens.accent,
                ),
              ),
            )
          else if (status == SpotlightTimelineGuideStatus.error)
            SpotlightTimelineGuideMessage(
              key: ValueKey(('spotlight-error', entry.entryKey)),
              label: 'Guide unavailable  ·  Retry',
              color: tokens.rec,
              hint: 'Press OK to retry the guide',
              focused: retrySelected,
              focusFill: tokens.focusFill!,
              focusInk: tokens.focusInk!,
              leading: Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: tokens.rec,
              ),
              onTap: () => _sections.loading.retry(entry),
            )
          else if (snapshot!.programmes.isEmpty)
            SpotlightTimelineGuideMessage(
              key: ValueKey(('spotlight-empty', entry.entryKey)),
              label: 'No programme information',
              color: tokens.fgFaint,
              onTap: () => _sections.selection.tapIdentity(row),
            )
          else if (visible.isEmpty)
            SpotlightTimelineGuideMessage(
              key: ValueKey(('spotlight-window-empty', entry.entryKey)),
              label: 'No information in this time window',
              color: tokens.fgFaint,
              onTap: () => _sections.selection.tapIdentity(row),
            ),
          for (final item in visible)
            Positioned(
              key: ValueKey((
                'spotlight-programme-position',
                entry.entryKey,
                item.programme.start.millisecondsSinceEpoch,
                item.index,
              )),
              left: item.geometry.left,
              width: math.max(1, item.geometry.width),
              top: 5,
              bottom: 5,
              child: _buildProgrammeCell(
                tokens,
                entry,
                row,
                item.programme,
                item.index,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgrammeCell(
    IptvStyleTokens tokens,
    SpotlightTimelineEntry entry,
    int row,
    EpgProgramme programme,
    int programmeIndex,
  ) {
    final startMs = programme.start.millisecondsSinceEpoch;
    final current =
        _owners.cursorRow == row &&
        _owners.cursorLane == SpotlightTimelineCursorLane.programme &&
        _owners.selectedProgrammeStartMs == startMs;
    final selected =
        _owners.hasFocus && !_owners.nowFocusNode.hasFocus && current;
    final now = widget.now();
    final isNow = programme.airsAt(now);
    final isPast = !programme.stop.isAfter(now);
    final foreground = selected
        ? tokens.focusInk!
        : isPast
        ? tokens.fgDim
        : tokens.fg;

    return Semantics(
      button: true,
      focusable: true,
      focused: selected,
      selected: current,
      hint: widget.selectBeforeActivate
          ? 'Tap to preview; tap again to open'
          : null,
      label:
          '${programme.title}, ${formatTime(programme.start)} to '
          '${formatTime(programme.stop)}'
          '${programme.hasArchive && isPast ? ', replay available' : ''}',
      onTap: () => _sections.selection.tapProgramme(row, programme),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _sections.selection.armPointerSelection(
          entry,
          () => _sections.selection.selectProgramme(
            row,
            programme,
            requestFocus: false,
            fromPointer: true,
          ),
        ),
        onExit: (_) => _sections.selection.cancelPointerSelection(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _sections.selection.tapProgramme(row, programme),
          onLongPress: widget.onChannelActions == null
              ? null
              : () {
                  _sections.selection.selectProgramme(
                    row,
                    programme,
                    fromPointer: true,
                  );
                  widget.onChannelActions!(entry);
                },
          child: AnimatedScale(
            scale: selected ? 1.018 : 1,
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              key: ValueKey((
                'spotlight-programme',
                entry.entryKey,
                startMs,
                programmeIndex,
              )),
              duration: const Duration(milliseconds: 130),
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? tokens.focusFill
                    : current || isNow
                    ? tokens.selectedTint
                    : const Color(0xFF10243A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? tokens.focusFill!
                      : current
                      ? tokens.accent
                      : isNow
                      ? tokens.accent.withValues(alpha: 0.56)
                      : tokens.hairline2,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: tokens.accent.withValues(alpha: 0.34),
                          blurRadius: 20,
                          spreadRadius: -5,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          programme.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 12,
                            height: 1.05,
                            fontWeight: selected || isNow
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        if (!widget.dense) ...[
                          const SizedBox(height: 5),
                          Text(
                            '${formatTime(programme.start)} – '
                            '${formatTime(programme.stop)}',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              color: foreground.withValues(alpha: 0.62),
                              fontSize: 9.5,
                              height: 1,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isNow && itemCanFitBadge(programme)) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? tokens.focusInk!.withValues(alpha: 0.1)
                            : tokens.accent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'NOW',
                        style: TextStyle(
                          color: selected ? tokens.focusInk : tokens.accent,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ] else if (programme.hasArchive && isPast) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.replay_rounded,
                      size: 13,
                      color: foreground.withValues(alpha: 0.65),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool itemCanFitBadge(EpgProgramme programme) =>
      programme.stop.difference(programme.start) >= const Duration(minutes: 25);

  static String formatTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
