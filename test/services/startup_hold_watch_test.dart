import 'package:debrify/services/startup_hold_watch.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<(String, StartupHoldStage)> events;
  late bool current;

  StartupHoldWatch watch() => StartupHoldWatch(
    isCurrent: () => current,
    record: (event, stage, _) => events.add((event, stage)),
  );

  setUp(() {
    events = [];
    current = true;
  });

  test('a prompt release records nothing', () {
    fakeAsync((async) {
      final hold = watch();
      async.elapse(const Duration(seconds: 19));
      hold.release();
      async.elapse(const Duration(minutes: 1));
      expect(events, isEmpty);
    });
  });

  test('a held gate names the step it is stuck on, once', () {
    fakeAsync((async) {
      final hold = watch();
      hold.stage(StartupHoldStage.trackRestore);
      async.elapse(const Duration(minutes: 2));
      expect(events, [('startup_gate_held', StartupHoldStage.trackRestore)]);
      hold.release();
    });
  });

  test('a late release is recorded so slow and stuck can be told apart', () {
    fakeAsync((async) {
      final hold = watch();
      async.elapse(const Duration(seconds: 21));
      hold.stage(StartupHoldStage.resume);
      hold.release();
      hold.release();
      expect(events, [
        ('startup_gate_held', StartupHoldStage.waitVideoReady),
        ('startup_gate_released_late', StartupHoldStage.resume),
      ]);
    });
  });

  test('a screen the viewer already left records nothing', () {
    fakeAsync((async) {
      final hold = watch();
      current = false;
      async.elapse(const Duration(minutes: 1));
      hold.release();
      expect(events, isEmpty);
    });
  });
}
