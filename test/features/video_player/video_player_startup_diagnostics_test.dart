import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/startup_driver.dart';

void main() {
  for (final kind in [
    'absent',
    'empty',
    'short',
    'exact64',
    'long whitespace',
  ]) {
    testWidgets(
      'P16 startup source diagnostic fields preserve $kind safe text and bounded metadata',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final raw = kind == 'empty'
            ? ''
            : kind == 'exact64'
            ? 'x' * 64
            : kind == 'long whitespace'
            ? ' A\n\t B ${'x' * 75}'
            : 'short-addon';
        final a = startupSource('metadata', addon: raw);
        try {
          await d.begin(
            d.screen(
              type: kind == 'absent' ? null : 'movie',
              sources: kind == 'absent' ? null : [a],
            ),
          );
          await d.result();
          if (kind != 'absent') await d.committed();
          await d.settle();
          final compact = raw.replaceAll(RegExp(r'\s+'), ' ');
          final safe = compact.isEmpty
              ? '-'
              : compact.length > 64
              ? compact.substring(0, 64)
              : compact;
          final sourceRaw = a.source;
          final sourceCompact = sourceRaw.replaceAll(RegExp(r'\s+'), ' ');
          final safeSource = sourceCompact.isEmpty
              ? '-'
              : sourceCompact.length > 64
              ? sourceCompact.substring(0, 64)
              : sourceCompact;
          final fields = kind == 'absent'
              ? 'sourceIndex=- type=- addon=- source=-'
              : 'sourceIndex=0 type=directUrl addon=$safe source=$safeSource';
          expect(
            d.event('candidate_open').singleOrNull,
            '[StartupFailover] event=candidate_open platform=flutter attempt=1/1 $fields aio=false timeoutMs=12000',
          );
          expect(
            d.event('candidate_result').singleOrNull,
            matches(
              RegExp(
                '^${RegExp.escape('[StartupFailover] event=candidate_result platform=flutter attempt=1/1 $fields ok=true reason=decoded_video elapsedMs=')}[0-9]+ width=1280 positionMs=80 durationMs=1200000\$',
              ),
            ),
          );
          if (kind != 'absent') {
            expect(
              d.event('begin').singleOrNull,
              '[StartupFailover] event=begin platform=flutter contentType=movie sourceCount=1 selectedIndex=0 startIndex=0 initialFailed=false tryNext=false maxAttempts=1 targetSeason=- targetEpisode=-',
            );
            expect(
              d.event('resolve').singleOrNull,
              '[StartupFailover] event=resolve platform=flutter attempt=1/1 $fields route=launch_url',
            );
            expect(
              d.event('commit').singleOrNull,
              '[StartupFailover] event=commit platform=flutter attempt=1/1 $fields playlistItems=0 playlistIndex=0',
            );
          }
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final throws in [false, true]) {
    testWidgets(
      'P16 validated binding callback ${throws ? 'failure is swallowed' : 'may be absent'} after the source log',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('callback', type: StreamType.torrent);
        if (throws) {
          d.onCommit = (_) async => throw StateError('signed callback secret');
        }
        try {
          await d.begin(d.screen(sources: [a], commitCallback: throws));
          await d.result();
          await d.settle();
          expect(d.event('commit'), hasLength(1));
          expect(
            d.logs.where((s) => s.contains('event=player_source_committed')),
            hasLength(1),
          );
          expect(
            d.event('binding_commit_failed'),
            throws
                ? [
                    '[StartupFailover] event=binding_commit_failed platform=flutter exception=StateError',
                  ]
                : isEmpty,
          );
          expect(d.commits, throws ? [a] : isEmpty);
          expect(d.player.state.playing, isTrue);
          expect(d.errors, isEmpty);
          expect(
            d.event('candidate_open').singleOrNull,
            contains('route=debrid_direct'),
          );
          expect(
            d.event('candidate_result').singleOrNull,
            contains('reason=duration_known'),
          );
          expect(
            d.event('candidate_result').singleOrNull,
            matches(RegExp(r'durationMs=1200000$')),
          );
        } finally {
          await d.close();
        }
      },
    );
  }
}
