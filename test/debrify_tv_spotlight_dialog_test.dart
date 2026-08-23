import 'package:debrify/screens/debrify_tv/dialogs/cached_loading_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/channel_creation_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/external_player_notice_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/import_channels_dialog.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('import dialog follows a deterministic linear DPAD run', (
    tester,
  ) async {
    await _pumpImportDialog(tester, const Size(960, 540));

    expect(_hasFocus(tester, 'From storage'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_hasFocus(tester, 'From a link'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_hasFocus(tester, 'From the community'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_hasFocus(tester, 'Cancel'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_hasFocus(tester, 'From the community'), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(600, 420),
    const Size(1280, 720),
  ]) {
    testWidgets(
      'import dialog is overflow-free at ${size.width}×${size.height}',
      (tester) async {
        await _pumpImportDialog(tester, size);

        expect(find.text('Where is it coming from?'), findsOneWidget);
        expect(find.text('From storage'), findsOneWidget);
        expect(find.text('From a link'), findsOneWidget);
        expect(find.text('From the community'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('TV import dialog matches the Spotlight visual contract', (
    tester,
  ) async {
    await _pumpImportDialog(tester, const Size(960, 540));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/debrify_tv_dialog_tv.png'),
    );
  });

  testWidgets('phone import dialog matches the responsive visual contract', (
    tester,
  ) async {
    await _pumpImportDialog(tester, const Size(360, 720));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/debrify_tv_dialog_phone.png'),
    );
  });

  testWidgets('tuning dialog exposes a focused, DPAD-activatable cancel', (
    tester,
  ) async {
    var cancelled = false;
    await _pumpAtSize(
      tester,
      const Size(960, 540),
      CachedLoadingDialog(onCancel: () => cancelled = true),
    );

    expect(_hasFocus(tester, 'Cancel'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(cancelled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress and notice dialogs stay overflow-free on phone', (
    tester,
  ) async {
    await _pumpAtSize(
      tester,
      const Size(320, 568),
      ChannelCreationDialog(
        channelName: 'A deliberately long channel name for compact screens',
        countdownSeconds: 20,
        onReady: (_) {},
      ),
    );
    expect(tester.takeException(), isNull);

    await _pumpAtSize(
      tester,
      const Size(320, 568),
      const ExternalPlayerNoticeDialog(),
    );
    expect(find.text('Opening another player'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

bool _hasFocus(WidgetTester tester, String text) =>
    Focus.of(tester.element(find.text(text))).hasFocus;

Future<void> _pumpImportDialog(WidgetTester tester, Size size) async {
  await _pumpAtSize(
    tester,
    size,
    const ImportChannelsDialog(isAndroidTv: true),
  );
}

Future<void> _pumpAtSize(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme = AppThemes.byId('spotlight');
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
      builder: (context, child) => AppThemeScope(theme: theme, child: child!),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
