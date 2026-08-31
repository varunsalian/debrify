import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/remote/remote_pairing_dialog.dart';
import 'package:debrify/widgets/tv_text_field.dart';

void main() {
  Future<Completer<String?>> openDialog(WidgetTester tester) async {
    final result = Completer<String?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showPairingCodeEntrySheet(
                context,
                tvName: 'Living Room',
              ).then(result.complete),
              child: const Text('Pair'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('uses the TV-safe field and confirms on the sixth digit', (
    tester,
  ) async {
    final result = await openDialog(tester);

    expect(find.byType(TvTextField), findsOneWidget);
    expect(find.text('Enter the code shown on "Living Room"'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();

    expect(await result.future, '123456');
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('TV keyboard input is digit-only, bounded, and auto-confirms', (
    tester,
  ) async {
    final oldKeyboardSetting = StorageService.tvKeyboardEnabledCached;
    PlatformUtil.debugSetAndroidTvCached(true);
    StorageService.tvKeyboardEnabledCached = true;
    addTearDown(() {
      PlatformUtil.debugSetAndroidTvCached(null);
      StorageService.tvKeyboardEnabledCached = oldKeyboardSetting;
    });

    final result = await openDialog(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    tester
        .state<TvTextFieldState>(find.byType(TvTextField))
        .insertText('12a345678');
    await tester.pumpAndSettle();

    expect(await result.future, '123456');
  });
}
