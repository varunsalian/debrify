import 'dart:ui';

import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

/// TV: skip the dialog backdrop blur — the dialog panels here are fully
/// opaque, so the blur only tints the thin margin ring around them, while its
/// saveLayer costs a full-screen blur pass on weak TV GPUs.
Widget maybeBlur(Widget child, {double sigma = 12}) {
  if (PlatformUtil.isTelevision) return child;
  return BackdropFilter(
    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: child,
  );
}
