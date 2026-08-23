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

  String record(int frame, double ptsTime, {int samples = 1536}) =>
      'frame:$frame  pts:${(ptsTime * 48000).round()}   pts_time:$ptsTime\n'
      'lavfi.astats.Overall.RMS_level=-24.5\n'
      'lavfi.astats.Overall.Number_of_samples=$samples.000000\n'
      'lavfi.aspectralstats.1.centroid=1500.0\n';

  test('parses ametadata print output split across arbitrary chunks', () {
    final tap = MediaKitAudioFeatureTap.forTesting(currentPositionMs: () => 0);
    final text = record(0, 10.0) + record(1, 10.032) + record(2, 10.064);
    // Feed in chunks that split lines mid-way; a record only lands once the
    // NEXT header proves it complete, so 3 headers → 2 ingested frames.
    for (var i = 0; i < text.length; i += 37) {
      tap.ingestPrintOutput(
        text.substring(i, (i + 37).clamp(0, text.length)),
      );
    }
    expect(tap.anchoredDurationMs, closeTo(64, 0.001));
    final segments = tap.snapshot();
    expect(segments, hasLength(1));
    expect(segments.single.anchorMs, 10000);
  });

  test('a pts jump re-anchors instead of stretching the segment', () {
    final tap = MediaKitAudioFeatureTap.forTesting(currentPositionMs: () => 0);
    tap.ingestPrintOutput(
      record(0, 0.0) +
          record(1, 0.032) +
          record(2, 0.064) +
          // Seek: pts leaps far beyond the accumulated duration.
          record(3, 300.0) +
          record(4, 300.032) +
          record(5, 300.064) +
          record(6, 300.096),
    );
    final segments = tap.snapshot();
    expect(segments, hasLength(2));
    expect(segments.first.anchorMs, 0);
    expect(segments.last.anchorMs, 300000);
  });

  test('a lossy record stream fragments below the aligner usability floor',
      () {
    final tap = MediaKitAudioFeatureTap.forTesting(currentPositionMs: () => 0);
    // Every other 32ms frame is missing: accumulated duration falls behind
    // real pts by 32ms per surviving record until the drift gate re-anchors.
    final buffer = StringBuffer();
    for (var i = 0; i < 400; i += 2) {
      buffer.write(record(i, i * 0.032));
    }
    tap.ingestPrintOutput(buffer.toString());
    final segments = tap.snapshot();
    expect(segments.length, greaterThan(10));
    for (final segment in segments) {
      expect(segment.durationMs, lessThan(2000));
    }
  });

  test('property fallback flags itself unreliable at half-rate accrual', () {
    final tap = MediaKitAudioFeatureTap.forTesting(
      currentPositionMs: () => 0,
      fileMode: false,
    );
    var position = 0;
    tap.observePosition(position);
    // 40s of witnessed playback, but only every other frame delivered.
    var deliver = true;
    for (var t = 0; t < 40000; t += 32) {
      if (deliver) {
        tap.ingestMetadata(const <String, String>{
          'lavfi.astats.Overall.RMS_level': '-24.5',
          'lavfi.astats.Overall.Number_of_samples': '1536.000000',
        });
      }
      deliver = !deliver;
      if (t % 512 == 0) {
        position = t;
        tap.observePosition(position);
      }
    }
    tap.observePosition(40000);
    expect(tap.reliable, isFalse);
  });

  test('file mode ignores write-buffer latency in reliability accounting', () {
    // Field case: FFmpeg's buffered writer had flushed only 26.3s of records
    // after 32.9s of playback — latency, not loss. File mode must never read
    // that as unreliable; pts fragmentation is its loss protection.
    final tap = MediaKitAudioFeatureTap.forTesting(currentPositionMs: () => 0);
    final buffer = StringBuffer();
    for (var i = 0; i < 820; i++) {
      buffer.write(record(i, i * 0.032)); // ~26.2s of contiguous records
    }
    tap.ingestPrintOutput(buffer.toString());
    for (var t = 0; t <= 33000; t += 500) {
      tap.observePosition(t);
    }
    expect(tap.reliable, isTrue);
    expect(tap.anchoredDurationMs, greaterThan(25000));
  });

  test('property fallback stays reliable at full-rate accrual', () {
    final tap = MediaKitAudioFeatureTap.forTesting(
      currentPositionMs: () => 0,
      fileMode: false,
    );
    var position = 0;
    tap.observePosition(position);
    for (var t = 0; t < 40000; t += 32) {
      tap.ingestMetadata(const <String, String>{
        'lavfi.astats.Overall.RMS_level': '-24.5',
        'lavfi.astats.Overall.Number_of_samples': '1536.000000',
      });
      if (t % 512 == 0) {
        position = t;
        tap.observePosition(position);
      }
    }
    tap.observePosition(40000);
    expect(tap.reliable, isTrue);
  });
}
