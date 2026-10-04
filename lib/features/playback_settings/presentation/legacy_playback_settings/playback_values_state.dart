import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/screens/video_player/services/network_tuning.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';

class PlaybackValuesState {
  // Debrify Player default settings
  bool isAndroidTv = false;

  int defaultAspectIndex = 2; // Fit Width (mobile) / Fill (TV)

  int nightModeIndex = 0; // Off

  bool systemAudioEffects = false; // Android only, opt-in

  bool tvosForceSoftwareDecode = false; // Apple TV only, opt-in

  bool audioPassthrough = false; // Android only, opt-in

  bool appleMultichannel = false; // tvOS/iOS only, opt-in

  bool tvosForceStereo = false; // tvOS diagnostics

  bool tvosLegacyAudioOutput = false; // tvOS diagnostics

  AndroidVideoRendererMode androidVideoRendererMode =
      AndroidVideoRendererMode.automatic;

  ContentDisplayMatchMode contentDisplayMatchMode =
      ContentDisplayMatchMode.systemDefault;

  bool startPortrait = false; // Phone only, opt-in

  int movieCompletionThreshold =
      LocalCompletionStorage.defaultLocalCompletionThreshold;

  int episodeCompletionThreshold =
      LocalCompletionStorage.defaultLocalCompletionThreshold;

  bool skipSegmentsEnabled = true;

  String skipSegmentProvider = SkipSegmentProviders.auto;

  String netPatience = NetworkTuning.standard;

  String netBuffer = NetworkTuning.standard;

  String iptvDecoderMode = 'auto';
}
