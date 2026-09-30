import 'home_integration_section.dart';
import 'home_continuation_return.dart';
import 'home_board_configuration_section.dart';
import 'dart:async';
import 'home_display_section.dart';
import 'home_hero_preview.dart';
import 'home_stage_section.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../../services/app_route_observer.dart';
import '../../../services/main_page_bridge.dart';

/// App-shell registrations for the Home, Search and Discover route variants.
///
/// Constructed instances own only the existing TV Home hero relays, independent
/// of layout: asynchronous style loads must not change listener ownership.
/// Static phase methods preserve the surrounding tab/layout registration order;
/// off-TV trailer playback retains its separate lifecycle.
class HomeHeroShellBridge {
  static void switchTab(int tab) => MainPageBridge.switchTab?.call(tab);

  static int get activeTvTabIndex => MainPageBridge.activeTvTabIndex;
  static bool isTvSidebarFocused() =>
      MainPageBridge.isTvSidebarFocused?.call() ?? false;
  static void focusTvSidebar() => MainPageBridge.focusTvSidebar?.call();

  /// Registers the Home layout's shell hooks at the original startup point.
  static void startHomeLayout({
    required bool Function() isTelevision,
    required bool restoredKeyword,
    required HomeDisplaySection display,
    required HomeHeroPreview preview,
    required HomeStageSection stage,
    // The Spotlight search sheet belongs to Search; Home registers its hooks.
    required bool Function() closeSearchSheet,
    required VoidCallback restoreSearchSheet,
  }) {
    // Home layout pref: loaded once here, then live-reloaded whenever the
    // Settings picker fires the bridge. HOME board instance only — the
    // Search tab keeps classic and must not steal the single bridge slot.
    // EVERY platform now: off-TV the pref decides Classic vs Spotlight,
    // and without this load the off-TV field would sit on its 'canvas'
    // initial forever (resolved to classic) whatever was chosen.
    unawaited(display.loadTvHomeStyle());
    unawaited(display.loadHomeCardOrientation());
    MainPageBridge.tvHomeStyleChanged = display.onTvHomeStyleChanged;
    if (isTelevision()) {
      MainPageBridge.tvHeroArtworkQualityChanged =
          display.onTvHeroArtworkQualityChanged;
      // Canvas theater mode: a dwell after trailer frames land recedes the
      // shelf so the video owns the screen; any key wakes it. Observe-only
      // handler (the key still performs its normal action) — same rule as
      // preview.onTakeoverKey.
      preview.heroTrailerShowing.addListener(
        stage.onCanvasTrailerShowingChanged,
      );
      HardwareKeyboard.instance.addHandler(stage.onCanvasTheaterKey);
      HardwareKeyboard.instance.addHandler(stage.stageHold.handleKeyEvent);
    } else {
      // Off-TV Home: system Back closes the Spotlight search sheet before
      // anything else may handle it. Routed through the bridge's tab-back
      // mechanism — a nested PopScope would race the root scope in
      // main.dart (its didPop==false path continues into double-back-exit
      // arming even when an inner scope consumed the press).
      MainPageBridge.registerTabBackHandler('home', closeSearchSheet);
      // Restored keyword results must come back with the sheet open — the
      // full-bleed shell would otherwise hide them behind a hero.
      if (restoredKeyword) restoreSearchSheet();
      // Hero trailer prefs for the OFF-TV Spotlight reel. Only the pieces
      // that mean "resolve and paint a video" — none of the TV shell
      // machinery the preview.heroTrailerActive block registers.
      MainPageBridge.addPlayerLaunchListener(preview.onContentPlayerLaunch);
      unawaited(preview.reloadHeroTrailerPrefs());
    }
  }

  /// Releases layout slots and keyboard hooks before stage resources are freed.
  static void disposeHomeLayout({
    required bool Function() isTelevisionHome,
    required HomeDisplaySection display,
    required HomeHeroPreview preview,
    required HomeStageSection stage,
  }) {
    if (MainPageBridge.tvHomeStyleChanged == display.onTvHomeStyleChanged) {
      MainPageBridge.tvHomeStyleChanged = null;
    }
    if (MainPageBridge.tvHeroArtworkQualityChanged ==
        display.onTvHeroArtworkQualityChanged) {
      MainPageBridge.tvHeroArtworkQualityChanged = null;
    }
    if (isTelevisionHome()) {
      preview.heroTrailerShowing.removeListener(
        stage.onCanvasTrailerShowingChanged,
      );
      HardwareKeyboard.instance.removeHandler(stage.onCanvasTheaterKey);
      HardwareKeyboard.instance.removeHandler(stage.stageHold.handleKeyEvent);
    }
  }

  /// Hooks integration changes and native playback returns before restoration.
  static void startContentSignals({
    required bool Function() isTelevisionSearch,
    required HomeIntegrationSection integration,
    required HomeContinuationReturn returning,
    required HomeDisplaySection display,
  }) {
    MainPageBridge.addIntegrationListener(integration.onIntegrationsChanged);
    // Playback that ran in a separate ACTIVITY (Android TV native player,
    // DeoVR, external app) pushes no Flutter route, so nothing on the board
    // ever learns it ended — the Continue Watching rows would keep showing the
    // episode the user just finished. This is that missing signal.
    MainPageBridge.addPlaybackReturnListener(returning.onPlaybackReturned);
    // Unconditional (the heroTrailerActive block below registers its own
    // trailer-suppression listener; this one is just the latch that tells the
    // post-playback refresh whether anything was actually played).
    MainPageBridge.addPlayerLaunchListener(returning.markPlaybackStarted);
    if (isTelevisionSearch()) {
      display.reloadSearchCardPrefs();
      MainPageBridge.addHomeSettingsListener(display.reloadSearchCardPrefs);
    }
  }

