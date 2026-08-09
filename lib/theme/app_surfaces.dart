import 'package:flutter/material.dart';

import 'legacy_theme_boundary.dart';

/// Whether a surface follows the live app theme or stays frozen on legacy.
enum SurfaceKind { themed, frozen }

/// The per-destination classification — the containment plan's FIRST gate.
///
/// Every tab index in `main.dart`'s registry has an explicit entry; a missed
/// index would mean a screen silently changing colour, so [kindForTab] treats
/// an unmapped index as FROZEN (an unclassified new tab renders legacy — the
/// safe failure) and `tab_classification_test.dart` fails the build until the
/// entry is added.
abstract final class AppSurfaces {
  /// Must equal the length of `_MainPageState._titles`. Asserted by test.
  static const int tabCount = 20;

  static const Map<int, SurfaceKind> tabs = {
    0: SurfaceKind.frozen, //  inert slot (deprecated old Home)
    1: SurfaceKind.themed, //  Playlist
    2: SurfaceKind.themed, //  Downloads
    3: SurfaceKind.themed, //  Debrify TV
    4: SurfaceKind.themed, //  Real-Debrid     (Cloud family)
    5: SurfaceKind.themed, //  TorBox          (Cloud family)
    6: SurfaceKind.themed, //  PikPak          (Cloud family)
    7: SurfaceKind.themed, //  Addons
    8: SurfaceKind.themed, //  Settings
    9: SurfaceKind.themed, //  Stremio TV
    10: SurfaceKind.themed, // WebDAV          (Cloud family)
    11: SurfaceKind.themed, // Premiumize      (Cloud family)
    12: SurfaceKind.themed, // AllDebrid       (Cloud family)
    13: SurfaceKind.themed, // IPTV
    14: SurfaceKind.themed, // YouTube
    15: SurfaceKind.themed, // Home
    16: SurfaceKind.themed, // Cloud hub
    17: SurfaceKind.themed, // Search
    18: SurfaceKind.themed, // Discover
    19: SurfaceKind.themed, // Calendar
  };

  static SurfaceKind kindForTab(int index) =>
      tabs[index] ?? SurfaceKind.frozen;

  /// The tab-boundary factory: `_buildPage` routes every destination through
  /// here. Frozen tabs get the freeze plus a boundary-local snackbar host;
  /// themed tabs pass through and inherit the live scope above the Navigator.
  static Widget wrapTab(int index, Widget page) {
    if (kindForTab(index) == SurfaceKind.themed) return page;
    return LegacyThemeBoundary(withMessenger: true, child: page);
  }
}

/// The single active-surface signal all three containment mechanisms publish
/// to, and the only thing system-bar ownership reads.
///
/// "Active" resolves in this order:
/// 1. a bootstrap overlay (splash / onboarding) is up → frozen;
/// 2. otherwise the TOP-MOST page route decides — [FrozenLegacyPageRoute] is
///    frozen, any other pushed page route is themed;
/// 3. at the stack root, the selected tab's classification decides.
///
/// Why not `_selectedIndex` alone: an excluded player pushed over a themed
/// tab changes neither the index nor the tab flag, and a launch ident changes
/// no route at all.
class AppSurfaceState extends ChangeNotifier {
  AppSurfaceState._();

  static final AppSurfaceState instance = AppSurfaceState._();

  int _tabIndex = 15;
  // True from process start until AppInitializer reports the splash gone —
  // the launch ident owns the screen before the first route settles.
  bool _bootstrapActive = true;
  final List<Route<dynamic>> _pageRoutes = <Route<dynamic>>[];

  SurfaceKind get active {
    if (_bootstrapActive) return SurfaceKind.frozen;
    final top = _pageRoutes.isEmpty ? null : _pageRoutes.last;
    if (top == null || top.isFirst) return AppSurfaces.kindForTab(_tabIndex);
    return top is FrozenLegacyPageRoute
        ? SurfaceKind.frozen
        : SurfaceKind.themed;
  }

  void publishTab(int index) {
    if (_tabIndex == index) return;
    _tabIndex = index;
    notifyListeners();
  }

  void publishBootstrap(bool active) {
    if (_bootstrapActive == active) return;
    _bootstrapActive = active;
    notifyListeners();
  }

  // Route-stack bookkeeping — called only by [AppSurfaceRouteObserver].
  void _routePushed(Route<dynamic> route) {
    if (route is! PageRoute) return;
    _pageRoutes.add(route);
    notifyListeners();
  }

  void _routeGone(Route<dynamic> route) {
    if (_pageRoutes.remove(route)) notifyListeners();
  }

  void _routeReplaced(Route<dynamic>? newRoute, Route<dynamic>? oldRoute) {
    // Replace IN PLACE: a background route swapped under a covering page must
    // not surface as top-most in this model, or system bars would restyle for
    // a route the user cannot see.
    final at = oldRoute == null ? -1 : _pageRoutes.indexOf(oldRoute);
    if (at >= 0) {
      if (newRoute is PageRoute) {
        _pageRoutes[at] = newRoute;
      } else {
        _pageRoutes.removeAt(at);
      }
    } else if (newRoute is PageRoute) {
      _pageRoutes.add(newRoute);
    }
    notifyListeners();
  }

  /// Test-only: back to process-start state. The singleton otherwise leaks
  /// route/bootstrap state across widget tests.
  @visibleForTesting
  void reset() {
    _tabIndex = 15;
    _bootstrapActive = true;
    _pageRoutes.clear();
    notifyListeners();
  }
}

/// Keeps [AppSurfaceState]'s page-route stack current. Registered on the root
/// `MaterialApp.navigatorObservers` alongside `appRouteObserver`.
class AppSurfaceRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      AppSurfaceState.instance._routePushed(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      AppSurfaceState.instance._routeGone(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      AppSurfaceState.instance._routeGone(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      AppSurfaceState.instance._routeReplaced(newRoute, oldRoute);
}

/// A `MaterialPageRoute` whose content is frozen on legacy — the ONLY way an
/// excluded screen may be pushed. Wraps the builder in a [LegacyThemeBoundary]
/// (with the local snackbar host) and identifies itself to [AppSurfaceState]
/// so system bars follow.
class FrozenLegacyPageRoute<T> extends MaterialPageRoute<T> {
  FrozenLegacyPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(
         builder: (context) => LegacyThemeBoundary(
           withMessenger: true,
           child: Builder(builder: builder),
         ),
       );
}

/// Push an excluded screen. The player above all: every external
/// `VideoPlayerScreen` construction goes through here (or constructs a
/// [FrozenLegacyPageRoute] directly), enforced by the source-guard test.
Future<T?> pushExcluded<T extends Object?>(
  BuildContext context,
  WidgetBuilder builder, {
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) => Navigator.of(context).push<T>(
  FrozenLegacyPageRoute<T>(
    builder: builder,
    settings: settings,
    fullscreenDialog: fullscreenDialog,
  ),
);
