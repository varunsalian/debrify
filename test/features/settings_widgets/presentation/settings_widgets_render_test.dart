import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/theme/app_surface.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/settings_widgets_fixture.dart';

void main() {
  testWidgets(
    'dropdown stale value is empty null callback returns normally and subtitle echoes',
    (tester) async {
      await settingsWidgetsCase(tester, (f) async {
        final changes = <String>[];
        const options = [
          SettingsSelectOption('a', 'Alpha', 'Alpha subtitle'),
          SettingsSelectOption('b', 'Beta', 'Beta subtitle'),
        ];
        Widget dropdown(String value) => SettingsSelectDropdown(
          options: options,
          value: value,
          onChanged: changes.add,
        );
        await tester.pumpWidget(f.host(dropdown('stale')));
        var field = tester.widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        );
        expect(field.initialValue, isNull);
        expect(() => field.onChanged!(null), returnsNormally);
        expect(changes, isEmpty);
        await tester.pumpWidget(f.host(const SizedBox.shrink()));
        await tester.pumpWidget(f.host(dropdown('a')));
        field = tester.widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        );
        expect(field.initialValue, 'a');
        expect(find.text('Alpha subtitle'), findsOneWidget);
        await tester.pumpWidget(f.host(dropdown('b')));
        final state = tester.state<FormFieldState<String>>(
          find.byType(DropdownButtonFormField<String>),
        );
        // Original SDK updates both the field value and subtitle on a parent
        // value change. Record this behavior without changing the library.
        expect(state.value, 'b');
        expect(find.text('Beta subtitle'), findsOneWidget);
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged!('b');
        expect(changes, ['b']);
      });
    },
  );
  testWidgets(
    'section rule surface keeps border dividers and blurb without fill',
    (tester) async {
      await settingsWidgetsCase(tester, (f) async {
        f.app = AppThemes.byId('console');
        expect(
          f.app.surface.modelFor(SurfaceFamily.settingsGroup),
          SeparationModel.rule,
        );
        await tester.pumpWidget(
          f.host(
            const SettingsSection(
              title: 'Rule section',
              blurb: 'Rule blurb',
              children: [Text('One'), Text('Two')],
            ),
          ),
        );
        final panels = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(SettingsSection),
                matching: find.byType(Container),
              ),
            )
            .where(
              (c) =>
                  c.decoration is BoxDecoration &&
                  c.clipBehavior == Clip.antiAlias,
            )
            .toList();
        expect(panels, hasLength(1));
        final panel = panels.single.decoration! as BoxDecoration;
        expect(panel.color, Colors.transparent);
        expect(panel.border, Border.all(color: f.app.settings.line, width: 1));
        expect(find.byType(Divider), findsOneWidget);
        expect(find.text('Rule blurb'), findsOneWidget);
      });
    },
  );
  for (final spotlight in [false, true]) {
    testWidgets(
      'section chrome banners skeleton runtime types spotlight=$spotlight',
      (tester) async {
        await settingsWidgetsCase(tester, (f) async {
          f.scrollable = true;
          await tester.pumpWidget(
            f.host(
              Column(
                children: [
                  const SettingsHeader(),
                  const SettingsPageHeader(
                    icon: Icons.home,
                    title: 'Page title',
                    subtitle: 'Page subtitle',
                  ),
                  for (final tone in SettingsBannerTone.values)
                    SettingsInfoBanner(
                      tone: tone,
                      icon: Icons.info,
                      text: 'Banner $tone',
                    ),
                  const SettingsSection(
                    title: 'Section',
                    blurb: 'Blurb',
                    children: [Text('One'), Text('Two'), Text('Three')],
                  ),
                ],
              ),
            ),
          );
          expect(find.text('Blurb'), findsOneWidget);
          expect(find.byType(Divider), findsNWidgets(2));
          expect(find.byType(SettingsInfoBanner), findsNWidgets(4));
          expect(find.byType(SettingsSectionLabel), findsOneWidget);
          f.scrollable = false;
          await tester.pumpWidget(f.host(const SettingsSkeleton()));
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_SkeletonHeader',
            ),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_SkeletonSection',
            ),
            findsNWidgets(3),
          );
          expect(
            find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_SkeletonTile',
            ),
            findsNWidgets(6),
          );
        }, spotlight: spotlight);
      },
    );
    testWidgets(
      'focused row decoration uses inverse Spotlight plate spotlight=$spotlight',
      (tester) async {
        await settingsWidgetsCase(tester, (f) async {
          final node = f.node('row');
          await tester.pumpWidget(
            f.host(
              SettingsTile(
                icon: Icons.home,
                title: 'Tile',
                subtitle: 'Subtitle',
                focusNode: node,
                onTap: () async {},
              ),
            ),
          );
          node.requestFocus();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester.widget<ParallaxFocus>(find.byType(ParallaxFocus)).focused,
            isTrue,
          );
          final decorated = tester
              .widgetList<Container>(
                find.descendant(
                  of: find.byType(SettingsTile),
                  matching: find.byType(Container),
                ),
              )
              .where((w) => w.decoration is BoxDecoration)
              .first;
          expect(
            (decorated.decoration! as BoxDecoration).color,
            spotlight ? f.app.core.tx : f.app.settings.panel2,
          );
        }, spotlight: spotlight);
      },
    );
  }
}
