import 'package:debrify/services/player_display_controls.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/subtitle_apply_driver.dart';

final _wakeDrain = Object();
const _notice =
    'Couldn’t apply subtitles. Try another embedded or online track.';

/// The log listener's failure classification during a live apply attempt:
/// error/fatal level and a subtitle prefix or decoder/converter text.
void main() {
  for (final (prefix, level, text, fails) in [
    ('sub', 'fatal', 'bad packet', true),
    ('SUB/ass', 'error', 'bad packet', true),
    ('ffmpeg', 'error', 'Subtitle Decoder failed', true),
    ('ffmpeg', 'error', 'subtitle converter failed', true),
    ('sub', 'warn', 'subtitle decoder failed', false),
    ('demux', 'error', 'track switch failed', false),
    ('cplayer', 'fatal', 'out of memory', false),
  ]) {
    testWidgets(
      'P20 a $level "$prefix: $text" log during an apply ${fails ? 'rolls it back' : 'is not a subtitle failure'}',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        try {
          await d.mount();
          final panel = await d.menu();
          expect(await d.select('2', panel: panel), isTrue);
          d.fail(prefix: prefix, level: level, reason: text);
          if (fails) {
            await d.rollback('1');
          } else {
            await d.f.advance(t, const Duration(milliseconds: 300));
            await d.f.actions.settle(t);
          }
          expect(d.player.state.track.subtitle.id, fails ? '1' : '2');
          expect(find.text(_notice), fails ? findsOneWidget : findsNothing);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
          // As EngineDriver.close: leave the shared wakelock queue cursor in
          // the real zone so later cases in this isolate do not stall.
          await t.runAsync(
            () => PlayerDisplayControls.instance.setWakelockOwner(
              _wakeDrain,
              false,
            ),
          );
        }
      },
    );
  }
}
