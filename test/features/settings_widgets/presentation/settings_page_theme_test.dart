import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/settings_widgets_fixture.dart';

class _DialogFromPage extends StatefulWidget {
  const _DialogFromPage();
  @override
  State<_DialogFromPage> createState() => _DialogFromPageState();
}

class _DialogFromPageState extends State<_DialogFromPage> {
  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: 'Page',
    body: TextButton(
      onPressed: () {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(
              Theme.of(context).colorScheme.primary.toARGB32().toString(),
              key: const ValueKey('dialog-color'),
            ),
          ),
        );
      },
      child: const Text('Dialog from State'),
    ),
  );
}

void main() {
  testWidgets('page theme memo keys identical base and app independently', (
    tester,
  ) async {
    await settingsWidgetsCase(tester, (f) async {
      final themes = <ThemeData>[];
      final bases = <ThemeData>[];
      Widget probe() => Builder(
        builder: (ctx) {
          bases.add(Theme.of(ctx));
          final a = settingsPageTheme(ctx);
          expect(settingsPageTheme(ctx), same(a));
          themes.add(a);
          return const SizedBox.shrink();
        },
      );
      await tester.pumpWidget(f.host(probe()));
      await tester.pump();
      final original = themes.last;
      await tester.pumpWidget(f.host(probe()));
      await tester.pump();
      expect(themes.last, same(original));
      final previousBase = bases.last;
      f.app = AppThemes.byId('spotlight');
      await tester.pumpWidget(f.host(probe()));
      await tester.pump();
      expect(bases.last, same(previousBase));
      expect(themes.last, isNot(same(original)));
      expect(themes.last.colorScheme.primary, f.app.settings.accent2);
      final spotlight = themes.last;
      f.base = f.base.copyWith(
        colorScheme: f.base.colorScheme.copyWith(onSurface: Colors.amber),
      );
      await tester.pumpWidget(f.host(probe()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(themes.last, isNot(same(spotlight)));
      expect(themes.last.colorScheme.onSurface, Colors.amber);
    });
  });
  testWidgets(
    'push themes route State context so its dialog inherits palette',
    (tester) async {
      await settingsWidgetsCase(tester, (f) async {
        await tester.pumpWidget(
          f.host(
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () {
                  pushSettingsPage<void>(ctx, const _DialogFromPage());
                },
                child: const Text('Push'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Push'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Dialog from State'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final text = tester.widget<Text>(
          find.byKey(const ValueKey('dialog-color')),
        );
        expect(text.data, f.app.settings.accent2.toARGB32().toString());
      });
    },
  );
  for (final dismissible in [false, true]) {
    testWidgets(
      'settings dialog scopes palette barrierDismissible=$dismissible',
      (tester) async {
        await settingsWidgetsCase(tester, (f) async {
          await tester.pumpWidget(
            f.host(
              Builder(
                builder: (ctx) => TextButton(
                  onPressed: () {
                    showSettingsDialog<void>(
                      context: ctx,
                      barrierDismissible: dismissible,
                      builder: (ctx) => AlertDialog(
                        title: Text(
                          Theme.of(
                            ctx,
                          ).colorScheme.primary.toARGB32().toString(),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.text(f.app.settings.accent2.toARGB32().toString()),
            findsOneWidget,
          );
          final barrier = tester.widget<ModalBarrier>(
            find.byType(ModalBarrier).last,
          );
          expect(barrier.dismissible, dismissible);
          await tester.tapAt(const Offset(4, 4));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.byType(AlertDialog),
            dismissible ? findsNothing : findsOneWidget,
          );
        });
      },
    );
  }
}
