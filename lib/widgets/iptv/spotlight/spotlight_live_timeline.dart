import 'dart:async';
import 'dart:math' as math;

import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_dependencies.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_sections.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';

export 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart'
    show
        SpotlightScheduleLoader,
        SpotlightChannelActivate,
        SpotlightProgrammeActivate,
        SpotlightTimelineEntryKey,
        SpotlightTimelineEntry,
        SpotlightTimelineSelection;
export 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart'
    show
        SpotlightProgrammeGeometry,
        spotlightProgrammeGeometry,
        spotlightRulerMarks;

/// Imperative focus handoff used by the surrounding Browse/search shell.
///
/// The controller does not own a [FocusNode]; the timeline keeps sole node
/// ownership so replacing or disposing the section cannot leak focus state.
class IptvSpotlightTimelineController {
  _SpotlightLiveTimelineState? _state;

  bool get hasFocus => _state?._hasFocus ?? false;

  /// Restores the exact logical cell without resetting its programme or time.
  bool restoreFocus() => _state?._restoreFocus() ?? false;

  bool focusFirstChannel() => _state?._focusFirstChannel() ?? false;

  /// Focus [index] directly without searching [SpotlightLiveTimeline.channels].
  /// This is safe for a large lazy database list: only the requested item is
  /// read, and the timeline scrolls it into view after taking focus.
  bool focusChannelAt(int index) => _state?._focusChannelAt(index) ?? false;

  /// Object identity is used because duplicate provider URLs are valid. The
  /// timeline deliberately limits restoration to its visible window so this
  /// handoff never scans/materializes a large lazy database list.
  bool focusChannel(IptvChannel channel) =>
      _state?._focusChannel(channel) ?? false;

  void _attach(_SpotlightLiveTimelineState state) {
    assert(
      _state == null || identical(_state, state),
      'An IptvSpotlightTimelineController can control one timeline at a time.',
    );
    _state = state;
  }

  void _detach(_SpotlightLiveTimelineState state) {
    if (identical(_state, state)) _state = null;
  }
}

/// A standalone Apple/tvOS-style EPG lane for live IPTV rows.
///
/// The identity column never pans horizontally. The ruler, programme cells,
/// and playhead all use one epoch window. A single [FocusNode] owns DPAD input;
/// programme cells are logical cursor targets rather than individual focus
/// nodes, which keeps large guides cheap to traverse.
class SpotlightLiveTimeline extends StatefulWidget {
  /// The current live-result list. It may be a lazy database-backed [List];
  /// this widget reads only indices ListView makes visible and never copies or
  /// scans it during build.
  ///
  /// The surrounding IPTV view already separates Live from VOD/Series. Keep
  /// that contract here so a 50k-row lazy list does not need a second filter.
  final List<IptvChannel> channels;
  final String sourceId;
  final int loadGeneration;
  final SpotlightScheduleLoader scheduleLoader;
  final SpotlightChannelActivate onChannelActivate;
  final SpotlightProgrammeActivate onProgrammeActivate;

  /// Increment this when the active XMLTV/Xtream guide context changes.
  /// Visible rows are retried even when their entry keys did not change.
  final int epgContextVersion;

  /// Receives every keyboard, hover, and pointer cursor move.
  final ValueChanged<SpotlightTimelineSelection>? onSelectionChanged;

  final IptvSpotlightTimelineController? controller;
  final bool autofocus;
  final VoidCallback? onExitUp;
  final VoidCallback? onExitLeft;
  final SpotlightChannelActivate? onChannelActions;

  /// A first pointer tap selects for preview; a second tap opens the selection.
  final bool selectBeforeActivate;

  /// Injectable wall clock for deterministic cursor-following tests.
  @visibleForTesting
  final DateTime Function() now;

  final DateTime? initialWindowStart;
  final Duration windowDuration;
  final Duration viewportSettleDelay;
  final double height;
  final bool dense;
  final double identityWidth;
  final double rowHeight;
  final double rulerHeight;

  const SpotlightLiveTimeline({
    super.key,
    required this.channels,
    required this.sourceId,
    required this.loadGeneration,
    required this.scheduleLoader,
    required this.onChannelActivate,
    required this.onProgrammeActivate,
    required this.epgContextVersion,
    this.onSelectionChanged,
    this.controller,
    this.autofocus = false,
    this.onExitUp,
    this.onExitLeft,
    this.onChannelActions,
    this.selectBeforeActivate = true,
    this.now = DateTime.now,
    this.initialWindowStart,
    this.windowDuration = const Duration(hours: 4),
    this.viewportSettleDelay = const Duration(milliseconds: 375),
    this.height = 360,
    this.dense = false,
    this.identityWidth = 300,
    this.rowHeight = 68,
    this.rulerHeight = 42,
  }) : assert(height > 0),
       assert(identityWidth > 0),
       assert(rowHeight > 0),
       assert(rulerHeight > 0),
       assert(windowDuration > Duration.zero),
       assert(viewportSettleDelay >= Duration.zero);

  @override
  State<SpotlightLiveTimeline> createState() => _SpotlightLiveTimelineState();
}

