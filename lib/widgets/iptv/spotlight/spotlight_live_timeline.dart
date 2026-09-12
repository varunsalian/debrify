import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/debrify_image_cache.dart';
import '../../../services/iptv_epg_service.dart';
import '../../../utils/tv_keys.dart';
import '../styles/iptv_style.dart';

/// Loads the schedule for one visible live channel.
///
/// Callers can wire this directly to
/// `IptvEpgService.instance.schedule(channel.url)`. Keeping the loader outside
/// this widget also lets a mixed-source list restore the correct guide context
/// before asking for a channel's programmes.
typedef SpotlightScheduleLoader =
    Future<List<EpgProgramme>> Function(IptvChannel channel);

typedef SpotlightChannelActivate = void Function(SpotlightTimelineEntry entry);

typedef SpotlightProgrammeActivate =
    void Function(SpotlightTimelineEntry entry, EpgProgramme programme);

/// The stable identity of an item in a flattened or virtual IPTV source.
///
/// A channel URL is deliberately absent: providers can repeat URLs and a
/// favorites/custom-list row can contain entries from several sources. The
/// source projection generation and row ordinal make those rows collision-free.
/// A filter or sort replacement must supply a new generation.
@immutable
class SpotlightTimelineEntryKey {
  final String sourceId;
  final int loadGeneration;
  final int sourceOrdinal;

