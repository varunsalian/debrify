import 'package:flutter/material.dart';

/// Hero flight for poster→detail-backdrop: always show the POSTER side of the
/// pair (the `from` hero on push, the `to` hero on pop), so the artwork the
/// user tapped is what grows into / shrinks out of the detail page — never a
/// half-loaded backdrop.
Widget homePosterFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final Hero posterHero =
      (direction == HeroFlightDirection.push
              ? fromHeroContext.widget
              : toHeroContext.widget)
          as Hero;
  // The shuttle renders in the root overlay, outside any Material — wrap so a
  // text placeholder (missing poster art) can't render unstyled mid-flight.
  return Material(type: MaterialType.transparency, child: posterHero.child);
}
