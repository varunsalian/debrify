import 'dart:async';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_constants_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

class SpotlightBoardSelection {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardSelection(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;
  void registerCard(SpotlightBoardCardState card) {
    _owners.selection.visibleCards.add(card);
    if (_owners.selection.largeCardInteractions &&
        (_owners.selection.selectedCard == null ||
            _owners.selection.selectionFromScroll)) {
      _sections.selection.queueScrollSelection();
    }
  }

  void unregisterCard(SpotlightBoardCardState card) {
    _owners.selection.visibleCards.remove(card);
    if (identical(_owners.selection.selectedCard, card)) {
      _owners.selection.selectedCard = null;
    }
    if (_owners.selection.largeCardInteractions &&
        _owners.selection.scrollingSources.isNotEmpty) {
      _sections.selection.queueScrollSelection();
    }
  }

  void selectCard(SpotlightBoardCardState? card, {required bool scrolling}) {
    // Changing widths during a drag can collapse a short row's scroll extent
    // and cancel the gesture. Hold painted widths until scrolling settles.
    for (final visible in _owners.selection.visibleCards) {
      if (visible.mounted) visible.freezeScrollWidth(scrolling);
    }
    final previous = _owners.selection.selectedCard;
    _owners.selection.selectedCard = card;
    if (!identical(previous, card) && previous?.mounted == true) {
      previous!.setWideSelection(false, moving: false);
    }
    card?.setWideSelection(true, moving: scrolling);
  }

  void interactWithCard(SpotlightBoardCardState card, bool active) {
    if (!_owners.selection.largeCardInteractions) return;
    // Hover can change as cards move beneath a stationary pointer.
    // Only scroll completion may release the moving state.
    if (_owners.selection.scrollingSources.isNotEmpty) {
      if (_sections.selection.pointerOwnsScrollSelection) {
        _sections.selection.queueScrollSelection();
      }
      return;
    }
    if (active) {
      _owners.selection.selectionFromScroll = false;
      _owners.selection.scrollInterruptedPreview = false;
      _sections.selection.selectCard(card, scrolling: false);
    } else if (!_owners.selection.selectionFromScroll &&
        identical(_owners.selection.selectedCard, card)) {
      // Hover and keyboard focus can overlap. Losing either one must not
      // hide the cursor while the other still owns this card.
      if (card.f || card.h) return;
      SpotlightBoardCardState? focused;
      for (final candidate in _owners.selection.visibleCards) {
        if (candidate.mounted && candidate.f) {
          focused = candidate;
          break;
        }
      }
      _sections.selection.selectCard(focused, scrolling: false);
    }
  }

  bool get pointerOwnsScrollSelection =>
      switch (Theme.of(_deps.context()).platform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      };

  bool onCardScroll(ScrollNotification notification) {
    if (!_owners.selection.largeCardInteractions) return false;
    final userStarted =
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle) ||
        (notification is ScrollStartNotification &&
            notification.dragDetails != null);
    final source = notification.context;
    if (userStarted) {
      _owners.selection.selectionFromScroll = true;
      if (notification.metrics.axis == Axis.vertical) {
        _owners.selection.scrollRowId = null;
      }
      if (source != null) _owners.selection.scrollingSources.add(source);
      _owners.selection.scrollInterruptedPreview = true;
      _sections.selection.queueScrollSelection();
    }
    // Layout corrections and ensureVisible are not new user gestures.
    if (!_owners.selection.scrollingSources.contains(source)) return false;
    if (notification is ScrollEndNotification) {
      _owners.selection.scrollingSources.remove(source);
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _sections.selection.queueScrollSelection();
    }
    return false;
  }

