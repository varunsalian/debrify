import 'package:debrify/features/sources/models/source_provider_option.dart';
import 'package:debrify/features/sources/presentation/source_provider_strip.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final keyboard in [false, true]) {
    testWidgets(
      'provider and retry dispatch remain distinct: keyboard=$keyboard',
      (tester) async {
        final events = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: Scaffold(
                body: SourceProviderStrip(
                  options: const [
                    SourceProviderOption(
                      key: 'empty',
                      label: 'Retry source',
                      retryable: true,
                      failed: true,
                      retrying: true,
                    ),
                    SourceProviderOption(key: 'ready', label: 'Ready source'),
                  ],
                  showAll: true,
                  selectedKey: 'ready',
                  onSelect: (key) => events.add('select:$key'),
                  onRetry: (key) => events.add('retry:$key'),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
          ['All', 'Retry source', 'Ready source'],
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byKey(const ValueKey('source-pill-ready')), findsOneWidget);
        for (final label in ['All', 'Ready source', 'Retry source']) {
          if (keyboard) {
            Focus.of(tester.element(find.text(label))).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          } else {
            await tester.tap(find.text(label));
          }
          await tester.pump();
        }
        expect(events, ['select:null', 'select:ready', 'retry:empty']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
