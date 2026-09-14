import 'package:flutter/foundation.dart';

abstract final class WebDavSyncFeature {
  /// M3/M4 shipped dark; M5 completed the folder-driven activation flow.
  /// A dart-define can still disable the feature for emergency rollback.
  static const bool rolloutEnabled = bool.fromEnvironment(
    'DEBRIFY_WEBDAV_SYNC',
    defaultValue: true,
  );

  @visibleForTesting
  static bool? debugOverride;

  static bool get enabled => debugOverride ?? rolloutEnabled;
}
