import 'package:media_kit/media_kit.dart' as mk;
import '../models/vp_subtitle_apply_attempt.dart';

String vpDiagnosticSubtitleId(mk.SubtitleTrack track) =>
    track.uri || track.data ? '<external>' : track.id;

bool vpSubtitlePreferenceMatchesAttempt(
  String subtitle,
  VpSubtitleApplyAttempt attempt,
) {
  if (attempt.requested.id == 'no') return subtitle == 'no';
  if (attempt.requested.uri || attempt.requested.data) {
    return subtitle.startsWith('stremio:');
  }
  return subtitle == attempt.requested.id;
}
