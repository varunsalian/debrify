import 'package:flutter/material.dart';

import '../services/tv_motion_profile.dart';

/// Captured by routes and overlays alongside the app theme.
class TvMotionScope extends InheritedTheme {
  const TvMotionScope({super.key, required this.profile, required super.child});

  final TvMotionProfile profile;

  static TvMotionProfile of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvMotionScope>()?.profile ??
      TvMotionController.current;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      TvMotionScope(profile: profile, child: child);

  @override
  bool updateShouldNotify(TvMotionScope oldWidget) =>
      profile != oldWidget.profile;
}

/// Lives above the Navigator and ProfileGate. The gate only rekeys its own
/// child, so this root must subscribe to profile warmers as well as selection.
class TvMotionRoot extends StatefulWidget {
  const TvMotionRoot({super.key, required this.child});

  final Widget child;

  @override
  State<TvMotionRoot> createState() => _TvMotionRootState();
}

class _TvMotionRootState extends State<TvMotionRoot> {
  @override
  void initState() {
    super.initState();
    TvMotionController.notifier.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    TvMotionController.notifier.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TvMotionScope(profile: TvMotionController.current, child: widget.child);
}
