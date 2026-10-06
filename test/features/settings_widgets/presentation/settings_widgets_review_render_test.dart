import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/settings_widgets_fixture.dart';

// IconTheme.of supplies black for an ordinary unspecified color. A public
// resolved palette double retains nullable color to exercise the widget's
// explicit settings.dim2 fallback, without changing production code.
class _NullableResolvedIconTheme extends IconThemeData {
  const _NullableResolvedIconTheme()
    : super(
        size: 31,
        fill: 0,
        weight: 400,
        grade: 0,
        opticalSize: 48,
        opacity: 1,
        applyTextScaling: false,
      );
  @override
  bool get isConcrete => true;
}

BoxDecoration rowDecoration(WidgetTester tester, Type type) =>
    tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(type),
                matching: find.byType(Container),
              ),
            )
            .where((c) => c.decoration is BoxDecoration)
            .first
            .decoration!
        as BoxDecoration;

void main() {
  for (final spotlight in [false, true]) {
    testWidgets('header copy styles and structure spotlight=$spotlight', (
      tester,
    ) async {
      await settingsWidgetsCase(tester, (f) async {
        await tester.pumpWidget(f.host(const SettingsHeader()));
        final texts = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(SettingsHeader),
                matching: find.byType(Text),
              ),
            )
            .toList();
        expect(
          texts.map((t) => t.data),
          spotlight
              ? [
                  'YOUR SPACE',
                  'Settings',
                  'Services, screens and playback—tuned in one place.',
                ]
              : ['Settings', 'Manage connections, search & playback'],
        );
        final column = tester.widget<Column>(
          find.descendant(
            of: find.byType(SettingsHeader),
            matching: find.byType(Column),
          ),
        );
        expect(column.crossAxisAlignment, CrossAxisAlignment.start);
        expect(
          column.children.map((w) => w.runtimeType),
          spotlight
              ? [Text, SizedBox, Text, SizedBox, Text]
              : [Text, SizedBox, Text],
        );
        expect(
          column.children.whereType<SizedBox>().map((w) => w.height),
          spotlight ? [10.0, 8.0] : [4.0],
        );
        final title = texts[spotlight ? 1 : 0];
        expect(
          title.style,
          spotlight
              ? const TextStyle(
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                )
              : const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text('Settings'),
        );
        expect(paragraph.text.style!.color, f.base.colorScheme.onSurface);
        expect(
          texts.last.style,
          spotlight
              ? TextStyle(fontSize: 12, height: 1.45, color: f.app.settings.dim)
              : TextStyle(fontSize: 13, color: f.app.settings.dim),
        );
        if (spotlight) {
          expect(
            texts.first.style,
            TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.1,
              color: f.app.settings.accent.withValues(alpha: 0.88),
            ),
          );
        }
      }, spotlight: spotlight);
    });
  }
  for (final palette in ['explicit', 'ordinary-unspecified', 'resolved-null']) {
    testWidgets('pending badge size and color palette=$palette', (
      tester,
    ) async {
      await settingsWidgetsCase(tester, (f) async {
        final IconThemeData data = switch (palette) {
          'explicit' => const IconThemeData(color: Colors.pink, size: 31),
          'resolved-null' => const _NullableResolvedIconTheme(),
          _ => const IconThemeData(size: 31),
        };
        await tester.pumpWidget(
          f.host(IconTheme(data: data, child: const WebDavSyncPendingBadge())),
        );
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.icon, Icons.chevron_right_rounded);
        expect(icon.size, 20);
        expect(tester.getSize(find.byType(Icon)), const Size(20, 20));
        expect(icon.color, switch (palette) {
          'explicit' => Colors.pink,
          'resolved-null' => f.app.settings.dim2,
          _ => Colors.black,
        });
      });
    });
  }
  testWidgets('empty section title creates no section label', (tester) async {
    await settingsWidgetsCase(tester, (f) async {
      await tester.pumpWidget(
        f.host(
          const SettingsSection(
            title: '',
            blurb: 'Empty title blurb',
            children: [Text('Content')],
          ),
        ),
      );
      expect(find.byType(SettingsSectionLabel), findsNothing);
      expect(find.text('Empty title blurb'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
    });
  });
  for (final spotlight in [false, true]) {
    for (final kind in ['card', 'tile', 'toggle', 'hero']) {
      testWidgets('$kind hover differs from focus spotlight=$spotlight', (
        tester,
      ) async {
        await settingsWidgetsCase(tester, (f) async {
          final node = f.node('row');
          final other = f.node('other');
          final Widget row = switch (kind) {
            'card' => ConnectionCard(info: f.info('Row'), focusNode: node),
            'tile' => SettingsTile(
              icon: Icons.home,
              title: 'Row',
              subtitle: '',
              focusNode: node,
              onTap: () async {},
            ),
            'toggle' => SettingsToggleTile(
              icon: Icons.home,
              title: 'Row',
              subtitle: '',
              focusNode: node,
              value: false,
              onChanged: (_) {},
            ),
            _ => SettingsLookHero(
              label: 'Row',
              subtitle: '',
              focusNode: node,
              onTap: () async {},
            ),
          };
          await tester.pumpWidget(
            f.host(
              Column(
                children: [
                  row,
                  TextButton(
                    focusNode: other,
                    onPressed: () {},
                    child: const Text('Other'),
                  ),
                ],
              ),
            ),
          );
          other.requestFocus();
          await tester.pump();
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          try {
            await mouse.addPointer(location: const Offset(1279, 999));
            await mouse.moveTo(tester.getCenter(find.byType(row.runtimeType)));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(node.hasFocus, isFalse);
            expect(
              tester.widget<ParallaxFocus>(find.byType(ParallaxFocus)).focused,
              isFalse,
            );
            final hover = rowDecoration(tester, row.runtimeType);
            final inverse = spotlight;
            final t = f.app.settings;
            expect(
              hover.color,
              inverse
                  ? f.app.core.tx
                  : kind == 'hero'
                  ? Color.alphaBlend(
                      t.accent.withValues(alpha: 0.1),
                      f.app.fade(f.app.core.tx, 0.04),
                    )
                  : t.panel2,
            );
            expect(
              (hover.border! as Border).top.color,
              inverse
                  ? f.app.core.tx
                  : kind == 'card'
                  ? t.line
                  : kind == 'hero'
                  ? t.accent.withValues(alpha: 0.24)
                  : Colors.transparent,
            );
            expect(hover.boxShadow, isNull);
            await mouse.moveTo(const Offset(1279, 999));
            await tester.pump();
            node.requestFocus();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(node.hasFocus, isTrue);
            expect(
              tester.widget<ParallaxFocus>(find.byType(ParallaxFocus)).focused,
              isTrue,
            );
            final focus = rowDecoration(tester, row.runtimeType);
            expect(focus.color, hover.color);
            expect(
              (focus.border! as Border).top.color,
              inverse
                  ? f.app.core.tx
                  : kind == 'hero'
                  ? t.accent.withValues(alpha: 0.24)
                  : t.accent,
            );
            expect(
              focus.boxShadow,
              kind == 'card' && !inverse
                  ? [
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : isNull,
            );
          } finally {
            await mouse.removePointer();
          }
        }, spotlight: spotlight);
      });
    }
  }
}
