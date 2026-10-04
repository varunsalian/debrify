import 'package:debrify/services/live_recording_service.dart';

class IptvSettingsRecordingOwner {
  // Recording engine + scheduled recordings. The section exists where SOME
  // recorder can run: Android 10+ (engine + toggle) or desktop (in-app
  // scheduler, no toggle). On iOS/pre-Q the page must not promise recording
  // that native methods will just refuse.
  bool recordingSectionVisible = false;
  bool engineToggleVisible = false;
  bool recordingEngineOn = true;
  int scheduledCount = 0;
  int maxConcurrent = LiveRecordingService.maxConcurrentDefault;

  /// Null while unknown / non-Android; battery exemption drives the row's
  /// label so users can see at a glance whether long recordings are safe.
  bool? batteryExempt;

  /// The exemption dialog is a separate activity: the request call returns
  /// the moment it LAUNCHES, so reading state right after it sees the old
  /// value. The truth arrives when this app resumes.
  bool recheckBatteryOnResume = false;
}