class _SpotlightLiveTimelineState extends State<SpotlightLiveTimeline>
    implements SpotlightTimelineWidgetView {
  final _owners = SpotlightTimelineOwners();
  SpotlightTimelineSections? _sectionsCache;
  SpotlightTimelineSections get _sections =>
      _sectionsCache ??= SpotlightTimelineSections(
        SpotlightTimelineDependencies(
          view: this,
          owners: _owners,
          context: () => context,
          mounted: () => mounted,
          setState: setState,
          holdOk: () => _holdOk,
          sections: () => _sections,
        ),
      );

  late final TvHoldOk _holdOk = TvHoldOk(
    onTap: _sections.cursor.activateCursor,
    onHold: () {
      final entry = _sections.loading.entryAt(_owners.cursorRow);
      if (entry != null) widget.onChannelActions?.call(entry);
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sections.loading.armViewportLoad();
    _sections.cursor.revealRow(_owners.cursorRow);
  }

  @override
  void initState() {
    super.initState();
    final now = widget.now();
    _owners.windowStart =
        widget.initialWindowStart ?? _sections.window.defaultWindowStart(now);
    _owners.followNow = widget.initialWindowStart == null;
    _owners.cursorTimeMs = now.millisecondsSinceEpoch;
    _owners.lastGuideRefreshAt = now;
    widget.controller?._attach(this);
    _owners.verticalController.addListener(_sections.loading.onViewportMoved);
    _owners.clockTick = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sections.window.onClockTick(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sections.loading.armViewportLoad();
      if (widget.autofocus) _sections.selection.focusNode.requestFocus();
      _sections.selection.announceSelection();
    });
  }

  @override
  void didUpdateWidget(SpotlightLiveTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }

    final sourceChanged =
        oldWidget.sourceId != widget.sourceId ||
        oldWidget.loadGeneration != widget.loadGeneration ||
        !identical(oldWidget.channels, widget.channels);
    final contextChanged =
        oldWidget.epgContextVersion != widget.epgContextVersion;
    if (sourceChanged || contextChanged) {
      _sections.selection.cancelPointerSelection();
      _owners.lastTappedCell = null;
      _holdOk.reset();
      _owners.guides.clear();
      _owners.pendingLoads.clear();
      _owners.lastGuideRefreshAt = widget.now();
    }

    _owners.cursorRow = _owners.cursorRow.clamp(
      0,
      math.max(0, widget.channels.length - 1),
    );
    if (widget.channels.isEmpty ||
        sourceChanged ||
        (contextChanged &&
            _owners.cursorLane == SpotlightTimelineCursorLane.retry)) {
      _owners.cursorLane = SpotlightTimelineCursorLane.identity;
      _owners.selectedProgrammeStartMs = null;
    }
    if (oldWidget.initialWindowStart != widget.initialWindowStart &&
        widget.initialWindowStart != null) {
      _owners.windowStart = widget.initialWindowStart!;
      _owners.followNow = false;
    } else if (oldWidget.initialWindowStart != widget.initialWindowStart &&
        widget.initialWindowStart == null) {
      _owners.windowStart = _sections.window.defaultWindowStart();
      _owners.followNow = true;
    }
    if (sourceChanged ||
        contextChanged ||
        oldWidget.height != widget.height ||
        oldWidget.rowHeight != widget.rowHeight ||
        oldWidget.rulerHeight != widget.rulerHeight ||
        oldWidget.viewportSettleDelay != widget.viewportSettleDelay) {
      _sections.loading.armViewportLoad();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (sourceChanged) _sections.selection.announceSelection();
      _sections.cursor.reconcileProgrammeCursor();
    });
  }

  @override
  void dispose() {
    _owners.viewportSettle?.cancel();
    _owners.clockTick?.cancel();
    _owners.pointerSettle?.cancel();
    _owners.verticalController
      ..removeListener(_sections.loading.onViewportMoved)
      ..dispose();
    _holdOk.reset();
    _owners.ownedFocusNode.dispose();
    _owners.nowFocusNode.dispose();
    widget.controller?._detach(this);
    super.dispose();
  }

  @override
  List<IptvChannel> get channels => widget.channels;
  @override
  String get sourceId => widget.sourceId;
  @override
  int get loadGeneration => widget.loadGeneration;
  @override
  SpotlightScheduleLoader get scheduleLoader => widget.scheduleLoader;
  @override
  SpotlightChannelActivate get onChannelActivate => widget.onChannelActivate;
  @override
  SpotlightProgrammeActivate get onProgrammeActivate =>
      widget.onProgrammeActivate;
  @override
  int get epgContextVersion => widget.epgContextVersion;
  @override
  ValueChanged<SpotlightTimelineSelection>? get onSelectionChanged =>
      widget.onSelectionChanged;
  @override
  bool get autofocus => widget.autofocus;
  @override
  VoidCallback? get onExitUp => widget.onExitUp;
  @override
  VoidCallback? get onExitLeft => widget.onExitLeft;
  @override
  SpotlightChannelActivate? get onChannelActions => widget.onChannelActions;
  @override
  bool get selectBeforeActivate => widget.selectBeforeActivate;
  @override
  DateTime Function() get now => widget.now;
  @override
  Duration get windowDuration => widget.windowDuration;
  @override
  Duration get viewportSettleDelay => widget.viewportSettleDelay;
  @override
  double get height => widget.height;
  @override
  bool get dense => widget.dense;
  @override
  double get identityWidth => widget.identityWidth;
  @override
  double get rowHeight => widget.rowHeight;
  @override
  double get rulerHeight => widget.rulerHeight;
  bool get _hasFocus => _owners.hasFocus;
  bool _restoreFocus() => _sections.selection.restoreFocus();
  bool _focusFirstChannel() => _sections.selection.focusFirstChannel();
  bool _focusChannelAt(int index) => _sections.selection.focusChannelAt(index);
  bool _focusChannel(IptvChannel channel) =>
      _sections.selection.focusChannel(channel);
  @override
  Widget build(BuildContext context) => _sections.frame.build(context);
}
