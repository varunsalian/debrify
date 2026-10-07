import 'dart:async';
import 'dart:math' as math;

import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_dependencies.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_sections.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:flutter/material.dart';

class SpotlightTimelineGuideLoading {
  final SpotlightTimelineDependencies _deps;
  SpotlightTimelineGuideLoading(this._deps);
  SpotlightTimelineWidgetView get widget => _deps.view;
  SpotlightTimelineOwners get _owners => _deps.owners;
  SpotlightTimelineSections get _sections => _deps.sections();

  // A two-line name and the subtitle both grow with accessibility text size.
  // Share the adjusted extent with painting, viewport loading and focus reveal.
  double get rowHeight {
    final scaler = MediaQuery.textScalerOf(_deps.context());
    final nameSize = widget.dense ? 12.5 : 14.0;
    final extra =
        math.max(0.0, scaler.scale(nameSize) - nameSize) * 2 * 1.1 +
        (widget.dense ? 0 : math.max(0.0, scaler.scale(10) - 10));
    return widget.rowHeight + extra.ceilToDouble();
  }

  SpotlightTimelineEntry? entryAt(int index) {
    if (index < 0 || index >= widget.channels.length) return null;
    return SpotlightTimelineEntry(
      sourceId: widget.sourceId,
      loadGeneration: widget.loadGeneration,
      sourceOrdinal: index,
      channel: widget.channels[index],
    );
  }

  void onViewportMoved() => armViewportLoad();

  void armViewportLoad() {
    _owners.viewportSettle?.cancel();
    final generation = ++_owners.requestGeneration;
    _owners.viewportSettle = Timer(widget.viewportSettleDelay, () {
      if (_deps.mounted() && generation == _owners.requestGeneration) {
        _loadVisibleRows(generation);
      }
    });
  }

  ({int first, int last})? visibleRange() {
    if (widget.channels.isEmpty || _owners.viewportHeight <= 0) return null;
    final offset = _owners.verticalController.hasClients
        ? _owners.verticalController.offset
        : 0.0;
    final extent = _owners.verticalController.hasClients
        ? _owners.verticalController.position.viewportDimension
        : _owners.viewportHeight;
    final first = (offset / rowHeight).floor().clamp(
      0,
      widget.channels.length - 1,
    );
    final last = ((offset + extent - 0.001) / rowHeight).floor().clamp(
      first,
      widget.channels.length - 1,
    );
    return (first: first, last: last);
  }

  void _loadVisibleRows(int generation) {
    final range = visibleRange();
    if (range == null) return;

    _evictDistantRows(range);

    var changed = false;
    for (var index = range.first; index <= range.last; index++) {
      final entry = entryAt(index)!;
      if (!entry.channel.isLive) continue;
      final key = entry.entryKey;
      final current = _owners.guides[key];
      if (current != null &&
          current.contextVersion == widget.epgContextVersion &&
          (current.status == SpotlightTimelineGuideStatus.ready ||
              current.status == SpotlightTimelineGuideStatus.error)) {
        continue;
      }

      final token = SpotlightTimelineLoadToken(
        generation: generation,
        entryKey: key,
        contextVersion: widget.epgContextVersion,
        sourceIndex: index,
        channel: entry.channel,
      );
      if (_owners.pendingLoads[key] == token) continue;

      _owners.pendingLoads[key] = token;
      _owners.guides[key] = SpotlightTimelineGuideSnapshot.loading(
        widget.epgContextVersion,
      );
      changed = true;
      unawaited(_loadSchedule(entry, token));
    }
    if (changed && _deps.mounted()) _deps.setState(() {});
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
        key.sourceOrdinal == _owners.cursorRow ||
        (key.sourceOrdinal >= keepFirst && key.sourceOrdinal <= keepLast);
    _owners.guides.removeWhere((key, _) => !keep(key));
    // Removing a token also invalidates its eventual completion through
    // [_accepts], without retaining a paged channel instance indefinitely.
    _owners.pendingLoads.removeWhere((key, _) => !keep(key));
  }

