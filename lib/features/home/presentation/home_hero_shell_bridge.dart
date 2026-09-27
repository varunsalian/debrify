import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../../services/app_route_observer.dart';
import '../../../services/main_page_bridge.dart';

/// The TV Home hero's borrowed shell, keyboard and route registrations.
///
/// Create only for the existing TV Home capacity gate, independent of layout:
/// styles load asynchronously and must not change listener ownership. Off-TV
/// trailer playback has a separate lifecycle and does not own these relays.
class HomeHeroShellBridge {
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
