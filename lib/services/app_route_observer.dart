import 'package:flutter/widgets.dart';

/// App-wide route observer. Screens that need to refresh when a route pushed on
/// top of them pops back (e.g. the See-All grids, which re-fetch after a detail
/// or player route closes) mix in [RouteAware] and subscribe to this.
///
/// Registered on the root [MaterialApp.navigatorObservers].
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
