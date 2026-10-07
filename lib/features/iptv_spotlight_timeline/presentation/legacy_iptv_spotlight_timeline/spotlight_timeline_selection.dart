import 'dart:async';

import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_dependencies.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_sections.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:flutter/material.dart';

class SpotlightTimelineSelectionActions {
  final SpotlightTimelineDependencies _deps;
  SpotlightTimelineSelectionActions(this._deps);
  SpotlightTimelineWidgetView get widget => _deps.view;
  SpotlightTimelineOwners get _owners => _deps.owners;
  SpotlightTimelineSections get _sections => _deps.sections();

  FocusNode get focusNode => _owners.ownedFocusNode;

  bool restoreFocus() {
    if (!_deps.mounted() || widget.channels.isEmpty) return false;
    cancelPointerSelection();
    if (_owners.cursorLane == SpotlightTimelineCursorLane.programme) {
      for (final programme
          in _sections.loading.programmesForRow(_owners.cursorRow) ??
              const <EpgProgramme>[]) {
        if (programme.start.millisecondsSinceEpoch ==
            _owners.selectedProgrammeStartMs) {
          _deps.setState(
            () => _sections.window.ensureProgrammeVisible(programme),
          );
          break;
        }
      }
    }
    focusNode.requestFocus();
    _sections.cursor.revealRow(_owners.cursorRow);
    announceSelection();
    return true;
  }

  void tapIdentity(int row) {
    final target = (_sections.loading.entryAt(row)!.entryKey, null);
    final activate =
        !widget.selectBeforeActivate || _owners.lastTappedCell == target;
    _owners.lastTappedCell = target;
    selectIdentity(row, activate: activate, fromPointer: true);
  }

  void tapProgramme(int row, EpgProgramme programme) {
    final target = (
      _sections.loading.entryAt(row)!.entryKey,
      programme.start.millisecondsSinceEpoch,
    );
    final activate =
        !widget.selectBeforeActivate || _owners.lastTappedCell == target;
    _owners.lastTappedCell = target;
    selectProgramme(row, programme, activate: activate, fromPointer: true);
  }

  bool focusFirstChannel() {
    if (!_deps.mounted() || widget.channels.isEmpty) return false;
    selectIdentity(0);
    return true;
  }

  bool focusChannelAt(int index) {
    if (!_deps.mounted() || index < 0 || index >= widget.channels.length)
      return false;
    selectIdentity(index);
    return true;
  }

  bool focusChannel(IptvChannel channel) {
    if (!_deps.mounted() || widget.channels.isEmpty) return false;
    final current = _sections.loading.entryAt(_owners.cursorRow);
    if (current != null && identical(current.channel, channel)) {
      selectIdentity(_owners.cursorRow);
      return true;
    }

    final range = _sections.loading.visibleRange();
    if (range != null) {
      for (var index = range.first; index <= range.last; index++) {
        if (identical(widget.channels[index], channel)) {
          selectIdentity(index);
          return true;
        }
      }
    }

    return false;
  }

  void selectIdentity(
    int row, {
    bool activate = false,
    bool requestFocus = true,
    bool fromPointer = false,
  }) {
    if (requestFocus) {
      cancelPointerSelection();
      focusNode.requestFocus();
    }
    _deps.setState(() {
      // Hover and controller selection can move the cursor without another
      // tap. Only consecutive taps on the same selected cell may activate it.
      if (_owners.lastTappedCell !=
          (_sections.loading.entryAt(row)!.entryKey, null)) {
        _owners.lastTappedCell = null;
      }
      _owners.cursorRow = row;
      _owners.cursorLane = SpotlightTimelineCursorLane.identity;
      _owners.selectedProgrammeStartMs = null;
    });
    _sections.cursor.revealRow(row);
    announceSelection(fromPointer: fromPointer);
    if (activate)
      _sections.cursor.activateIdentity(_sections.loading.entryAt(row)!);
  }

  void selectProgramme(
    int row,
    EpgProgramme programme, {
    bool activate = false,
    bool requestFocus = true,
    bool fromPointer = false,
  }) {
    if (requestFocus) {
      cancelPointerSelection();
      focusNode.requestFocus();
    }
    _deps.setState(() {
      if (_owners.lastTappedCell !=
          (
            _sections.loading.entryAt(row)!.entryKey,
            programme.start.millisecondsSinceEpoch,
          )) {
        _owners.lastTappedCell = null;
      }
      _owners.cursorRow = row;
      _owners.cursorLane = SpotlightTimelineCursorLane.programme;
      _sections.cursor.selectProgrammeValue(programme);
    });
    _sections.cursor.revealRow(row);
    announceSelection(fromPointer: fromPointer);
    if (activate)
      widget.onProgrammeActivate(_sections.loading.entryAt(row)!, programme);
  }

  void announceSelection({bool fromPointer = false}) {
    final callback = widget.onSelectionChanged;
    final entry = _sections.loading.entryAt(_owners.cursorRow);
    if (callback == null || entry == null) return;
    EpgProgramme? selected;
    if (_owners.cursorLane == SpotlightTimelineCursorLane.programme) {
      for (final programme
          in _sections.loading.programmesForRow(_owners.cursorRow) ??
              const []) {
        if (programme.start.millisecondsSinceEpoch ==
            _owners.selectedProgrammeStartMs) {
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

  void armPointerSelection(SpotlightTimelineEntry entry, VoidCallback select) {
    cancelPointerSelection();
    final sourceId = widget.sourceId;
    final loadGeneration = widget.loadGeneration;
    final contextVersion = widget.epgContextVersion;
    final channels = widget.channels;
    _owners.pointerSettle = Timer(const Duration(milliseconds: 375), () {
      _owners.pointerSettle = null;
      final row = entry.sourceOrdinal;
      if (!_deps.mounted() ||
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

  void cancelPointerSelection() {
    _owners.pointerSettle?.cancel();
    _owners.pointerSettle = null;
  }
}
