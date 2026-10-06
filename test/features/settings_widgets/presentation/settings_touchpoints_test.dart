import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import '../../../support/settings_widgets_fixture.dart';

void main() {
  testWidgets('settings URL forwards parsed URI through launcher platform', (
    tester,
  ) async {
    await settingsWidgetsCase(tester, (f) async {
      await launchSettingsUrl(
        'https://example.test/path?value=one%20two#anchor',
      );
      expect(f.launcher.urls, [
        'https://example.test/path?value=one%20two#anchor',
      ]);
      expect(f.launcher.options, hasLength(1));
      final options = f.launcher.options.single;
      expect(options.mode, PreferredLaunchMode.platformDefault);
      expect(options.webOnlyWindowName, isNull);
      expect(options.webViewConfiguration.enableJavaScript, isTrue);
      expect(options.webViewConfiguration.enableDomStorage, isTrue);
      expect(options.webViewConfiguration.headers, isEmpty);
      expect(options.browserConfiguration.showTitle, isFalse);
    });
  });
  testWidgets('legacy dialog shows full current reason autofocus OK and pops', (
    tester,
  ) async {
    await settingsWidgetsCase(tester, (f) async {
      ProfileBootstrap.legacyReason = 'Original migration reason\nFirst frame';
      await tester.pumpWidget(
        f.host(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () {
                showLegacyModeInfoDialog(ctx);
              },
              child: const Text('Legacy'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Legacy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Running in legacy mode'), findsOneWidget);
      expect(find.text(ProfileBootstrap.legacyReasonSummary), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'OK'),
      );
      expect(button.autofocus, isTrue);
      expect(Focus.of(tester.element(find.text('OK'))).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
