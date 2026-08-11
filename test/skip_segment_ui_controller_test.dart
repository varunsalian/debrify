import 'package:debrify/screens/video_player/services/skip_segment_ui_controller.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notifies only when the active skip boundary changes', () {
    const intro = SkipSegment(
      type: SkipSegmentType.intro,
      start: Duration(seconds: 10),
      end: Duration(seconds: 80),
    );
    const equivalentIntro = SkipSegment(
      type: SkipSegmentType.intro,
      start: Duration(seconds: 10),
      end: Duration(seconds: 80),
    );
    const outro = SkipSegment(
      type: SkipSegmentType.outro,
      start: Duration(minutes: 42),
      end: Duration(minutes: 44),
    );
    final controller = SkipSegmentUiController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.update(intro);
    expect(notifications, 1);

    controller.update(intro);
    controller.update(equivalentIntro);
    expect(notifications, 1);

    controller.update(outro);
    expect(notifications, 2);

    controller.clear();
    expect(notifications, 3);
    controller.clear();
    expect(notifications, 3);

    controller.dispose();
  });

  test(
    'segment lookup changes exactly at inclusive start and exclusive end',
    () {
      const intro = SkipSegment(
        type: SkipSegmentType.intro,
        start: Duration(seconds: 10),
        end: Duration(seconds: 80),
      );
      const segments = SkipSegments(intros: [intro]);

      expect(segments.segmentAt(const Duration(milliseconds: 9999)), isNull);
      expect(segments.segmentAt(const Duration(seconds: 10)), same(intro));
      expect(
        segments.segmentAt(const Duration(milliseconds: 79999)),
        same(intro),
      );
      expect(segments.segmentAt(const Duration(seconds: 80)), isNull);
    },
  );
}
