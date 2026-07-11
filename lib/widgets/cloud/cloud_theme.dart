import 'package:flutter/material.dart';

/// Shared design tokens for the restyled cloud/debrid file screens.
///
/// Values intentionally mirror the Search screen board (`kStremioBg` /
/// `kStremioAccent` and the radial bloom in `search_screen.dart`) so the six
/// cloud pages read as the same app. Keep the two in sync if either changes.
abstract final class CloudTheme {
  static const Color bg = Color(0xFF0D0B1A);
  static const Color accent = Color(0xFF7B5CFF);

  /// Elevated surface for context menus — slightly lighter than [bg], same
  /// indigo hue.
  static const Color menuSurface = Color(0xFF1E1B2C);

  static const Color amber = Color(0xFFF59E0B);
  static const Color blue = Color(0xFF60A5FA);
  static const Color green = Color(0xFF10B981);
  static const Color red = Color(0xFFEF4444);
  static const Color purple = Color(0xFFA78BFA);

  /// Radial bloom painted behind every cloud page (same stops as the Search
  /// board's background).
  static const RadialGradient pageGradient = RadialGradient(
    center: Alignment(0, -0.75),
    radius: 1.35,
    colors: [Color(0xFF241E44), Color(0xFF161327), Color(0xFF0F0D1D), bg],
    stops: [0.0, 0.38, 0.68, 1.0],
  );
}

/// Paints the cloud-page radial bloom behind a (transparent) Scaffold, so the
/// gradient shows through the AppBar area too. Prefer [CloudScaffold], which
/// bundles the transparent Scaffold/AppBar setup this needs to work.
class CloudPageBackground extends StatelessWidget {
  final Widget child;

  const CloudPageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: CloudTheme.pageGradient),
      child: child,
    );
  }
}

/// Scaffold for cloud pages: radial bloom behind a transparent Scaffold, with
/// any [appBar] made transparent/flat via the theme — so call sites don't
/// each repeat the backgroundColor/elevation/scrolledUnderElevation set (and
/// can't forget part of it).
class CloudScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;

  const CloudScaffold({super.key, this.appBar, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CloudPageBackground(
      child: Theme(
        data: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          body: body,
        ),
      ),
    );
  }
}
