import 'package:debrify/screens/profiles/profile_recovery_screen.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

  testWidgets('TV recovery gives initial focus to the preserving action', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileRecoveryScreen(
          forceTvSafeInput: true,
          onRecovered: () async {},
          onResetComplete: () async {},
        ),
      ),
    );
    await tester.pump();

    final restoreFinder = find.widgetWithText(FilledButton, 'Restore a backup');
    final restore = tester.widget<FilledButton>(restoreFinder);
    final recoveryAdmin = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Continue with a new Recovery Admin'),
    );
    expect(restore.autofocus, isTrue);
    expect(recoveryAdmin.autofocus, isFalse);
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    expect(focusedWidget, isNotNull);
    expect(
      find.ancestor(of: find.byWidget(focusedWidget!), matching: restoreFinder),
      findsOneWidget,
    );
  });
}
