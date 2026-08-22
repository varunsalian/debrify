import 'package:debrify/screens/video_player/services/media_kit_audio_feature_tap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes FFmpeg decimal sample counts without compressing time', () {
    final result =
        MediaKitAudioFeatureTap.decodeMetadata(const <String, String>{
          'lavfi.astats.Overall.RMS_level': '-21.069520',
          'lavfi.astats.Overall.Number_of_samples': '4096.000000',
          'lavfi.aspectralstats.1.centroid': '1004.14',
        }, 48000);

    expect(result, isNotNull);
    expect(result!.samples, 4096);
    expect(result.broadbandRms, greaterThan(0));
    expect(result.bandRms, greaterThan(0));
  });

  test('preserves silent samples as zero-energy timeline', () {
    final result =
        MediaKitAudioFeatureTap.decodeMetadata(const <String, String>{
          'lavfi.astats.Overall.RMS_level': '-inf',
          'lavfi.astats.Overall.Number_of_samples': '2048.000000',
        }, 48000);

    expect(result, isNotNull);
    expect(result!.samples, 2048);
    expect(result.broadbandRms, 0);
    expect(result.bandRms, 0);
  });

  test('rejects malformed frames instead of inventing timing', () {
    final result = MediaKitAudioFeatureTap.decodeMetadata(
      const <String, String>{'lavfi.astats.Overall.RMS_level': '-20'},
      48000,
    );

    expect(result, isNull);
  });
}
