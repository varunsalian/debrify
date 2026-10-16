import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/video_player_environment.dart';
import 'support/resume_driver.dart';

void main() {
  const cases = <(String, int, double?, double?, double?, int)>[
    ('explicit Trakt wins over deeper local', 900000, 20, null, null, 240000),
    (
      'explicit remote at exact low boundary falls through to local',
      350000,
      1 / 6,
      null,
      null,
      350000,
    ),
    (
      'fractional tracker promise remains seekable',
      900000,
      0.5,
      null,
      null,
      6000,
    ),
    ('explicit MDBList wins over deeper local', 900000, null, 25, null, 300000),
    ('explicit Simkl wins over deeper local', 900000, null, null, 30, 360000),
    ('remote fold selects MDBList maximum', 100000, 20, 50, 40, 600000),
    ('remote fold selects Simkl maximum', 100000, 20, 40, 50, 600000),
    ('equal tracker percentages retain target', 100000, 30, 30, 30, 360000),
    (
      'zero tracker percent falls through to local',
      350000,
      0,
      null,
      null,
      350000,
    ),
    (
      '100 percent tracker falls through to local',
      350000,
      100,
      null,
      null,
      350000,
    ),
    (
      'remote at 90 percent falls through to local',
      350000,
      90,
      null,
      null,
      350000,
    ),
    ('local at exact low boundary starts fresh', 2000, null, null, null, 0),
    ('local above low boundary resumes', 2001, null, null, null, 2001),
    (
      'local immediately below high boundary resumes',
      1079999,
      null,
      null,
      null,
      1079999,
    ),
    ('local at high boundary starts fresh', 1080000, null, null, null, 0),
    (
      'explicit remote revives a locally completed legacy row',
      1100000,
      40,
      null,
      null,
      480000,
    ),
  ];
  for (final (label, local, trakt, mdblist, simkl, expected) in cases) {
    testWidgets('Resume P14 arbitration $label', (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final diagnostics = ResumeVerifierDriver(t, f)..captureLogs();
      const url = 'https://player.test/p14-arbitration.mp4';
      try {
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(url, {
            'positionMs': local,
            'durationMs': 1200000,
            'speed': 1.0,
            'aspect': 'contain',
          }),
        );
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: url,
            title: 'Resume arbitration',
            contentType: 'series',
            contentImdbId: 'tt1410000',
            contentSeason: 2,
            contentEpisode: 3,
            traktProgressPercent: trakt,
            mdblistProgressPercent: mdblist,
            simklProgressPercent: simkl,
          ),
        );
        await f.actions.settle(t);
        final seeks = f.player.calls
            .where((c) => c.$1 == 'seek')
            .map((c) => (c.$2 as Duration).inMilliseconds);
        expect(seeks, expected == 0 ? isEmpty : [expected]);
        final providers = [trakt, mdblist, simkl].whereType<double>();
        final remote = providers.isEmpty
            ? null
            : providers.reduce((a, b) => a > b ? a : b);
        final remoteMs = remote != null && remote > 0 && remote < 100
            ? (1200000 * remote / 100).floor()
            : 0;
        if (expected > 0) {
          expect(
            diagnostics.logs,
            contains(
              remoteMs > 2000 && remoteMs < 1080000
                  ? 'Resume: explicit tracker percent -> ${expected}ms'
                  : 'Resume: furthest of remote=${remoteMs}ms local=${local}ms -> ${expected}ms',
            ),
          );
        } else {
          expect(
            diagnostics.logs.where(
              (v) =>
                  v.startsWith('Resume: explicit tracker percent') ||
                  v.startsWith('Resume: furthest of'),
            ),
            isEmpty,
          );
        }
        expect(
          f.player.calls.where((c) => c.$1 == 'rate'),
          isEmpty,
          reason: 'A stored 1.0 preference must skip setRate',
        );
      } finally {
        diagnostics.restoreLogs();
        await f.close(t);
      }
    });
  }
}
