import 'dart:async';
import 'package:flutter/material.dart';
import 'home_hero_preview.dart';
import 'home_hero_shell_bridge.dart';

/// Owns the hero's shell relays and borrowed route registration.
class HomeHeroShell {
  HomeHeroShell(this._preview, this._chromeDim, this._lightsOff);
  final HomeHeroPreview _preview;
  final ValueNotifier<double> _chromeDim;
  final ValueNotifier<bool> _lightsOff;
  HomeHeroShellBridge? _binding;

  void start(RouteAware routeAware) {
    // Ambient hero trailer gates (Home board TV only) — read before the board
    // loads so the seeded first spotlight can already schedule its trailer.
    if (_preview.heroTrailerActive) {
      _binding = HomeHeroShellBridge(
        takeover: _preview.heroTrailerTakeover,
        showing: _preview.heroTrailerShowing,
        onSidebarFocus: _preview.onTvSidebarFocusChanged,
        onChromeDim: relayChromeDim,
        onLightsOff: relayLightsOff,
        onContentLaunch: _preview.onContentPlayerLaunch,
        onKey: _preview.onTakeoverKey,
        routeAware: routeAware,
      );
      unawaited(_preview.reloadHeroTrailerPrefs(initial: true));
    }
  }

  /// Mirror the takeover arc onto the app-shell notifier (sidebar rail hide).
  void relayChromeDim() {
    _chromeDim.value = _preview.heroTrailerTakeover.value;
  }

  /// Mirror the ambient trailer's lights-off state onto the app-shell
  /// notifier — the shell veils the sidebar rail in lock-step with the
  /// board's own row/hero veils, so the whole room goes dark together.
  void relayLightsOff() {
    _lightsOff.value = _preview.heroTrailerShowing.value;
  }

  void bindRoute(BuildContext context) {
    if (_preview.heroTrailerActive) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) _binding?.bindRoute(route);
    }
  }

  void didPushNext() {
    if (!_preview.heroTrailerActive) return;
    _preview.clearHeroTrailer();
  }

  void dispose() => _binding?.dispose();
}
