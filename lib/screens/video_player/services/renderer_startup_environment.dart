import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Renderer preference/error-recovery decision only, not a device override.
abstract final class RendererStartupEnvironment {
  @visibleForTesting
  static bool? debugIsAndroid;

  static bool get isAndroid => debugIsAndroid ?? Platform.isAndroid;
}
