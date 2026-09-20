import 'package:debrify/screens/profiles/profile_recovery_screen.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
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

  testWidgets('unavailable vault exposes only explicit reset recovery', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileRecoveryScreen(
          forceTvSafeInput: true,
          deviceVaultFailure: DeviceVaultFailure.missing,
          onRecovered: () async {},
          onResetComplete: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Restore a backup'), findsNothing);
    expect(find.text('Continue with a new Recovery Admin'), findsNothing);
    final resetFinder = find.widgetWithText(
      TextButton,
      'Erase private data and reconnect',
    );
    expect(resetFinder, findsOneWidget);
    expect(tester.widget<TextButton>(resetFinder).autofocus, isTrue);
    expect(find.textContaining('secure device vault'), findsOneWidget);
  });

  testWidgets('transient vault failure never offers destructive recovery', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileRecoveryScreen(
          forceTvSafeInput: true,
          deviceVaultFailure: DeviceVaultFailure.unavailable,
          onRecovered: () async {},
          onResetComplete: () async => closed = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('Erase private'), findsNothing);
    expect(find.text('Restore a backup'), findsNothing);
    final close = find.widgetWithText(FilledButton, 'Close Debrify');
    expect(close, findsOneWidget);
    await tester.tap(close);
    await tester.pump();
    expect(closed, isTrue);
  });
}