  const SpotlightTimelineEntryKey({
    required this.sourceId,
    required this.loadGeneration,
    required this.sourceOrdinal,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpotlightTimelineEntryKey &&
          sourceId == other.sourceId &&
          loadGeneration == other.loadGeneration &&
          sourceOrdinal == other.sourceOrdinal;

  @override
  int get hashCode => Object.hash(sourceId, loadGeneration, sourceOrdinal);

  @override
  String toString() => '$sourceId/$loadGeneration/$sourceOrdinal';
}

/// A channel plus the source identity needed to reject recycled-row results.
@immutable
class SpotlightTimelineEntry {
  final String sourceId;
  final int loadGeneration;
  final int sourceOrdinal;
  final IptvChannel channel;

  const SpotlightTimelineEntry({
    required this.sourceId,
    required this.loadGeneration,
    required this.sourceOrdinal,
    required this.channel,
  });

  SpotlightTimelineEntryKey get entryKey => SpotlightTimelineEntryKey(
    sourceId: sourceId,
    loadGeneration: loadGeneration,
    sourceOrdinal: sourceOrdinal,
  );
}

/// The widget's single logical cursor, exposed for a surrounding preview pane.
@immutable
class SpotlightTimelineSelection {
  final SpotlightTimelineEntry entry;
  final EpgProgramme? programme;
  final bool fromPointer;

  const SpotlightTimelineSelection({
    required this.entry,
    this.programme,
    this.fromPointer = false,
  });
}

/// Imperative focus handoff used by the surrounding Browse/search shell.
///
/// The controller does not own a [FocusNode]; the timeline keeps sole node
/// ownership so replacing or disposing the section cannot leak focus state.
class IptvSpotlightTimelineController {
  _SpotlightLiveTimelineState? _state;

  bool get hasFocus => _state?._hasFocus ?? false;

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

  /// Injectable wall clock for deterministic cursor-following tests.
  @visibleForTesting
  final DateTime Function() now;

  final DateTime? initialWindowStart;
  final Duration windowDuration;
  final Duration viewportSettleDelay;
  final double height;
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
    this.now = DateTime.now,
    this.initialWindowStart,
    this.windowDuration = const Duration(hours: 4),
    this.viewportSettleDelay = const Duration(milliseconds: 375),
    this.height = 360,
    this.identityWidth = 224,
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

enum _CursorLane { identity, retry, programme }

enum _GuideStatus { loading, ready, error }

@immutable
class _GuideSnapshot {
  final _GuideStatus status;
  final int contextVersion;
  final List<EpgProgramme> programmes;

  const _GuideSnapshot.loading(this.contextVersion)
    : status = _GuideStatus.loading,
      programmes = const [];

  const _GuideSnapshot.ready(this.contextVersion, this.programmes)
    : status = _GuideStatus.ready;

  const _GuideSnapshot.error(this.contextVersion)
    : status = _GuideStatus.error,
      programmes = const [];
}

@immutable
class _LoadToken {
  final int generation;
  final SpotlightTimelineEntryKey entryKey;
  final int contextVersion;
  final int sourceIndex;
  final IptvChannel channel;

  const _LoadToken({
    required this.generation,
    required this.entryKey,
    required this.contextVersion,
    required this.sourceIndex,
    required this.channel,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LoadToken &&
          generation == other.generation &&
          entryKey == other.entryKey &&
          contextVersion == other.contextVersion &&
          sourceIndex == other.sourceIndex &&
          identical(channel, other.channel);

  @override
  int get hashCode => Object.hash(
    generation,
    entryKey,
    contextVersion,
    sourceIndex,
    identityHashCode(channel),
  );
}

class _SpotlightLiveTimelineState extends State<SpotlightLiveTimeline> {
  static const _background = Color(0xFF06111E);
  static const _identityBackground = Color(0xFF081522);
  static const _timelineBackground = Color(0xFF0B1929);

  final FocusNode _ownedFocusNode = FocusNode(
    debugLabel: 'spotlight-live-timeline',
  );
  final ScrollController _verticalController = ScrollController();
  final Map<SpotlightTimelineEntryKey, _GuideSnapshot> _guides = {};
  final Map<SpotlightTimelineEntryKey, _LoadToken> _pendingLoads = {};

  late DateTime _windowStart;
  late bool _followNow;
  late DateTime _lastGuideRefreshAt;
  Timer? _viewportSettle;
  Timer? _clockTick;
  Timer? _pointerSettle;
  static const Duration _guideRefreshInterval = Duration(minutes: 30);
  int _requestGeneration = 0;
  double _viewportHeight = 0;
  int _cursorRow = 0;
  _CursorLane _cursorLane = _CursorLane.identity;
  int? _selectedProgrammeStartMs;
  late int _cursorTimeMs;
  bool _hasFocus = false;

  FocusNode get _focusNode => _ownedFocusNode;

  @override
  void initState() {
    super.initState();
    final now = widget.now();
    _windowStart = widget.initialWindowStart ?? _defaultWindowStart(now);
    _followNow = widget.initialWindowStart == null;
    _cursorTimeMs = now.millisecondsSinceEpoch;
    _lastGuideRefreshAt = now;
    widget.controller?._attach(this);
    _verticalController.addListener(_onViewportMoved);
    _clockTick = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _onClockTick(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _armViewportLoad();
      if (widget.autofocus) _focusNode.requestFocus();
      _announceSelection();
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
      _cancelPointerSelection();
      _guides.clear();
      _pendingLoads.clear();
      _lastGuideRefreshAt = DateTime.now();
    }

    _cursorRow = _cursorRow.clamp(0, math.max(0, widget.channels.length - 1));
    if (widget.channels.isEmpty ||
        sourceChanged ||
        (contextChanged && _cursorLane == _CursorLane.retry)) {
      _cursorLane = _CursorLane.identity;
      _selectedProgrammeStartMs = null;
    }
    if (oldWidget.initialWindowStart != widget.initialWindowStart &&
        widget.initialWindowStart != null) {
      _windowStart = widget.initialWindowStart!;
      _followNow = false;
    } else if (oldWidget.initialWindowStart != widget.initialWindowStart &&
        widget.initialWindowStart == null) {
      _windowStart = _defaultWindowStart();
      _followNow = true;
    }
    if (sourceChanged ||
        contextChanged ||
        oldWidget.height != widget.height ||
        oldWidget.rowHeight != widget.rowHeight ||
        oldWidget.rulerHeight != widget.rulerHeight ||
        oldWidget.viewportSettleDelay != widget.viewportSettleDelay) {
      _armViewportLoad();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (sourceChanged) _announceSelection();
      _reconcileProgrammeCursor();
    });
  }

  @override
  void dispose() {
    _viewportSettle?.cancel();
    _clockTick?.cancel();
    _pointerSettle?.cancel();
    _verticalController
      ..removeListener(_onViewportMoved)
      ..dispose();
    _ownedFocusNode.dispose();
    widget.controller?._detach(this);
    super.dispose();
  }

  DateTime _defaultWindowStart([DateTime? at]) {
    final now = at ?? widget.now();
    final minute = now.minute < 30 ? 0 : 30;
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      minute,
    ).subtract(const Duration(minutes: 30));
  }

  void _onClockTick() {
    if (!mounted) return;
    final now = widget.now();
    if (_followNow) {
      _windowStart = _defaultWindowStart(now);
      // Until the user chooses a programme, RIGHT should enter the show that
      // is current at the time of the key press. Without advancing this anchor
      // it stayed pinned to widget creation and could select a show that ended
      // while the guide was left open.
      if (_selectedProgrammeStartMs == null) {
        _cursorTimeMs = now.millisecondsSinceEpoch;
      }
    }

    final guidesExpired =
        now.difference(_lastGuideRefreshAt) >= _guideRefreshInterval;
    var selectionReset = false;
    if (guidesExpired) {
      _lastGuideRefreshAt = now;
      // The service uses the same 30-minute TTL. Dropping only this widget's
      // bounded snapshots makes the next settled viewport request fresh data.
      _guides.clear();
      _pendingLoads.clear();
      if (_cursorLane == _CursorLane.retry) {
        _cursorLane = _CursorLane.identity;
        _selectedProgrammeStartMs = null;
        selectionReset = true;
      }
      _armViewportLoad();
    }
    setState(() {});
    if (selectionReset) _announceSelection();
  }

  SpotlightTimelineEntry? _entryAt(int index) {
    if (index < 0 || index >= widget.channels.length) return null;
    return SpotlightTimelineEntry(
      sourceId: widget.sourceId,
      loadGeneration: widget.loadGeneration,
      sourceOrdinal: index,
      channel: widget.channels[index],
    );
  }

  void _onViewportMoved() => _armViewportLoad();

  void _armViewportLoad() {
    _viewportSettle?.cancel();
    final generation = ++_requestGeneration;
    _viewportSettle = Timer(widget.viewportSettleDelay, () {
      if (mounted && generation == _requestGeneration) {
        _loadVisibleRows(generation);
      }
    });
  }

  ({int first, int last})? _visibleRange() {
    if (widget.channels.isEmpty || _viewportHeight <= 0) return null;
    final offset = _verticalController.hasClients
        ? _verticalController.offset
        : 0.0;
    final extent = _verticalController.hasClients
        ? _verticalController.position.viewportDimension
        : _viewportHeight;
    final first = (offset / widget.rowHeight).floor().clamp(
      0,
      widget.channels.length - 1,
    );
    final last = ((offset + extent - 0.001) / widget.rowHeight).floor().clamp(
      first,
      widget.channels.length - 1,
    );
    return (first: first, last: last);
  }

  void _loadVisibleRows(int generation) {
    final range = _visibleRange();
    if (range == null) return;

    _evictDistantRows(range);

    var changed = false;
    for (var index = range.first; index <= range.last; index++) {
      final entry = _entryAt(index)!;
      if (!entry.channel.isLive) continue;
      final key = entry.entryKey;
      final current = _guides[key];
      if (current != null &&
          current.contextVersion == widget.epgContextVersion &&
          (current.status == _GuideStatus.ready ||
              current.status == _GuideStatus.error)) {
        continue;
      }

      final token = _LoadToken(
        generation: generation,
        entryKey: key,
        contextVersion: widget.epgContextVersion,
        sourceIndex: index,
        channel: entry.channel,
      );
      if (_pendingLoads[key] == token) continue;

      _pendingLoads[key] = token;
      _guides[key] = _GuideSnapshot.loading(widget.epgContextVersion);
      changed = true;
      unawaited(_loadSchedule(entry, token));
    }
    if (changed && mounted) setState(() {});
  }

  void _evictDistantRows(({int first, int last}) visible) {
    final visibleCount = visible.last - visible.first + 1;
    final buffer = math.max(8, visibleCount * 2);
    final keepFirst = math.max(0, visible.first - buffer);
    final keepLast = math.min(
      widget.channels.length - 1,
      visible.last + buffer,
    );
    bool keep(SpotlightTimelineEntryKey key) =>
        key.sourceOrdinal == _cursorRow ||
        (key.sourceOrdinal >= keepFirst && key.sourceOrdinal <= keepLast);
    _guides.removeWhere((key, _) => !keep(key));
    // Removing a token also invalidates its eventual completion through
    // [_accepts], without retaining a paged channel instance indefinitely.
    _pendingLoads.removeWhere((key, _) => !keep(key));
  }

  Future<void> _loadSchedule(
    SpotlightTimelineEntry entry,
    _LoadToken token,
  ) async {
    try {
      final loaded = await widget.scheduleLoader(entry.channel);
      final programmes = List<EpgProgramme>.of(loaded)
        ..removeWhere((programme) => !programme.stop.isAfter(programme.start))
        ..sort((a, b) {
          final startOrder = a.start.compareTo(b.start);
          return startOrder != 0 ? startOrder : a.stop.compareTo(b.stop);
        });
      if (!_accepts(token)) {
        _removePendingIfCurrent(token);
        return;
      }
      _pendingLoads.remove(token.entryKey);
      setState(() {
        _guides[token.entryKey] = _GuideSnapshot.ready(
          token.contextVersion,
          List.unmodifiable(programmes),
        );
      });
      _reconcileProgrammeCursor();
    } catch (_) {
      if (!_accepts(token)) {
        _removePendingIfCurrent(token);
        return;
      }
      _pendingLoads.remove(token.entryKey);
      final selectedProgrammeFailed =
          token.sourceIndex == _cursorRow &&
          _cursorLane == _CursorLane.programme;
      setState(() {
        _guides[token.entryKey] = _GuideSnapshot.error(token.contextVersion);
        if (selectedProgrammeFailed) {
          _cursorLane = _CursorLane.identity;
          _selectedProgrammeStartMs = null;
        }
      });
      if (selectedProgrammeFailed) {
        _announceSelection();
      } else {
        _reconcileProgrammeCursor();
      }
    }
  }

  void _removePendingIfCurrent(_LoadToken token) {
    if (identical(_pendingLoads[token.entryKey], token)) {
      _pendingLoads.remove(token.entryKey);
    }
  }

  bool _accepts(_LoadToken token) {
    if (!mounted || token.generation != _requestGeneration) return false;
    if (token.contextVersion != widget.epgContextVersion) return false;
    if (_pendingLoads[token.entryKey] != token) return false;
    if (token.entryKey.sourceId != widget.sourceId ||
        token.entryKey.loadGeneration != widget.loadGeneration ||
        token.sourceIndex < 0 ||
        token.sourceIndex >= widget.channels.length ||
        token.entryKey.sourceOrdinal != token.sourceIndex) {
      return false;
    }
    return identical(widget.channels[token.sourceIndex], token.channel);
  }

  void _retry(SpotlightTimelineEntry entry) {
    final key = entry.entryKey;
    final leaveRetryLane =
        _cursorLane == _CursorLane.retry && _cursorRow == key.sourceOrdinal;
    _guides.remove(key);
    _pendingLoads.remove(key);
    final token = _LoadToken(
      generation: _requestGeneration == 0
          ? ++_requestGeneration
          : _requestGeneration,
      entryKey: key,
      contextVersion: widget.epgContextVersion,
      sourceIndex: key.sourceOrdinal,
      channel: entry.channel,
    );
    _pendingLoads[key] = token;
    setState(() {
      if (leaveRetryLane) {
        _cursorLane = _CursorLane.identity;
        _selectedProgrammeStartMs = null;
      }
      _guides[key] = _GuideSnapshot.loading(widget.epgContextVersion);
    });
    if (leaveRetryLane) _announceSelection();
    unawaited(_loadSchedule(entry, token));
  }

  void _onFocusChange(bool focused) {
    if (_hasFocus == focused) return;
    setState(() => _hasFocus = focused);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final activationKey = isActivateOrSpaceKey(key);
    // Holding OK must never stack player routes or confirmation dialogs.
    // Arrow repeats remain intentional for fast guide traversal.
    if (event is KeyRepeatEvent && activationKey) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) return _moveVertical(-1);
    if (key == LogicalKeyboardKey.arrowDown) return _moveVertical(1);
    if (key == LogicalKeyboardKey.arrowLeft) return _moveHorizontal(-1);
    if (key == LogicalKeyboardKey.arrowRight) return _moveHorizontal(1);
    if (activationKey) {
      _activateCursor();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _moveVertical(int delta) {
    final target = _cursorRow + delta;
    if (target < 0 || target >= widget.channels.length) {
      return KeyEventResult.ignored;
    }
    setState(() {
      _cursorRow = target;
      if (_cursorLane == _CursorLane.programme) {
        final programmes = _programmesForRow(target);
        if (programmes == null) {
          _selectedProgrammeStartMs = null;
          // A cached failure has no programme target to reconcile later.
          // Keep channel playback and RIGHT-to-retry visibly reachable.
          if (_hasGuideError(_entryAt(target)!)) {
            _cursorLane = _CursorLane.identity;
          }
        } else if (programmes.isEmpty) {
          _cursorLane = _CursorLane.identity;
          _selectedProgrammeStartMs = null;
        } else {
          final nearest = _nearestProgramme(programmes, _cursorTimeMs);
          _selectProgrammeValue(nearest);
        }
      } else if (_cursorLane == _CursorLane.retry) {
        final entry = _entryAt(target);
        if (entry == null || !_hasGuideError(entry)) {
          _cursorLane = _CursorLane.identity;
        }
      }
    });
    _revealRow(target);
    _announceSelection();
    return KeyEventResult.handled;
  }

  KeyEventResult _moveHorizontal(int delta) {
    if (widget.channels.isEmpty) return KeyEventResult.ignored;
    final entry = _entryAt(_cursorRow)!;
    final programmes = _programmesForRow(_cursorRow);
    if (_cursorLane == _CursorLane.identity) {
      if (delta < 0) return KeyEventResult.ignored;
      if (_hasGuideError(entry)) {
        setState(() {
          _cursorLane = _CursorLane.retry;
          _selectedProgrammeStartMs = null;
        });
        _announceSelection();
        return KeyEventResult.handled;
      }
      if (programmes == null || programmes.isEmpty) {
        return KeyEventResult.ignored;
      }
      final nearest = _nearestProgramme(programmes, _cursorTimeMs);
      setState(() {
        _cursorLane = _CursorLane.programme;
        _selectProgrammeValue(nearest);
        _ensureProgrammeVisible(nearest);
      });
      _announceSelection();
      return KeyEventResult.handled;
    }

    if (_cursorLane == _CursorLane.retry) {
      if (delta > 0) return KeyEventResult.ignored;
      setState(() {
        _cursorLane = _CursorLane.identity;
        _selectedProgrammeStartMs = null;
      });
      _announceSelection();
      return KeyEventResult.handled;
    }

    if (programmes == null || programmes.isEmpty) {
      if (delta < 0) {
        setState(() {
          _cursorLane = _CursorLane.identity;
          _selectedProgrammeStartMs = null;
        });
        _announceSelection();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    var current = programmes.indexWhere(
      (programme) =>
          programme.start.millisecondsSinceEpoch == _selectedProgrammeStartMs,
    );
    if (current < 0) {
      current = programmes.indexOf(
        _nearestProgramme(programmes, _cursorTimeMs),
      );
    }
    final target = current + delta;
    if (target < 0) {
      setState(() {
        _cursorLane = _CursorLane.identity;
        _selectedProgrammeStartMs = null;
      });
      _announceSelection();
      return KeyEventResult.handled;
    }
    if (target >= programmes.length) return KeyEventResult.ignored;

    final programme = programmes[target];
    setState(() {
      _selectProgrammeValue(programme);
      _ensureProgrammeVisible(programme);
    });
    _announceSelection();
    return KeyEventResult.handled;
  }

  List<EpgProgramme>? _programmesForRow(int row) {
    final entry = _entryAt(row);
    if (entry == null) return null;
    final snapshot = _guides[entry.entryKey];
    return snapshot?.status == _GuideStatus.ready ? snapshot!.programmes : null;
  }

  EpgProgramme _nearestProgramme(List<EpgProgramme> programmes, int targetMs) {
    EpgProgramme nearest = programmes.first;
    var nearestDistance = _distanceToProgramme(nearest, targetMs);
    for (final programme in programmes.skip(1)) {
      final distance = _distanceToProgramme(programme, targetMs);
      if (distance < nearestDistance) {
        nearest = programme;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  int _distanceToProgramme(EpgProgramme programme, int targetMs) {
    final start = programme.start.millisecondsSinceEpoch;
    final stop = programme.stop.millisecondsSinceEpoch;
    if (targetMs >= start && targetMs < stop) return 0;
    return targetMs < start ? start - targetMs : targetMs - stop;
  }

  void _selectProgrammeValue(EpgProgramme programme) {
    _selectedProgrammeStartMs = programme.start.millisecondsSinceEpoch;
    _cursorTimeMs = _selectedProgrammeStartMs!;
  }

  void _ensureProgrammeVisible(EpgProgramme programme) {
    final startMs = _windowStart.millisecondsSinceEpoch;
    final durationMs = widget.windowDuration.inMilliseconds;
    final endMs = startMs + durationMs;
    final programmeStart = programme.start.millisecondsSinceEpoch;
    final programmeStop = programme.stop.millisecondsSinceEpoch;
    if (programmeStart >= startMs && programmeStop <= endMs) return;

    final lead = (durationMs * 0.12).round();
    final newStartMs = programmeStart < startMs
        ? programmeStart - lead
        : programmeStop - durationMs + lead;
    _windowStart = DateTime.fromMillisecondsSinceEpoch(newStartMs);
    _followNow = false;
  }

  void _reconcileProgrammeCursor() {
    if (!mounted || _cursorLane != _CursorLane.programme) return;
    final programmes = _programmesForRow(_cursorRow);
    if (programmes == null) return;
    if (programmes.isEmpty) {
      setState(() {
        _cursorLane = _CursorLane.identity;
        _selectedProgrammeStartMs = null;
      });
      _announceSelection();
      return;
    }
    final exact = programmes.where(
      (programme) =>
          programme.start.millisecondsSinceEpoch == _selectedProgrammeStartMs,
    );
    if (exact.isNotEmpty) {
      // A guide refresh can replace programme instances while retaining their
      // start time. Republish the current instance so preview data and actions
      // do not keep pointing at the object from the previous guide snapshot.
      _announceSelection();
      return;
    }
    final nearest = _nearestProgramme(programmes, _cursorTimeMs);
    setState(() => _selectProgrammeValue(nearest));
    _announceSelection();
  }

  void _revealRow(int row) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalController.hasClients) return;
      final position = _verticalController.position;
      final top = row * widget.rowHeight;
      final bottom = top + widget.rowHeight;
      var target = position.pixels;
      if (top < position.pixels) {
        target = top;
      } else if (bottom > position.pixels + position.viewportDimension) {
        target = bottom - position.viewportDimension;
      }
      target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 0.5) return;
      _verticalController.animateTo(
        target,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _activateCursor() {
    final entry = _entryAt(_cursorRow);
    if (entry == null) return;
    if (_cursorLane == _CursorLane.retry) {
      if (_hasGuideError(entry)) _retry(entry);
      return;
    }
    if (_cursorLane == _CursorLane.programme) {
      final programmes = _programmesForRow(_cursorRow);
      if (programmes != null) {
        for (final programme in programmes) {
          if (programme.start.millisecondsSinceEpoch ==
              _selectedProgrammeStartMs) {
            widget.onProgrammeActivate(entry, programme);
            return;
          }
        }
      }
    }
    _activateIdentity(entry);
  }

  bool _hasGuideError(SpotlightTimelineEntry entry) =>
      entry.channel.isLive &&
      _guides[entry.entryKey]?.status == _GuideStatus.error;

  void _activateIdentity(SpotlightTimelineEntry entry) =>
      widget.onChannelActivate(entry);

  bool _focusFirstChannel() {
    if (!mounted || widget.channels.isEmpty) return false;
    _selectIdentity(0);
    return true;
  }

  bool _focusChannelAt(int index) {
    if (!mounted || index < 0 || index >= widget.channels.length) return false;
    _selectIdentity(index);
    return true;
  }

  bool _focusChannel(IptvChannel channel) {
    if (!mounted || widget.channels.isEmpty) return false;
    final current = _entryAt(_cursorRow);
    if (current != null && identical(current.channel, channel)) {
      _selectIdentity(_cursorRow);
      return true;
    }

    final range = _visibleRange();
    if (range != null) {
      for (var index = range.first; index <= range.last; index++) {
        if (identical(widget.channels[index], channel)) {
          _selectIdentity(index);
          return true;
        }
      }
    }

    return false;
  }

  void _selectIdentity(
    int row, {
    bool activate = false,
    bool requestFocus = true,
    bool fromPointer = false,
  }) {
    if (requestFocus) {
      _cancelPointerSelection();
      _focusNode.requestFocus();
    }
    setState(() {
      _cursorRow = row;
      _cursorLane = _CursorLane.identity;
      _selectedProgrammeStartMs = null;
    });
    _revealRow(row);
    _announceSelection(fromPointer: fromPointer);
    if (activate) _activateIdentity(_entryAt(row)!);
  }

  void _selectProgramme(
    int row,
    EpgProgramme programme, {
    bool activate = false,
    bool requestFocus = true,
    bool fromPointer = false,
  }) {
    if (requestFocus) {
      _cancelPointerSelection();
      _focusNode.requestFocus();
    }
    setState(() {
      _cursorRow = row;
      _cursorLane = _CursorLane.programme;
      _selectProgrammeValue(programme);
    });
    _revealRow(row);
    _announceSelection(fromPointer: fromPointer);
    if (activate) widget.onProgrammeActivate(_entryAt(row)!, programme);
  }

  void _announceSelection({bool fromPointer = false}) {
    final callback = widget.onSelectionChanged;
    final entry = _entryAt(_cursorRow);
    if (callback == null || entry == null) return;
    EpgProgramme? selected;
    if (_cursorLane == _CursorLane.programme) {
      for (final programme in _programmesForRow(_cursorRow) ?? const []) {
        if (programme.start.millisecondsSinceEpoch ==
            _selectedProgrammeStartMs) {
          selected = programme;
          break;
        }
      }
    }
    callback(
      SpotlightTimelineSelection(
        entry: entry,
        programme: selected,
        fromPointer: fromPointer,
      ),
    );
  }

  void _armPointerSelection(SpotlightTimelineEntry entry, VoidCallback select) {
    _cancelPointerSelection();
    final sourceId = widget.sourceId;
    final loadGeneration = widget.loadGeneration;
    final contextVersion = widget.epgContextVersion;
    final channels = widget.channels;
    _pointerSettle = Timer(const Duration(milliseconds: 375), () {
      _pointerSettle = null;
      final row = entry.sourceOrdinal;
      if (!mounted ||
          widget.sourceId != sourceId ||
          widget.loadGeneration != loadGeneration ||
          widget.epgContextVersion != contextVersion ||
          !identical(widget.channels, channels) ||
          row < 0 ||
          row >= widget.channels.length ||
          !identical(widget.channels[row], entry.channel)) {
        return;
      }
      select();
    });
  }

  void _cancelPointerSelection() {
    _pointerSettle?.cancel();
    _pointerSettle = null;
  }

  void _handlePointerSignal(PointerSignalEvent signal, double timelineWidth) {
    if (signal is! PointerScrollEvent || timelineWidth <= 0) return;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final shift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final deltaPixels = signal.scrollDelta.dx.abs() > 0.01
        ? signal.scrollDelta.dx
        : shift
        ? signal.scrollDelta.dy
        : 0.0;
    if (deltaPixels == 0) return;
    final deltaMs =
        deltaPixels / timelineWidth * widget.windowDuration.inMilliseconds;
    setState(() {
      _windowStart = DateTime.fromMillisecondsSinceEpoch(
        _windowStart.millisecondsSinceEpoch + deltaMs.round(),
      );
      _followNow = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = IptvStyleTokens.spotlight;
    return SizedBox(
      height: widget.height,
      child: Material(
        color: _background,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(14),
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onFocusChange: _onFocusChange,
          onKeyEvent: _onKeyEvent,
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
                  onPointerSignal: (signal) =>
                      _handlePointerSignal(signal, timelineWidth),
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          _buildRuler(tokens, identityWidth, timelineWidth),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, rowConstraints) {
                                if (_viewportHeight !=
                                    rowConstraints.maxHeight) {
                                  _viewportHeight = rowConstraints.maxHeight;
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) _armViewportLoad();
                                  });
                                }
                                if (widget.channels.isEmpty) {
                                  return _buildEmpty(tokens);
                                }
                                return ListView.builder(
                                  key: const ValueKey(
                                    'spotlight-live-timeline-rows',
                                  ),
                                  controller: _verticalController,
                                  itemExtent: widget.rowHeight,
                                  itemCount: widget.channels.length,
                                  physics: const ClampingScrollPhysics(),
                                  itemBuilder: (context, index) => _buildRow(
                                    tokens,
                                    _entryAt(index)!,
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
              color: _identityBackground,
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
                    _dayHeading(_windowStart),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${widget.channels.length}',
                  style: TextStyle(
                    color: tokens.fgFaint,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: timelineWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _timelineBackground,
                border: Border(bottom: BorderSide(color: tokens.hairline)),
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final mark in _rulerMarks())
                    Positioned(
                      left: _timeX(mark, timelineWidth),
                      top: 0,
                      bottom: 0,
                      child: _RulerMark(
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

  List<DateTime> _rulerMarks() => spotlightRulerMarks(
    windowStart: _windowStart,
    windowDuration: widget.windowDuration,
  );

  double _timeX(DateTime time, double width) =>
      (time.millisecondsSinceEpoch - _windowStart.millisecondsSinceEpoch) /
      widget.windowDuration.inMilliseconds *
      width;

  Widget _buildEmpty(IptvStyleTokens tokens) {
    return Container(
      color: _timelineBackground,
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

  Widget _buildRow(
    IptvStyleTokens tokens,
    SpotlightTimelineEntry entry,
    int row,
    double identityWidth,
    double timelineWidth,
  ) {
    return RepaintBoundary(
      key: ValueKey(('spotlight-row', entry.entryKey)),
      child: Row(
        children: [
          SizedBox(
            width: identityWidth,
            child: _buildIdentity(tokens, entry, row),
          ),
          SizedBox(
            width: timelineWidth,
            child: _buildProgrammeTrack(tokens, entry, row, timelineWidth),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentity(
    IptvStyleTokens tokens,
    SpotlightTimelineEntry entry,
    int row,
  ) {
    final snapshot = _guides[entry.entryKey];
    final programmeIsRefreshing =
        _cursorLane == _CursorLane.programme &&
        (snapshot == null || snapshot.status == _GuideStatus.loading);
    final selected =
        _hasFocus &&
        _cursorRow == row &&
        (_cursorLane == _CursorLane.identity || programmeIsRefreshing);
    final channel = entry.channel;
    final guideUnavailable =
        channel.isLive && snapshot?.status == _GuideStatus.error;
    return Semantics(
      button: true,
      focusable: true,
      focused: selected,
      selected: selected,
      label: [
        if (channel.channelNumber != null) 'Channel ${channel.channelNumber}',
        channel.name,
        if (channel.group != null && channel.group!.isNotEmpty) channel.group!,
        channel.isLive ? 'Live' : 'On demand',
        if (guideUnavailable) 'Guide unavailable',
      ].join(', '),
      hint: guideUnavailable
          ? 'Press OK to play the channel or RIGHT to retry the guide'
          : null,
      onTap: () => _selectIdentity(row, activate: true),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        // Match the existing channel rows: crossing the guide does not churn
        // the preview or steal search focus; resting selects after a dwell.
        onEnter: (_) => _armPointerSelection(
          entry,
          () => _selectIdentity(row, requestFocus: false, fromPointer: true),
        ),
        onExit: (_) => _cancelPointerSelection(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectIdentity(row, activate: true),
          child: AnimatedScale(
            scale: selected ? 1.018 : 1,
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              key: ValueKey(('spotlight-identity', entry.entryKey)),
              duration: const Duration(milliseconds: 130),
              margin: const EdgeInsets.fromLTRB(6, 5, 7, 5),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: selected ? tokens.focusFill : _identityBackground,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? tokens.focusFill! : tokens.hairline,
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
                  if (channel.channelNumber != null) ...[
                    SizedBox(
                      width: 34,
                      child: Text(
                        channel.channelNumber.toString(),
                        style: TextStyle(
                          color: selected
                              ? tokens.focusInk!.withValues(alpha: 0.64)
                              : tokens.fgFaint,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                  _ChannelMark(
                    logoUrl: channel.logoUrl,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? tokens.focusInk : tokens.fg,
                            fontSize: 13,
                            height: 1.05,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          channel.group?.trim().isNotEmpty == true
                              ? channel.group!
                              : 'Live television',
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

  Widget _buildProgrammeTrack(
    IptvStyleTokens tokens,
    SpotlightTimelineEntry entry,
    int row,
    double width,
  ) {
    if (!entry.channel.isLive) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: _timelineBackground,
          border: Border(
            bottom: BorderSide(color: tokens.hairline),
            left: BorderSide(color: tokens.hairline),
          ),
        ),
        child: _GuideMessage(
          label: 'On demand  ·  Press OK to open',
          color: tokens.fgFaint,
          leading: Icon(
            Icons.play_circle_outline_rounded,
            size: 15,
            color: tokens.fgDim,
          ),
          onTap: () => _selectIdentity(row, activate: true),
        ),
      );
    }
    final snapshot = _guides[entry.entryKey];
    final status = snapshot?.status ?? _GuideStatus.loading;
    final retrySelected =
        _hasFocus &&
        _cursorRow == row &&
        _cursorLane == _CursorLane.retry &&
        status == _GuideStatus.error;
    final visible =
        <
          ({
            int index,
            EpgProgramme programme,
            SpotlightProgrammeGeometry geometry,
          })
        >[];
    if (status == _GuideStatus.ready) {
      for (var index = 0; index < snapshot!.programmes.length; index++) {
        final programme = snapshot.programmes[index];
        final geometry = spotlightProgrammeGeometry(
          programmeStart: programme.start,
          programmeStop: programme.stop,
          windowStart: _windowStart,
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
        color: _timelineBackground,
        border: Border(
          bottom: BorderSide(color: tokens.hairline),
          left: BorderSide(color: tokens.hairline),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (final mark in _rulerMarks())
            Positioned(
              left: _timeX(mark, width),
              top: 0,
              bottom: 0,
              child: Container(width: 1, color: tokens.hairline),
            ),
          if (status == _GuideStatus.loading)
            _GuideMessage(
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
          else if (status == _GuideStatus.error)
            _GuideMessage(
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
              onTap: () => _retry(entry),
            )
          else if (snapshot!.programmes.isEmpty)
            _GuideMessage(
              key: ValueKey(('spotlight-empty', entry.entryKey)),
              label: 'No programme information',
              color: tokens.fgFaint,
            )
          else if (visible.isEmpty)
            _GuideMessage(
              key: ValueKey(('spotlight-window-empty', entry.entryKey)),
              label: 'No information in this time window',
              color: tokens.fgFaint,
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
    final selected =
        _hasFocus &&
        _cursorRow == row &&
        _cursorLane == _CursorLane.programme &&
        _selectedProgrammeStartMs == startMs;
    final now = DateTime.now();
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
      selected: selected,
      label:
          '${programme.title}, ${_formatTime(programme.start)} to '
          '${_formatTime(programme.stop)}'
          '${programme.hasArchive && isPast ? ', replay available' : ''}',
      onTap: () => _selectProgramme(row, programme, activate: true),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _armPointerSelection(
          entry,
          () => _selectProgramme(
            row,
            programme,
            requestFocus: false,
            fromPointer: true,
          ),
        ),
        onExit: (_) => _cancelPointerSelection(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectProgramme(row, programme, activate: true),
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
                    : isNow
                    ? tokens.selectedTint
                    : const Color(0xFF10243A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? tokens.focusFill!
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
                        const SizedBox(height: 5),
                        Text(
                          '${_formatTime(programme.start)} – '
                          '${_formatTime(programme.stop)}',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.62),
                            fontSize: 9.5,
                            height: 1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
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

  Widget _buildPlayhead(
    double identityWidth,
    double timelineWidth,
    IptvStyleTokens tokens,
  ) {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final startMs = _windowStart.millisecondsSinceEpoch;
    final endMs = startMs + widget.windowDuration.inMilliseconds;
    if (nowMs < startMs || nowMs > endMs || timelineWidth <= 0) {
      return const SizedBox.shrink();
    }
    final x = identityWidth + _timeX(now, timelineWidth);
    return Positioned(
      left: x - 1,
      top: 16,
      bottom: 0,
      child: IgnorePointer(
        child: Semantics(
          label: 'Current time ${_formatTime(now)}',
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

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String _dayHeading(DateTime time) {
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
    final now = DateTime.now();
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

class _RulerMark extends StatelessWidget {
  final DateTime time;
  final Color color;
  final Color lineColor;

  const _RulerMark({
    required this.time,
    required this.color,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final local = time.toLocal();
    final label =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      width: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: lineColor),
          ),
          Positioned(
            left: 7,
            top: 10,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideMessage extends StatelessWidget {
  final String label;
  final Color color;
  final Widget? leading;
  final VoidCallback? onTap;
  final String? hint;
  final bool focused;
  final Color? focusFill;
  final Color? focusInk;

  const _GuideMessage({
    super.key,
    required this.label,
    required this.color,
    this.leading,
    this.onTap,
    this.hint,
    this.focused = false,
    this.focusFill,
    this.focusInk,
  }) : assert(
         !focused || (focusFill != null && focusInk != null),
         'A focused guide message needs focus colors.',
       );

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: focused
          ? BoxDecoration(
              color: focusFill,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 16,
                  spreadRadius: -5,
                ),
              ],
            )
          : null,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: focused ? focusInk : color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(label: label, child: content);
    }
    return Semantics(
      excludeSemantics: true,
      button: true,
      focusable: true,
      focused: focused,
      selected: focused,
      label: label,
      hint: hint,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

class _ChannelMark extends StatelessWidget {
  final String? logoUrl;
  final bool selected;
  final IptvStyleTokens tokens;

  const _ChannelMark({
    required this.logoUrl,
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
      width: 38,
      height: 38,
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
