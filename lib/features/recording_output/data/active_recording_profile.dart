import 'package:debrify/services/profiles/profile_runtime.dart';

/// The profile whose share settings are in force: the committed profile, or
/// the single legacy owner on installs without profiles.
String activeRecordingProfileId() => ProfileRuntime.isProfileCommitted
    ? ProfileRuntime.capture().profileId
    : 'legacy-admin-v1';
