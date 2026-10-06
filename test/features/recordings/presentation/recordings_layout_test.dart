import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';

void main() {
  testWidgets('empty DVR keeps schedule action and hides list sections', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await f.mount(t);
      expect(find.text('Your DVR is empty'), findsOneWidget);
      expect(find.text('Schedule a recording'), findsOneWidget);
      expect(find.text('LIBRARY'), findsNothing);
      expect(find.text('SCHEDULED'), findsNothing);
    });
  });

  testWidgets('populated layout keeps section order counts and folder action', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await f.seedSchedules([f.schedule('one')]);
      await t.runAsync(() => f.file('Library.ts'));
      await f.mount(t);
      expect(
        t.getTopLeft(find.text('SCHEDULED')).dy,
        lessThan(t.getTopLeft(find.text('LIBRARY')).dy),
      );
      expect(find.text('1 UPCOMING'), findsOneWidget);
      expect(find.text('1 · 1 KB'), findsOneWidget);
      expect(find.byTooltip('Show in folder'), findsOneWidget);
      expect(find.text('Your DVR is empty'), findsNothing);
    });
  });
}
