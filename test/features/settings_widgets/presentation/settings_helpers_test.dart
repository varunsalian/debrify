import 'package:debrify/models/tv_render_quality.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initials preserve separators internal capitals and empty fallback', () {
    for (final entry in {
      'Real Debrid': 'RD',
      'Jackett & Prowlarr': 'JP',
      'AllDebrid': 'AD',
      'PikPak': 'PP',
      'Torbox': 'TO',
      'a': 'A',
      '': '?',
      ' & ': '?',
    }.entries) {
      expect(settingsInitialsFor(entry.key), entry.value, reason: entry.key);
    }
  });
  test(
    'connection predicates characterize every negative keyword and readiness',
    () {
      for (final status in [
        'Inactive',
        'EXPIRED',
        'Error contacting server',
        'Failed',
        'Needs attention',
        'Active',
        'Configured',
        'Unknown',
      ]) {
        for (final connected in [false, true]) {
          final info = ConnectionInfo(
            title: 'Provider',
            connected: connected,
            status: status,
            caption: '',
            onTap: () async {},
          );
          final negative = [
            'Inactive',
            'EXPIRED',
            'Error contacting server',
            'Failed',
            'Needs attention',
          ].contains(status);
          expect(
            settingsConnectionNeedsAttention(info),
            connected && negative,
            reason: '$status/$connected',
          );
          expect(settingsConnectionIsReady(info), connected && !negative);
        }
      }
    },
  );
  test(
    'TV choices preserve order labels subtitles completeness and size fallback',
    () {
      expect(kTvUiScaleChoices.map((c) => c.percent), [100, 90, 80]);
      expect(kTvUiScaleChoices.map((c) => c.title), [
        'Large',
        'Medium',
        'Compact',
      ]);
      expect(kTvUiScaleChoices.map((c) => c.subtitle), [
        'The original size — everything bigger',
        'Default — about 10% more fits on screen',
        'About 25% more fits on screen',
      ]);
      expect(
        [for (final c in kTvUiScaleChoices) tvUiScaleLabel(c.percent)],
        ['Large (100%)', 'Medium (90%)', 'Compact (80%)'],
      );
      expect(tvUiScaleLabel(77), '77%');
      expect(
        kTvRenderQualityChoices.map((c) => c.quality),
        TvRenderQuality.values,
      );
      expect(kTvRenderQualityChoices.map((c) => c.label), [
        'Automatic',
        'Sharper picture',
        'Smoother navigation',
      ]);
      expect(
        [
          for (final c in kTvRenderQualityChoices)
            tvRenderQualityLabel(c.quality),
        ],
        ['Automatic', 'Sharper picture', 'Smoother navigation'],
      );
      expect(kTvRenderQualityChoices.map((c) => c.subtitle), [
        "Default — Debrify picks based on this TV's graphics",
        "Draw at the panel's full resolution",
        'Draw at about 720p so scrolling stays fluid — text and art look softer',
      ]);
    },
  );
}
