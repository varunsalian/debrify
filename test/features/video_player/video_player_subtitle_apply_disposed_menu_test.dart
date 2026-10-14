import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/subtitle_apply_driver.dart';

void main() {
  for (final corrected in [false, true]) {
    testWidgets(
      'subtitle saved menu callback after disposal ${corrected ? 'throws while clearing the corrected notifier' : 'continues a previously null correction through native apply and persistence'} as-is',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        try {
          await d.mount();
          final panel = await d.menu();
          if (corrected) {
            expect(await d.select('2', panel: panel), isTrue);
            d.fail();
            await d.rollback('1');
          }
          await t.pumpWidget(const SizedBox());
          await d.f.until(t, () => d.player.disposed.isCompleted);
          d.player.calls.clear();
          final action = panel.onEmbeddedSubtitleSelected('3', '1');
          if (corrected) {
            await expectLater(
              d.f.finish(t, action),
              throwsA(
                isA<FlutterError>().having(
                  (e) => e.toString(),
                  'disposed correction',
                  contains('used after being disposed'),
                ),
              ),
            );
            expect(d.player.calls.where((v) => v.$1 == 'subtitle'), isEmpty);
            expect((await d.saved())?['subtitleTrackId'], isNull);
          } else {
            expect(await d.f.finish(t, action), isTrue);
            expect(d.player.state.track.subtitle.id, '3');
            expect((await d.saved())?['subtitleTrackId'], '3');
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