  /// Removes borrowed change listeners before their view owners are disposed.
  static void disposeContentSignals({
    required bool Function() offTvHome,
    required bool Function() closeSearchSheet,
    required VoidCallback searchSheetFocusChanged,
    required FocusNode Function() searchField,
    required HomeHeroPreview preview,
    required VoidCallback reclaimFocus,
    required HomeIntegrationSection integration,
    required HomeContinuationReturn returning,
    required HomeBoardConfigurationSection configuration,
    required HomeDisplaySection display,
  }) {
    if (offTvHome()) {
      // Same closure that registered — the bridge's mid-transition contract.
      MainPageBridge.unregisterTabBackHandler('home', closeSearchSheet);
      searchField().removeListener(searchSheetFocusChanged);
      MainPageBridge.removePlayerLaunchListener(preview.onContentPlayerLaunch);
    }
    // Safe no-op in the variants that never registered it.
    FocusManager.instance.removeListener(reclaimFocus);
    MainPageBridge.removeIntegrationListener(integration.onIntegrationsChanged);
    MainPageBridge.removePlaybackReturnListener(returning.onPlaybackReturned);
    MainPageBridge.removePlayerLaunchListener(returning.markPlaybackStarted);
    MainPageBridge.removeHomeSettingsListener(
      configuration.reloadForHomeSettings,
    );
    MainPageBridge.removeHomeSettingsListener(display.reloadSearchCardPrefs);
  }

  static void playSavedDebrifyChannel(String channelId) {
    if (MainPageBridge.watchDebrifyTvChannel != null) {
      MainPageBridge.watchDebrifyTvChannel!(channelId);
      return;
    }
    MainPageBridge.notifyDebrifyTvChannelToAutoPlay(channelId);
    MainPageBridge.switchTab?.call(MainTab.debrifyTv);
  }

  static void playSavedStremioChannel(String channelId) {
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel!(channelId);
      return;
    }
    MainPageBridge.notifyStremioTvChannelToAutoPlay(channelId);
    MainPageBridge.switchTab?.call(MainTab.stremioTv);
  }

  HomeHeroShellBridge({
    required Listenable takeover,
    required Listenable showing,
    required ValueChanged<bool> onSidebarFocus,
    required VoidCallback onChromeDim,
    required VoidCallback onLightsOff,
    required VoidCallback onContentLaunch,
    required KeyEventCallback onKey,
    required RouteAware routeAware,
    RouteObserver<PageRoute<dynamic>>? routeObserver,
  }) : _takeover = takeover,
       _showing = showing,
       _onSidebarFocus = onSidebarFocus,
       _onChromeDim = onChromeDim,
       _onLightsOff = onLightsOff,
       _onContentLaunch = onContentLaunch,
       _onKey = onKey,
       _routeAware = routeAware,
       _routeObserver = routeObserver ?? appRouteObserver {
    // Sidebar entry does not change the focused title: the callback stops its
    // preview on entry and re-arms focus-rest scheduling on exit.
    MainPageBridge.addTvSidebarFocusListener(_onSidebarFocus);
    // Match the board's takeover and lights-off state. Tint remains independent
    // of playback: relaying it here would flood the chrome at playback edges.
    _takeover.addListener(_onChromeDim);
    _showing.addListener(_onLightsOff);
    // Real content launches suppress previews even when a native activity does
    // not push a Flutter route. Takeover keys only observe; Select still acts.
    MainPageBridge.addPlayerLaunchListener(_onContentLaunch);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  final Listenable _takeover;
  final Listenable _showing;
  final ValueChanged<bool> _onSidebarFocus;
  final VoidCallback _onChromeDim;
  final VoidCallback _onLightsOff;
  final VoidCallback _onContentLaunch;
  final KeyEventCallback _onKey;
  final RouteAware _routeAware;
  final RouteObserver<PageRoute<dynamic>> _routeObserver;
  bool _disposed = false;

  void bindRoute(PageRoute<dynamic> route) {
    if (!_disposed) _routeObserver.subscribe(_routeAware, route);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    MainPageBridge.removeTvSidebarFocusListener(_onSidebarFocus);
    _takeover.removeListener(_onChromeDim);
    _showing.removeListener(_onLightsOff);
    MainPageBridge.removePlayerLaunchListener(_onContentLaunch);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _routeObserver.unsubscribe(_routeAware);
    // Unmount may run while the tree is locked. Retain the original conditional
    // post-frame resets, including their order; never repaint the shell here.
    if (MainPageBridge.tvChromeDim.value != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MainPageBridge.tvChromeDim.value = 0;
      });
    }
    if (MainPageBridge.tvHeroTint.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MainPageBridge.tvHeroTint.value = null;
      });
    }
    if (MainPageBridge.tvAmbientArt.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MainPageBridge.tvAmbientArt.value = null;
      });
    }
    if (MainPageBridge.tvStageLightsOff.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MainPageBridge.tvStageLightsOff.value = false;
      });
    }
  }
}
