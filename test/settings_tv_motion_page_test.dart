import 'package:debrify/screens/settings/tv_motion_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    TvMotionController.resetProfileScope();
    PlatformUtil.debugSetAndroidTvCached(true);
  });
  tearDown(() {
    TvMotionController.resetProfileScope();
    PlatformUtil.debugSetAndroidTvCached(null);
    ProfileRuntime.debugReset();
  });

  testWidgets(
    'DPAD selects Smooth and Snappy and writes only motion preference',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TvMotionPage()));
      await tester.pumpAndSettle();
      final rows = tester
          .widgetList<SettingsTile>(find.byType(SettingsTile))
          .toList();
      expect(rows.first.focusNode!.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(rows.last.focusNode!.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(TvMotionController.current, TvMotionProfile.smooth);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {TvMotionController.preferenceKey});
      expect(prefs.getString(TvMotionController.preferenceKey), 'smooth');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(TvMotionController.current, TvMotionProfile.snappy);
      expect(prefs.getString(TvMotionController.preferenceKey), 'snappy');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
