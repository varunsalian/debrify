import 'dart:async';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:flutter/material.dart';

class SpotlightBoardCadence {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardCadence(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;

  /// One funnel for leaving the rolling state, so no exit path can forget to
  /// tell the host to tear the video down.
  void stopRolling() {
    if (!_owners.hero.rolling) return;
    if (_deps.mounted()) _deps.setState(() => _owners.hero.rolling = false);
    view.onTrailerStop?.call();
  }

  /// A desktop IPTV card is about to mount its own video decoder. The hero
  /// must yield its output lease before that mount; otherwise MediaKit queues
  /// the card behind an ambient trailer that loops indefinitely. Re-arm the
  /// hero only when the pointer has left every live card.
  void onDesktopPreviewActivityChanged(Object owner, bool active) {
    if (view.dpad) return;
    final hadPreview = _owners.hero.desktopPreviewOwners.isNotEmpty;
    if (active) {
      _owners.hero.desktopPreviewOwners.add(owner);
    } else {
      _owners.hero.desktopPreviewOwners.remove(owner);
    }
    final hasPreview = _owners.hero.desktopPreviewOwners.isNotEmpty;
    if (hadPreview == hasPreview) return;

    if (hasPreview) {
      _owners.hero.cadence?.cancel();
      _owners.hero.cadence = null;
      if (_owners.hero.rolling && _deps.mounted()) {
        _deps.setState(() => _owners.hero.rolling = false);
      }
      // Also cancels a hero resolve that has not reached its first frame yet.
      view.onTrailerStop?.call();
      return;
    }

    _sections.cadence.restartCadence();
  }

  void restartCadence() {
    if (_owners.selection.largeCardInteractions &&
        _owners.selection.scrollingSources.isNotEmpty) {
      return;
    }
    _owners.hero.cadence?.cancel();
    // Nulled, not just cancelled: didUpdateWidget's reconcile decides "is a
    // timer armed" by null-ness, and a cancelled-but-non-null handle reads
    // as armed.
    _owners.hero.cadence = null;
    if (!_deps.mounted()) return;
    if (_owners.hero.dwelledHeroId != null &&
        _owners.hero.dwelledHeroId == _sections.heroArt.heroItem?.id) {
      return;
    }
    _owners.hero.rolling = false;
    // The active card owns the one available decoder. A rebuild caused by
    // loading more shelves or resolving hero art must not re-arm the hero
    // underneath it.
    if (_owners.hero.desktopPreviewOwners.isNotEmpty) return;
    // With no trailer to arm there is nothing to schedule. The reel itself
    // still moves only on input.
    if (!view.trailersEnabled || view.onDwell == null) return;
    // TV: frozen while focus is off the hero. `_row == -1` alone is NOT that
    // test: it stays -1 when focus goes to the sidebar, another tab, or a
    // pushed detail route — the node's own `hasFocus` is the real question.
    // Touch has no focus to gate on; visibility is checked at FIRE time.
    if (view.dpad && (_owners.navigation.row >= 0 || !view.heroNode.hasFocus)) {
      return;
    }
    // A short, cancellable dwell before the trailer resolve starts, so a
    // focus or route change (or a quick swipe on) stops it first.
    _owners.hero.cadence = Timer(
      const Duration(seconds: 2),
      _sections.cadence.onArtDone,
    );
  }

  /// Dot tap / swipe target: show slide [i] and restart the clock.
  void jumpTo(int i) {
    if (i < 0 || i >= view.hero.length) return;
    if (view.hero[i].id == _owners.hero.heroId) return;
    _sections.cadence.stopRolling();
    _owners.hero.dwelledHeroId = null;
    _deps.setState(() => _owners.hero.heroId = view.hero[i].id);
    view.refreshMetadataPresentation();
    _sections.ambient.probe();
    _sections.cadence.restartCadence();
  }

  void onArtDone() {
    // The one-shot is consumed the moment this runs — null it, or the
    // reconcile in didUpdateWidget reads a dead handle as "armed" and a
    // disable→re-enable of trailers strands the cadence forever.
    _owners.hero.cadence = null;
    if (!_deps.mounted() || _owners.navigation.row >= 0) return;
    // Scrolled off the hero (touch/wheel — a DPAD descent goes through
    // [_down] and cancels the clock itself): do not start a decoder behind
    // the veil. No re-arm — scrolling back under the threshold restarts the
    // cadence via [_onBoardScrolled].
    if (_owners.constants.scrolledAway) return;
    // Touch: a covered or backgrounded board must not spin up an engine for
    // a hero nobody can see. Poll gently until visible; this retry delay is
    // not part of the visible start cadence.
    if (!view.dpad) {
      final route = ModalRoute.of(_deps.context());
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final visible =
          (route == null || route.isCurrent) &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed);
      if (!visible) {
        _owners.hero.cadence = Timer(
          SpotlightBoardHeroState.hiddenRetry,
          _sections.cadence.onArtDone,
        );
        return;
      }
    }
    final item = _sections.heroArt.heroItem;
    if (item == null) {
      // didUpdateWidget re-arms when the first hero arrives; polling an empty
      // reel here would create a zero-delay loop.
      return;
    }
    if (view.trailersEnabled && view.onDwell != null) {
      _owners.hero.dwelledHeroId = item.id;
      // Once a trailer is rolling the reel stays put — the video loops until
      // the next deliberate move (swipe, dot tap, LEFT/RIGHT, DOWN).
      _deps.setState(() => _owners.hero.rolling = true);
      view.onDwell!(item);
    }
    // Never an advance — see the cadence comment.
  }

  /// Re-arms when the hero actually holds focus and stops the moment it does
  /// not — covering the sidebar, tab switches and pushed routes in one place.
  void onHeroFocus() {
    if (!_deps.mounted()) return;
    if (view.heroNode.hasFocus) {
      _sections.cadence.restartCadence();
    } else {
      _owners.hero.cadence?.cancel();
      _owners.hero.dwelledHeroId = null;
      _sections.cadence.stopRolling();
    }
  }
}
