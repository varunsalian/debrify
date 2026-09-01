import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/screens/video_player/services/subtitle_aligner.dart';

typedef _Span = ({int start, int end});

void main() {
  const frameMs = 32.0;

  List<_Span> speechPattern(int fromMs, int toMs, {int seed = 3}) {
    final random = math.Random(seed);
    final output = <_Span>[];
    var time = fromMs + 500;
    while (time < toMs - 1000) {
      final length = 600 + random.nextInt(1800);
      output.add((start: time, end: time + length));
      time += length + 400 + random.nextInt(2200);
    }
    return output;
  }

  AudioFeatureSegment segment(
    int anchorMs,
    int durationMs,
    List<_Span> speech, {
    List<_Span> music = const <_Span>[],
    int seed = 7,
  }) {
    const rate = 48000;
    const frameSamples = 1536;
    final count = (durationMs / frameMs).floor();
    final band = List<double>.filled(count, 0);
    final broad = List<double>.filled(count, 0);
    final random = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final time = anchorMs + (i * frameMs).floor();
      final inSpeech = speech.any(
        (span) => time >= span.start && time <= span.end,
      );
      final inMusic = music.any(
        (span) => time >= span.start && time <= span.end,
      );
      var bandValue = 0.002 + random.nextDouble() * 0.001;
      var broadValue = 0.004 + random.nextDouble() * 0.002;
      if (inMusic) {
        bandValue += 0.05 + random.nextDouble() * 0.004;
        broadValue += 0.18;
      }
      if (inSpeech) {
        final syllable = (i ~/ 6).isEven ? 1.0 : 0.25;
        bandValue += 0.12 * syllable + random.nextDouble() * 0.01;
        broadValue += 0.13 * syllable;
      }
      band[i] = bandValue;
      broad[i] = broadValue;
    }
    return AudioFeatureSegment(
      anchorMs: anchorMs,
      sampleRate: rate,
      frameSamples: frameSamples,
      band: band,
      broadband: broad,
    );
  }

  List<SubtitleCueSpan> cuesFor(
    List<_Span> speech,
    int offsetEarlierMs, {
    int seed = 11,
  }) {
    final random = math.Random(seed);
    return speech
        .map((span) {
          final jitter = random.nextInt(161) - 80;
          return SubtitleCueSpan(
            span.start - offsetEarlierMs + jitter,
            span.end - offsetEarlierMs + jitter + 250,
            'Dialogue line with a plausible length here',
          );
        })
        .toList(growable: false);
  }

  test('recovers early subtitles with the player offset sign', () {
    final speech = speechPattern(0, 8 * 60000);
    final result = SubtitleAligner.align(<AudioFeatureSegment>[
      segment(0, 8 * 60000, speech),
    ], cuesFor(speech, 3000));
    expect(result, isA<SubtitleAlignSynced>());
    expect((result as SubtitleAlignSynced).offsetMs, closeTo(3000, 150));
  });

  test('recovers late subtitles as a negative offset', () {
    final speech = speechPattern(0, 8 * 60000);
    final result = SubtitleAligner.align(<AudioFeatureSegment>[
      segment(0, 8 * 60000, speech),
    ], cuesFor(speech, -12000));
    expect(result, isA<SubtitleAlignSynced>());
    expect((result as SubtitleAlignSynced).offsetMs, closeTo(-12000, 150));
  });

  test('refuses unrelated cues instead of guessing', () {
    final speech = speechPattern(0, 8 * 60000);
    final unrelated = speechPattern(0, 8 * 60000, seed: 99);
    final result = SubtitleAligner.align(<AudioFeatureSegment>[
      segment(0, 8 * 60000, speech),
    ], cuesFor(unrelated, 0));
    expect(result, isA<SubtitleAlignNoMatch>());
  });

  test('declines too little audio before attempting a match', () {
    final speech = speechPattern(0, 20000);
    final result = SubtitleAligner.align(<AudioFeatureSegment>[
      segment(0, 20000, speech),
    ], cuesFor(speech, 2000));
    expect(result, isA<SubtitleAlignNotEnoughAudio>());
  });

  test('never reports framerate drift as a confident fixed offset', () {
    final speech = speechPattern(0, 10 * 60000);
    const scale = 23.976 / 25;
    final drifted = <SubtitleCueSpan>[
      for (final span in speech)
        SubtitleCueSpan(
          (span.start * scale).floor(),
          (span.end * scale).floor() + 250,
          'A plausible dialogue line',
        ),
    ];
    final result = SubtitleAligner.align(<AudioFeatureSegment>[
      segment(0, 10 * 60000, speech),
    ], drifted);
    expect(
      result,
      anyOf(isA<SubtitleAlignDrift>(), isA<SubtitleAlignNoMatch>()),
    );
  });

  test('survives disjoint watched spans after a seek', () {
    final speech = speechPattern(0, 20 * 60000);
    final result = SubtitleAligner.align(<AudioFeatureSegment>[
      segment(0, 3 * 60000, speech),
      segment(9 * 60000, 4 * 60000, speech),
    ], cuesFor(speech, -4000));
    expect(result, isA<SubtitleAlignSynced>());
    expect((result as SubtitleAlignSynced).offsetMs, closeTo(-4000, 150));
  });

  test('speech remains matchable with strong film music', () {
    final speech = speechPattern(0, 8 * 60000);
    const music = <_Span>[
      (start: 0, end: 90000),
      (start: 200000, end: 300000),
      (start: 380000, end: 470000),
    ];
    final result = SubtitleAligner.align(<AudioFeatureSegment>[
      segment(0, 8 * 60000, speech, music: music),
    ], cuesFor(speech, 2000));
    expect(result, isA<SubtitleAlignSynced>());
    expect((result as SubtitleAlignSynced).offsetMs, closeTo(2000, 150));
  });

  test('recent capture wins when an old end-of-film peek cannot fit', () {
    final speech = speechPattern(0, 200 * 60000);
    final result = SubtitleAligner.align(<AudioFeatureSegment>[
      segment(178 * 60000, 60000, speech),
      segment(0, 6 * 60000, speech),
    ], cuesFor(speech, 2500));
    expect(result, isA<SubtitleAlignSynced>());
    expect((result as SubtitleAlignSynced).offsetMs, closeTo(2500, 150));
  });

  test('narrow tier resolves a typical offset after thirty seconds', () {
    final speech = speechPattern(0, 30000);
    final result = SubtitleAligner.alignTiered(<AudioFeatureSegment>[
      segment(0, 30000, speech),
    ], cuesFor(speech, 2000));
    expect(result, isA<SubtitleAlignSynced>());
    expect((result as SubtitleAlignSynced).offsetMs, closeTo(2000, 150));
  });

  test('tiered alignment refuses an unseen large offset with short audio', () {
    final speech = speechPattern(0, 75000);
    final result = SubtitleAligner.alignTiered(<AudioFeatureSegment>[
      segment(0, 30000, speech),
    ], cuesFor(speech, 40000));
    expect(result, isA<SubtitleAlignNotEnoughAudio>());
  });

  test('unrelated cues are refused at every rung, scored audio included', () {
    // The narrow gate must not be a false-positive machine. A loud sustained
    // score over the first third (the DC-shift trap: sliding cues out of the
    // quiet region correlates for free) plus wrong-film cues, at every
    // ladder rung — never a confident verdict.
    for (final seconds in <int>[30, 45, 60, 90, 120, 180]) {
      for (final seed in <int>[3, 5]) {
        final speech = speechPattern(0, seconds * 1000, seed: seed);
        final unrelated = speechPattern(0, seconds * 1000, seed: seed + 40);
        final result = SubtitleAligner.alignTiered(<AudioFeatureSegment>[
          segment(
            0,
            seconds * 1000,
            speech,
            music: <_Span>[(start: 0, end: seconds * 1000 ~/ 3)],
            seed: seed + 100,
          ),
        ], cuesFor(unrelated, 0));
        expect(
          result,
          isNot(isA<SubtitleAlignSynced>()),
          reason: '${seconds}s seed $seed: $result',
        );
        expect(result, isNot(isA<SubtitleAlignDrift>()));
      }
    }
  });

  test('a true offset resolves from forty-five seconds with scored audio', () {
    for (final seed in <int>[3, 5]) {
      final speech = speechPattern(0, 45000, seed: seed);
      final result = SubtitleAligner.alignTiered(<AudioFeatureSegment>[
        segment(
          0,
          45000,
          speech,
          music: <_Span>[(start: 0, end: 15000)],
          seed: seed + 100,
        ),
      ], cuesFor(speech, 2000));
      expect(result, isA<SubtitleAlignSynced>(), reason: 'seed $seed: $result');
      expect((result as SubtitleAlignSynced).offsetMs, closeTo(2000, 300));
    }
  });

  test('a drifting file never gets a far-off plain offset from a short span', () {
    // Under two minutes the scale cannot be trusted, so nothing scaled is
    // applied — and the losing plain-offset hypothesis must never surface
    // as the −11 s garbage the old narrow gate produced. At most the
    // instantaneous offset (within a second) may be reported.
    const scale = 23.976 / 25;
    for (final seconds in <int>[45, 60, 90]) {
      for (final seed in <int>[3, 5]) {
        final speech = speechPattern(0, seconds * 1000, seed: seed);
        final drifted = <SubtitleCueSpan>[
          for (final span in speech)
            SubtitleCueSpan(
              (span.start * scale).floor() + 1500,
              (span.end * scale).floor() + 1750,
              'A plausible dialogue line',
            ),
        ];
        final result = SubtitleAligner.alignTiered(<AudioFeatureSegment>[
          segment(
            0,
            seconds * 1000,
            speech,
            music: <_Span>[(start: 0, end: seconds * 1000 ~/ 3)],
            seed: seed + 100,
          ),
        ], drifted);
        expect(result, isNot(isA<SubtitleAlignDrift>()));
        if (result is SubtitleAlignSynced) {
          expect(
            result.offsetMs.abs(),
            lessThan(1000),
            reason: '${seconds}s seed $seed: $result',
          );
        }
      }
    }
  });

  test('framerate drift is corrected once enough of the file was heard', () {
    // Cues authored for 25 fps timing on 23.976 fps audio, shifted 1.5 s:
    // display = file × (25/23.976) − 1.56 s. Three minutes is past the
    // trust span, so the verdict is a Drift carrying that transform.
    final speech = speechPattern(0, 3 * 60000);
    const scale = 23.976 / 25;
    final drifted = <SubtitleCueSpan>[
      for (final span in speech)
        SubtitleCueSpan(
          (span.start * scale).floor() + 1500,
          (span.end * scale).floor() + 1750,
          'A plausible dialogue line',
        ),
    ];
    final result = SubtitleAligner.align(<AudioFeatureSegment>[
      segment(0, 3 * 60000, speech),
    ], drifted);
    expect(result, isA<SubtitleAlignDrift>(), reason: '$result');
    final drift = result as SubtitleAlignDrift;
    expect(drift.scale, closeTo(25 / 23.976, 0.002));
    expect(drift.offsetMs, closeTo(-1564, 500));
  });

  test('local centring zeroes masked-out cells and removes a regional mean', () {
    final audio = <double>[
      for (var i = 0; i < 2000; i++) i < 1000 ? 0.2 : 0.8,
    ];
    final mask = <double>[for (var i = 0; i < 2000; i++) i == 1500 ? 0 : 1];
    final centered = SubtitleAligner.centerLocally(audio, mask);
    expect(centered[1500], 0);
    // Deep inside each region the local mean equals the level: ≈ 0.
    expect(centered[300].abs(), lessThan(1e-9));
    expect(centered[1800].abs(), lessThan(1e-9));
    // A global mean (0.5) would have left ±0.3 everywhere.
    expect(centered.every((v) => v.abs() < 0.31), isTrue);
  });

  test('filters SDH and music-only cues', () {
    final kept = SubtitleAligner.filterCues(const <SubtitleCueSpan>[
      SubtitleCueSpan(0, 1000, '[door slams]'),
      SubtitleCueSpan(0, 1000, '(distant gunfire)'),
      SubtitleCueSpan(0, 1000, '♪ ominous music ♪'),
      SubtitleCueSpan(0, 1000, '<i>[thunder]</i>'),
      SubtitleCueSpan(0, 1000, 'Actual spoken dialogue.'),
      SubtitleCueSpan(0, 1000, '<i>Whispered but real.</i>'),
    ]);
    expect(kept, hasLength(2));
  });

  test('frame duration uses exact sample counts', () {
    const feature = AudioFeatureSegment(
      anchorMs: 0,
      sampleRate: 44100,
      frameSamples: 1411,
      band: <double>[],
      broadband: <double>[],
    );
    expect(feature.frameDurationMs, closeTo(1411 * 1000 / 44100, 1e-9));
    expect((feature.frameDurationMs - 32).abs(), greaterThan(1e-4));
  });
}
