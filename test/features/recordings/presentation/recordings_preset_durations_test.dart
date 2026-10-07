import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';
import '../../../support/recordings_manual_driver.dart';

void main() {
  const presets = <(String, Duration)>[
    ('5 minutes (test)', Duration(minutes: 5)),
    ('30 minutes', Duration(minutes: 30)),
    ('1 hour', Duration(hours: 1)),
    ('2 hours', Duration(hours: 2)),
    ('3 hours', Duration(hours: 3)),
  ];
  for (final (label, duration) in presets) {
    testWidgets('length preset $label schedules its exact duration', (t) async {
      await recordingsCase(t, (f) async {
        await t.runAsync(f.profiles);
        await f.mount(t);
        await RecordingsManualDriver(t, f).untilLength();
        await f.tap(t, find.text(label));
        await f.until(
          t,
          () => find.text('Recording scheduled').evaluate().isNotEmpty,
        );
        final schedules = await DesktopScheduleService.instance.list();
        expect(
          schedules,
          hasLength(1),
          reason: 'one preset creates one schedule',
        );
        expect(
          schedules.single.endMs - schedules.single.startMs,
          duration.inMilliseconds,
          reason: 'preset schedules exact desktop duration: $label',
        );
      });
    });
  }
}
