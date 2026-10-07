import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_dependencies.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_sections.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_widget_view.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpotlightTimelineCursor {
  final SpotlightTimelineDependencies _deps;
  SpotlightTimelineCursor(this._deps);
  SpotlightTimelineWidgetView get widget => _deps.view;
  SpotlightTimelineOwners get _owners => _deps.owners;
  SpotlightTimelineSections get _sections => _deps.sections();

  void onFocusChange(bool focused) {
    if (_owners.hasFocus == focused) return;
    _deps.setState(() {
      _owners.hasFocus = focused;
      if (!focused) {
        _owners.lastTappedCell = null;
        _deps.holdOk().reset();
      }
    });
  }

  KeyEventResult onKeyEvent(FocusNode node, KeyEvent event) {
    // The ruler's Now button owns its own keys; it is not a logical guide cell.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (isActivateOrSpaceKey(event.logicalKey) &&
        widget.onChannelActions != null &&
        _owners.cursorLane != SpotlightTimelineCursorLane.retry) {
      _sections.selection.cancelPointerSelection();
      return _deps.holdOk().handle(event);
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    _sections.selection.cancelPointerSelection();
    _deps.holdOk().reset();
    _owners.lastTappedCell = null;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.home) {
      _sections.window.jumpToNow();
      return KeyEventResult.handled;
    }
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
      activateCursor();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _moveVertical(int delta) {
    final target = _owners.cursorRow + delta;
    if (target < 0) {
      if (!_owners.followNow) {
        _owners.nowFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (widget.onExitUp == null) return KeyEventResult.ignored;
      widget.onExitUp!();
      return KeyEventResult.handled;
    }
    if (target >= widget.channels.length) return KeyEventResult.handled;
    _deps.setState(() {
      _owners.cursorRow = target;
      if (_owners.cursorLane == SpotlightTimelineCursorLane.programme) {
        final programmes = _sections.loading.programmesForRow(target);
        if (programmes == null) {
          _owners.selectedProgrammeStartMs = null;
          // A cached failure has no programme target to reconcile later.
          // Keep channel playback and RIGHT-to-retry visibly reachable.
          if (_sections.loading.hasGuideError(
            _sections.loading.entryAt(target)!,
          )) {
            _owners.cursorLane = SpotlightTimelineCursorLane.identity;
          }
        } else if (programmes.isEmpty) {
          _owners.cursorLane = SpotlightTimelineCursorLane.identity;
          _owners.selectedProgrammeStartMs = null;
        } else {
          final nearest = _nearestProgramme(programmes, _owners.cursorTimeMs);
          selectProgrammeValue(nearest);
        }
      } else if (_owners.cursorLane == SpotlightTimelineCursorLane.retry) {
        final entry = _sections.loading.entryAt(target);
        if (entry == null || !_sections.loading.hasGuideError(entry)) {
          _owners.cursorLane = SpotlightTimelineCursorLane.identity;
        }
      }
    });
    revealRow(target);
    _sections.selection.announceSelection();
    return KeyEventResult.handled;
  }

  KeyEventResult _moveHorizontal(int delta) {
    if (widget.channels.isEmpty) return KeyEventResult.handled;
    final entry = _sections.loading.entryAt(_owners.cursorRow)!;
    final programmes = _sections.loading.programmesForRow(_owners.cursorRow);
    if (_owners.cursorLane == SpotlightTimelineCursorLane.identity) {
      if (delta < 0) {
        if (widget.onExitLeft == null) return KeyEventResult.ignored;
        widget.onExitLeft!();
        return KeyEventResult.handled;
      }
      if (_sections.loading.hasGuideError(entry)) {
        _deps.setState(() {
          _owners.cursorLane = SpotlightTimelineCursorLane.retry;
          _owners.selectedProgrammeStartMs = null;
        });
        _sections.selection.announceSelection();
        return KeyEventResult.handled;
      }
      if (programmes == null || programmes.isEmpty) {
        return KeyEventResult.handled;
      }
      final nearest = _nearestProgramme(programmes, _owners.cursorTimeMs);
      _deps.setState(() {
        _owners.cursorLane = SpotlightTimelineCursorLane.programme;
        selectProgrammeValue(nearest);
        _sections.window.ensureProgrammeVisible(nearest);
      });
      _sections.selection.announceSelection();
      return KeyEventResult.handled;
    }

    if (_owners.cursorLane == SpotlightTimelineCursorLane.retry) {
      if (delta > 0) return KeyEventResult.handled;
      _deps.setState(() {
        _owners.cursorLane = SpotlightTimelineCursorLane.identity;
        _owners.selectedProgrammeStartMs = null;
      });
      _sections.selection.announceSelection();
      return KeyEventResult.handled;
    }

    if (programmes == null || programmes.isEmpty) {
      if (delta < 0) {
        _deps.setState(() {
          _owners.cursorLane = SpotlightTimelineCursorLane.identity;
          _owners.selectedProgrammeStartMs = null;
        });
        _sections.selection.announceSelection();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    var current = programmes.indexWhere(
      (programme) =>
          programme.start.millisecondsSinceEpoch ==
          _owners.selectedProgrammeStartMs,
    );
    if (current < 0) {
      current = programmes.indexOf(
        _nearestProgramme(programmes, _owners.cursorTimeMs),
      );
    }
    final target = current + delta;
    if (target < 0) {
      _deps.setState(() {
        _owners.cursorLane = SpotlightTimelineCursorLane.identity;
        _owners.selectedProgrammeStartMs = null;
      });
      _sections.selection.announceSelection();
      return KeyEventResult.handled;
    }
    if (target >= programmes.length) return KeyEventResult.handled;

    final programme = programmes[target];
    _deps.setState(() {
      selectProgrammeValue(programme);
      _sections.window.ensureProgrammeVisible(programme);
    });
    _sections.selection.announceSelection();
    return KeyEventResult.handled;
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

  void selectProgrammeValue(EpgProgramme programme) {
    _owners.selectedProgrammeStartMs = programme.start.millisecondsSinceEpoch;
    _owners.cursorTimeMs = _owners.selectedProgrammeStartMs!;
  }

  void reconcileProgrammeCursor() {
    if (!_deps.mounted() ||
        _owners.cursorLane != SpotlightTimelineCursorLane.programme)
      return;
    final programmes = _sections.loading.programmesForRow(_owners.cursorRow);
    if (programmes == null) return;
    if (programmes.isEmpty) {
      _deps.setState(() {
        _owners.cursorLane = SpotlightTimelineCursorLane.identity;
        _owners.selectedProgrammeStartMs = null;
      });
      _sections.selection.announceSelection();
      return;
    }
    final exact = programmes.where(
      (programme) =>
          programme.start.millisecondsSinceEpoch ==
          _owners.selectedProgrammeStartMs,
    );
    if (exact.isNotEmpty) {
      // A guide refresh can replace programme instances while retaining their
      // start time. Republish the current instance so preview data and actions
      // do not keep pointing at the object from the previous guide snapshot.
      _sections.selection.announceSelection();
      return;
    }
    final nearest = _nearestProgramme(programmes, _owners.cursorTimeMs);
    _deps.setState(() => selectProgrammeValue(nearest));
    _sections.selection.announceSelection();
  }

  void revealRow(int row) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() || !_owners.verticalController.hasClients) return;
      final position = _owners.verticalController.position;
      final top = row * _sections.loading.rowHeight;
      final bottom = top + _sections.loading.rowHeight;
      var target = position.pixels;
      if (top < position.pixels) {
        target = top;
      } else if (bottom > position.pixels + position.viewportDimension) {
        target = bottom - position.viewportDimension;
      }
      target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 0.5) return;
      _owners.verticalController.animateTo(
        target,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void activateCursor() {
    final entry = _sections.loading.entryAt(_owners.cursorRow);
    if (entry == null) return;
    if (_owners.cursorLane == SpotlightTimelineCursorLane.retry) {
      if (_sections.loading.hasGuideError(entry))
        _sections.loading.retry(entry);
      return;
    }
    if (_owners.cursorLane == SpotlightTimelineCursorLane.programme) {
      final programmes = _sections.loading.programmesForRow(_owners.cursorRow);
      if (programmes != null) {
        for (final programme in programmes) {
          if (programme.start.millisecondsSinceEpoch ==
              _owners.selectedProgrammeStartMs) {
            widget.onProgrammeActivate(entry, programme);
            return;
          }
        }
      }
    }
    activateIdentity(entry);
  }

  void activateIdentity(SpotlightTimelineEntry entry) =>
      widget.onChannelActivate(entry);
}