  Future<void> _loadSchedule(
    SpotlightTimelineEntry entry,
    SpotlightTimelineLoadToken token,
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
      _owners.pendingLoads.remove(token.entryKey);
      _deps.setState(() {
        _owners.guides[token.entryKey] = SpotlightTimelineGuideSnapshot.ready(
          token.contextVersion,
          List.unmodifiable(programmes),
        );
      });
      _sections.cursor.reconcileProgrammeCursor();
    } catch (_) {
      if (!_accepts(token)) {
        _removePendingIfCurrent(token);
        return;
      }
      _owners.pendingLoads.remove(token.entryKey);
      final selectedProgrammeFailed =
          token.sourceIndex == _owners.cursorRow &&
          _owners.cursorLane == SpotlightTimelineCursorLane.programme;
      _deps.setState(() {
        _owners.guides[token.entryKey] = SpotlightTimelineGuideSnapshot.error(
          token.contextVersion,
        );
        if (selectedProgrammeFailed) {
          _owners.cursorLane = SpotlightTimelineCursorLane.identity;
          _owners.selectedProgrammeStartMs = null;
        }
      });
      if (selectedProgrammeFailed) {
        _sections.selection.announceSelection();
      } else {
        _sections.cursor.reconcileProgrammeCursor();
      }
    }
  }

  void _removePendingIfCurrent(SpotlightTimelineLoadToken token) {
    if (identical(_owners.pendingLoads[token.entryKey], token)) {
      _owners.pendingLoads.remove(token.entryKey);
    }
  }

  bool _accepts(SpotlightTimelineLoadToken token) {
    if (!_deps.mounted() || token.generation != _owners.requestGeneration)
      return false;
    if (token.contextVersion != widget.epgContextVersion) return false;
    if (_owners.pendingLoads[token.entryKey] != token) return false;
    if (token.entryKey.sourceId != widget.sourceId ||
        token.entryKey.loadGeneration != widget.loadGeneration ||
        token.sourceIndex < 0 ||
        token.sourceIndex >= widget.channels.length ||
        token.entryKey.sourceOrdinal != token.sourceIndex) {
      return false;
    }
    return identical(widget.channels[token.sourceIndex], token.channel);
  }

  void retry(SpotlightTimelineEntry entry) {
    final key = entry.entryKey;
    final leaveRetryLane =
        _owners.cursorLane == SpotlightTimelineCursorLane.retry &&
        _owners.cursorRow == key.sourceOrdinal;
    _owners.guides.remove(key);
    _owners.pendingLoads.remove(key);
    final token = SpotlightTimelineLoadToken(
      generation: _owners.requestGeneration == 0
          ? ++_owners.requestGeneration
          : _owners.requestGeneration,
      entryKey: key,
      contextVersion: widget.epgContextVersion,
      sourceIndex: key.sourceOrdinal,
      channel: entry.channel,
    );
    _owners.pendingLoads[key] = token;
    _deps.setState(() {
      if (leaveRetryLane) {
        _owners.cursorLane = SpotlightTimelineCursorLane.identity;
        _owners.selectedProgrammeStartMs = null;
      }
      _owners.guides[key] = SpotlightTimelineGuideSnapshot.loading(
        widget.epgContextVersion,
      );
    });
    if (leaveRetryLane) _sections.selection.announceSelection();
    unawaited(_loadSchedule(entry, token));
  }

  List<EpgProgramme>? programmesForRow(int row) {
    final entry = entryAt(row);
    if (entry == null) return null;
    final snapshot = _owners.guides[entry.entryKey];
    return snapshot?.status == SpotlightTimelineGuideStatus.ready
        ? snapshot!.programmes
        : null;
  }

  bool hasGuideError(SpotlightTimelineEntry entry) =>
      entry.channel.isLive &&
      _owners.guides[entry.entryKey]?.status ==
          SpotlightTimelineGuideStatus.error;
}
