import 'dart:async';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/settings_widgets_fixture.dart';

Finder rowInk(Type type) =>
    find.descendant(of: find.byType(type), matching: find.byType(InkWell));

void main() {
  testWidgets(
    'disabled tile cannot focus activate or hover-light and stays dim',
    (tester) async {
      await settingsWidgetsCase(tester, (f) async {
        final enabled = f.node('enabled');
        final disabled = f.node('disabled');
        final last = f.node('last');
        await tester.pumpWidget(
          f.host(
            Column(
              children: [
                SettingsTile(
                  icon: Icons.home,
                  title: 'First',
                  subtitle: '',
                  focusNode: enabled,
                  onTap: () async {},
                ),
                SettingsTile(
                  icon: Icons.lock,
                  title: 'Disabled',
                  subtitle: '',
                  focusNode: disabled,
                  enabled: false,
                  onTap: () async {
                    f.callbacks.add('disabled');
                  },
                ),
                SettingsTile(
                  icon: Icons.home,
                  title: 'Last',
                  subtitle: '',
                  focusNode: last,
                  onTap: () async {},
                ),
              ],
            ),
          ),
        );
        final ink = tester.widget<InkWell>(
          find.descendant(
            of: find.widgetWithText(SettingsTile, 'Disabled'),
            matching: find.byType(InkWell),
          ),
        );
        expect(ink.canRequestFocus, isFalse);
        expect(ink.onTap, isNull);
        expect(disabled.canRequestFocus, isFalse);
        final opacity = tester.widget<Opacity>(
          find.descendant(
            of: find.widgetWithText(SettingsTile, 'Disabled'),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacity.opacity, 0.45);
        enabled.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(last.hasFocus, isTrue);
        await tester.tap(find.text('Disabled'));
        await tester.pump();
        expect(f.callbacks, isEmpty);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Disabled')));
        await tester.pump();
        final containers = tester.widgetList<Container>(
          find.descendant(
            of: find.widgetWithText(SettingsTile, 'Disabled'),
            matching: find.byType(Container),
          ),
        );
        expect(
          (containers
                      .where((c) => c.decoration is BoxDecoration)
                      .first
                      .decoration!
                  as BoxDecoration)
              .color,
          Colors.transparent,
        );
        await mouse.removePointer();
      });
    },
  );
  for (final type in ['tile', 'toggle', 'hero']) {
    for (final borrowed in [false, true]) {
      testWidgets('$type focus ownership borrowed=$borrowed and live focus', (
        tester,
      ) async {
        await settingsWidgetsCase(tester, (f) async {
          final supplied = borrowed ? f.node('supplied') : null;
          final other = f.node('other');
          final Widget widget = switch (type) {
            'tile' => SettingsTile(
              icon: Icons.home,
              title: 'Row',
              subtitle: 'Subtitle',
              focusNode: supplied,
              onTap: () async {
                f.callbacks.add('tap');
              },
            ),
            'toggle' => SettingsToggleTile(
              icon: Icons.home,
              title: 'Row',
              subtitle: 'Subtitle',
              value: false,
              onChanged: f.changes.add,
              focusNode: supplied,
            ),
            _ => SettingsLookHero(
              label: 'Row',
              subtitle: 'Subtitle',
              focusNode: supplied,
              onTap: () async {
                f.callbacks.add('tap');
              },
            ),
          };
          await tester.pumpWidget(
            f.host(
              Column(
                children: [
                  widget,
                  TextButton(
                    focusNode: other,
                    onPressed: () {},
                    child: const Text('Other'),
                  ),
                ],
              ),
            ),
          );
          final ink = tester.widget<InkWell>(rowInk(widget.runtimeType));
          final node = ink.focusNode!;
          if (borrowed) {
            expect(node, same(supplied));
          }
          node.requestFocus();
          await tester.pump();
          expect(
            tester
                .widget<ParallaxFocus>(
                  find.descendant(
                    of: find.byType(widget.runtimeType),
                    matching: find.byType(ParallaxFocus),
                  ),
                )
                .focused,
            isTrue,
          );
          other.requestFocus();
          await tester.pump();
          expect(
            tester
                .widget<ParallaxFocus>(
                  find.descendant(
                    of: find.byType(widget.runtimeType),
                    matching: find.byType(ParallaxFocus),
                  ),
                )
                .focused,
            isFalse,
          );
          await tester.pumpWidget(f.host(const SizedBox.shrink()));
          if (borrowed) {
            expect(() => node.addListener(() {}), returnsNormally);
          } else {
            expect(() => node.addListener(() {}), throwsFlutterError);
          }
        }, spotlight: true);
      });
    }
  }
  testWidgets('toggle row is one stop and tap or OK invert the value', (
    tester,
  ) async {
    await settingsWidgetsCase(tester, (f) async {
      final node = f.node('toggle');
      final after = f.node('after');
      await tester.pumpWidget(
        f.host(
          Column(
            children: [
              SettingsToggleTile(
                icon: Icons.check,
                title: 'Toggle',
                subtitle: '',
                value: true,
                onChanged: f.changes.add,
                focusNode: node,
              ),
              TextButton(
                focusNode: after,
                onPressed: () {},
                child: const Text('After'),
              ),
            ],
          ),
        ),
      );
      final switchFinder = find.byType(Switch);
      expect(
        find.ancestor(of: switchFinder, matching: find.byType(ExcludeFocus)),
        findsOneWidget,
      );
      await tester.tap(find.text('Toggle'));
      await tester.pump();
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(f.changes, [false, false]);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(after.hasFocus, isTrue);
    });
  });
  test('spec factories retain icon title subtitles and overrides', () {
    const spec = SettingsRowContent(
      icon: Icons.home,
      title: 'Title',
      subtitle: 'Subtitle',
    );
    final tile = SettingsTile.spec(spec, onTap: () async {});
    expect(tile.icon, spec.icon);
    expect(tile.title, spec.title);
    expect(tile.subtitle, spec.subtitle);
    expect(
      SettingsTile.spec(
        spec,
        subtitle: 'Override',
        onTap: () async {},
      ).subtitle,
      'Override',
    );
    final toggle = SettingsToggleTile.spec(
      spec,
      value: true,
      onChanged: (_) {},
    );
    expect(toggle.icon, spec.icon);
    expect(toggle.title, spec.title);
    expect(toggle.subtitle, spec.subtitle);
    final info = SettingsInfoTile.spec(spec, value: 'Value');
    expect(info.icon, spec.icon);
    expect(info.title, spec.title);
    expect(info.value, 'Value');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    const key = ValueKey('spec-key');
    const trailing = Icon(Icons.star);
    Future<void> activate() async {}
    void change(bool value) {}
    final allTile = SettingsTile.spec(
      spec,
      key: key,
      onTap: activate,
      subtitle: 'Override',
      tag: 'Tag',
      trailing: trailing,
      destructive: true,
      enabled: false,
      focusNode: focus,
    );
    expect(allTile.key, same(key));
    expect(allTile.icon, spec.icon);
    expect(allTile.title, spec.title);
    expect(allTile.subtitle, 'Override');
    expect(allTile.onTap, same(activate));
    expect(allTile.tag, 'Tag');
    expect(allTile.trailing, same(trailing));
    expect(allTile.destructive, isTrue);
    expect(allTile.enabled, isFalse);
    expect(allTile.focusNode, same(focus));
    final allToggle = SettingsToggleTile.spec(
      spec,
      key: key,
      value: false,
      onChanged: change,
      focusNode: focus,
      subtitleMaxLines: 3,
    );
    expect(allToggle.key, same(key));
    expect(allToggle.icon, spec.icon);
    expect(allToggle.title, spec.title);
    expect(allToggle.subtitle, spec.subtitle);
    expect(allToggle.value, isFalse);
    expect(allToggle.onChanged, same(change));
    expect(allToggle.focusNode, same(focus));
    expect(allToggle.subtitleMaxLines, 3);
    final allInfo = SettingsInfoTile.spec(spec, key: key, value: 'Custom');
    expect(allInfo.key, same(key));
    expect(allInfo.icon, spec.icon);
    expect(allInfo.title, spec.title);
    expect(allInfo.value, 'Custom');
  });
  for (final width in [380.0, 389.0, 390.0, 420.0]) {
    testWidgets('hero swatches threshold width=$width', (tester) async {
      await settingsWidgetsCase(tester, (f) async {
        f.width = width + 40;
        await tester.pumpWidget(
          f.host(
            SettingsLookHero(
              label: 'Look',
              subtitle: 'Subtitle',
              onTap: () async {},
            ),
          ),
        );
        expect(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_SettingsSwatches',
          ),
          width >= 390 ? findsOneWidget : findsNothing,
        );
      });
    });
  }
  for (final kind in ['hero', 'tile']) {
    testWidgets('$kind awaits async tap completion', (tester) async {
      await settingsWidgetsCase(tester, (f) async {
        final gate = Completer<void>();
        try {
          final Widget row = kind == 'hero'
              ? SettingsLookHero(
                  label: 'Async',
                  subtitle: '',
                  onTap: () => gate.future,
                )
              : SettingsTile(
                  icon: Icons.home,
                  title: 'Async',
                  subtitle: '',
                  onTap: () => gate.future,
                );
          await tester.pumpWidget(f.host(row));
          final dynamic activate = tester
              .widget<InkWell>(rowInk(row.runtimeType))
              .onTap;
          final result = activate();
          expect(result, isA<Future<void>>());
          var finished = false;
          (result as Future<void>).then((_) {
            finished = true;
          });
          await tester.pump();
          expect(finished, isFalse);
          gate.complete();
          await tester.pump();
          expect(finished, isTrue);
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
        }
      });
    });
  }
}