  /// Like the phone detail rail, scrolling supplies a visual reading cursor.
  /// Measure actual cards because Spotlight mixes shapes and expanded widths.
  /// Only one visible shelf/card owns it; cached offscreen cells never preview.
  void queueScrollSelection() {
    if (_owners.selection.selectionQueued) return;
    _owners.selection.selectionQueued = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _owners.selection.selectionQueued = false;
      if (!_deps.mounted()) return;
      _owners.selection.scrollingSources.removeWhere(
        (source) => !source.mounted,
      );
      if (!_owners.selection.visibleCards.any(
        (card) =>
            card.mounted && card.widget.rowId == _owners.selection.scrollRowId,
      )) {
        _owners.selection.scrollRowId = null;
      }
      if (!_owners.selection.largeCardInteractions) {
        _sections.selection.selectCard(null, scrolling: false);
        return;
      }

      if (_owners.selection.scrollInterruptedPreview) {
        _owners.selection.scrollInterruptedPreview = false;
        _owners.selection.selectedCard?.setWideSelection(true, moving: true);
      }
      // Desktop scrolling must not replace the pointer with the touch
      // reading cursor. MouseRegion also updates when content moves under
      // a stationary pointer; its callbacks queue another selection pass.
      if (_sections.selection.pointerOwnsScrollSelection) {
        SpotlightBoardCardState? hovered;
        SpotlightBoardCardState? focused;
        for (final card in _owners.selection.visibleCards) {
          if (!card.mounted || !card.widget.largeInteractions) continue;
          if (card.h) hovered = card;
          if (card.f) focused = card;
        }
        _owners.selection.selectionFromScroll = false;
        _sections.selection.selectCard(
          hovered ?? focused,
          scrolling: _owners.selection.scrollingSources.isNotEmpty,
        );
        if (_owners.selection.scrollingSources.isEmpty &&
            _owners.hero.desktopPreviewOwners.isEmpty)
          _sections.cadence.restartCadence();
        return;
      }
      final render = _deps.context().findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final bounds = Offset.zero & render.size;
      final readingY = bounds.height * 0.6;
      final readingX = _owners.scroll.lastMetrics?.gutter ?? 24;
      SpotlightBoardCardState? nearest;
      double bestRow = double.infinity;
      double bestColumn = double.infinity;
      for (final card in _owners.selection.visibleCards) {
        if (!card.mounted || !card.widget.largeInteractions) continue;
        if (_owners.selection.selectionFromScroll &&
            _owners.selection.scrollRowId != null &&
            card.widget.rowId != _owners.selection.scrollRowId)
          continue;
        final box = card.context.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        final rect =
            box.localToGlobal(Offset.zero, ancestor: render) & box.size;
        final visible = rect.intersect(bounds);
        if (visible.height < rect.height * 0.65 || visible.width < 24) continue;
        // Preserve explicit selection only while its card remains visible.
        if (!_owners.selection.selectionFromScroll &&
            identical(card, _owners.selection.selectedCard)) {
          return;
        }
        final row = (rect.center.dy - readingY).abs();
        final column = (rect.left - readingX).abs();
        if (row < bestRow - 4 ||
            ((row - bestRow).abs() <= 4 && column < bestColumn)) {
          nearest = card;
          bestRow = row;
          bestColumn = column;
        }
      }
      _sections.selection.selectCard(
        nearest,
        scrolling: _owners.selection.scrollingSources.isNotEmpty,
      );
      if (_owners.selection.scrollingSources.isEmpty &&
          _owners.hero.desktopPreviewOwners.isEmpty)
        _sections.cadence.restartCadence();
    });
  }

  /// Crossing detector for [_scrolledAway]: teardown on the way out,
  /// re-arm on the way back. Also called on metrics corrections (see
  /// [_board]) because a clamped offset never notifies the controller.
  void onBoardScrolled() {
    if (!_owners.scroll.scroll.hasClients) return;
    if (!view.dpad &&
        _owners.scroll.scroll.position.extentAfter <=
            SpotlightBoardConstantsState.touchLoadMoreThreshold) {
      unawaited(_sections.movement.loadMoreShelvesForTouch());
    }
    if (_owners.scroll.heroBandH <= 0) return;
    final away = _owners.scroll.scroll.offset > _owners.scroll.heroBandH * 0.35;
    if (away == _owners.constants.scrolledAway) return;
    _owners.constants.scrolledAway = away;
    if (away) {
      _owners.hero.cadence?.cancel();
      _owners.hero.cadence = null;
      _sections.cadence.stopRolling();
    } else {
      // Applies its own gates (DPAD hero focus, pref, dwell callback), so
      // this is safe to fire from any scroll back to the top.
      _sections.cadence.restartCadence();
    }
  }
}
