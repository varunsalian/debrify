// A TV user couldn't reach "Review full transfer": RadioGroup binds every arrow
// key to choosing the next radio, so focus never left the options.

import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/remote/remote_transfer_all.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _mount(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: RemoteTransferAll(onBack: () {})),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

/// Test storage fails the inventory, which leaves one radio with its Try again
/// button above it: enough to show whether focus can leave the radios.
FocusNode _focusOption(WidgetTester tester) {
  final option = Focus.of(
    tester.element(find.text('Current profile’s setup only')),
  )..requestFocus();
  return option;
}

void main() {
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

  testWidgets('on TV, UP leaves the options for the rest of the page', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    await _mount(tester);
    final option = _focusOption(tester);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, option);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, isNot(option));
  });

  testWidgets('off TV the arrows stay with the radio group', (tester) async {
    PlatformUtil.debugSetAndroidTvCached(false);
    await _mount(tester);
    final option = _focusOption(tester);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, option);
  });
}
