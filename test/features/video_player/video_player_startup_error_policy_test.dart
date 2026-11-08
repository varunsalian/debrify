import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/startup_driver.dart';

/// mpv reports recoverable problems on the same error stream as dead links.
/// Only an error that means the source cannot play may reject a startup
/// candidate; the rest leave the decision to decoding or the timeout.
void main() {
  for (final debrid in [false, true]) {
    final route = debrid ? 'debrid' : 'VOD';

    testWidgets('$route: no audio device does not reject a playing source', (
      t,
    ) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource(
        'no-audio',
        type: debrid ? StreamType.torrent : StreamType.directUrl,
      );
      try {
        await d.begin(d.screen(sources: [a]));
        await d.openEntered();
        d.player.emit(
          'error',
          'Could not open/initialize audio device -> no sound.',
        );
        await d.tick(const Duration(milliseconds: 200));
        expect(d.event('candidate_result'), isEmpty);
        expect(
          d.event('player_error').singleOrNull,
          contains('kind=benign label=audio_device'),
        );
        d.frame();
        await d.result();
        await d.committed();
        expect(d.event('candidate_result').single, contains('ok=true'));
        expect(d.commits, [a]);
        expect(d.player.calls.where((c) => c.$1 == 'stop'), isEmpty);
      } finally {
        await d.close();
      }
    });

    testWidgets('$route: an unrecognised error waits for real playback', (
      t,
    ) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource(
        'unknown-error',
        type: debrid ? StreamType.torrent : StreamType.directUrl,
      );
      try {
        await d.begin(d.screen(sources: [a]));
        await d.openEntered();
        d.player.emit('error', 'fixture ordinary source error');
        d.player.emit('error', 'fixture ordinary source error');
        await d.tick(const Duration(seconds: 11));
        expect(d.event('candidate_result'), isEmpty);
        expect(
          d.event('player_error').singleOrNull,
          contains('kind=unknown label=other'),
          reason: 'Each error type is recorded once per candidate',
        );
        d.frame();
        await d.result();
        await d.committed();
        expect(d.commits, [a]);
      } finally {
        await d.close();
      }
    });

    testWidgets(
      '$route: unrecognised and harmless errors still time out a dead source',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        final a = startupSource(
          'unknown-dead',
          type: debrid ? StreamType.torrent : StreamType.directUrl,
        );
        try {
          await d.begin(d.screen(sources: [a]));
          await d.openEntered();
          d.player.emit('error', 'fixture ordinary source error');
          d.player.emit(
            'error',
            'Could not open/initialize audio device -> no sound.',
          );
          await d.tick(const Duration(seconds: 13));
          await d.result();
          expect(
            d.event('candidate_result').single,
            contains('ok=false reason=timeout'),
          );
          expect(d.commits, isEmpty);
          // Diagnostics name each error type once and the rejection reason,
          // never the message text.
          final selection = d.logs.where((l) => l.startsWith('SourceSelect:'));
          expect(
            selection.where((l) => l.contains('event=candidate_player_error')),
            hasLength(2),
          );
          expect(
            selection.where(
              (l) =>
                  l.contains('event=candidate_rejected') &&
                  l.contains('reason=timeout'),
            ),
            hasLength(1),
          );
          expect(d.logs.where((l) => l.contains('fixture ordinary')), isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets('$route: a fatal open failure still rejects at once', (
      t,
    ) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource(
        'fatal-open',
        type: debrid ? StreamType.torrent : StreamType.directUrl,
      );
      try {
        await d.begin(d.screen(sources: [a]));
        await d.openEntered();
        d.player.emit('error', 'Failed to open https://fixture.invalid/a.mkv.');
        await d.result();
        expect(
          d.event('candidate_result').single,
          contains('ok=false reason=player_error'),
        );
        expect(
          d.event('player_error').single,
          contains('kind=fatal label=open_failed rejects=true'),
        );
        expect(d.commits, isEmpty);
      } finally {
        await d.close();
      }
    });
  }
}
