import 'dart:io';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/settings_widgets_fixture.dart';

const captureLinux = bool.fromEnvironment(
  'SETTINGS_WIDGETS_CAPTURE_ORIGINAL_LINUX',
);
const requireLinux = bool.fromEnvironment(
  'SETTINGS_WIDGETS_REQUIRE_ORIGINAL_LINUX',
);
const order = String.fromEnvironment('SETTINGS_WIDGETS_GOLDEN_ORDER');

void main() {
  const scenes = [
    'tv_legacy_gallery',
    'tv_spotlight_gallery',
    'wide_connections',
    'phone_connections',
    'phone_skeleton',
  ];
  for (final scene in order == 'reverse' ? scenes.reversed : scenes) {
    final platform = Platform.isLinux ? 'linux' : 'macos';
    final path = 'test/goldens/settings_widgets/$platform/$scene.png';
    testWidgets(
      'original pixel golden $scene',
      (tester) async {
        final size = switch (scene) {
          'tv_legacy_gallery' ||
          'tv_spotlight_gallery' => const Size(1920, 1080),
          'wide_connections' => const Size(1280, 900),
          'phone_connections' => const Size(390, 1000),
          _ => const Size(390, 844),
        };
        await settingsWidgetsCase(
          tester,
          (f) async {
            PlatformUtil.debugSetAndroidTvCached(
              scene.startsWith('tv_') || scene == 'wide_connections',
            );
            final promised = <Finder>[];
            FocusNode? focus;
            Widget child;
            if (scene.endsWith('_gallery')) {
              f.width = 1000;
              focus = f.node('golden-focused-tile');
              child = SettingsBackground(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SettingsPageHeader(
                        key: ValueKey('header'),
                        icon: Icons.settings,
                        title: 'Settings vocabulary',
                        subtitle: 'Original settings widgets',
                      ),
                      const SizedBox(height: 16),
                      for (final tone in SettingsBannerTone.values) ...[
                        SettingsInfoBanner(
                          key: ValueKey('banner-$tone'),
                          tone: tone,
                          text: 'Original ${tone.name} banner',
                        ),
                        const SizedBox(height: 8),
                      ],
                      SettingsLookHero(
                        key: const ValueKey('hero'),
                        label: scene == 'tv_spotlight_gallery'
                            ? 'Spotlight'
                            : 'Legacy',
                        subtitle: 'Active appearance',
                        onTap: () async {},
                      ),
                      const SizedBox(height: 16),
                      SettingsSection(
                        title: 'Options',
                        blurb: 'Original rows and controls',
                        children: [
                          SettingsTile(
                            key: const ValueKey('tile'),
                            icon: Icons.home,
                            title: 'Focused tile',
                            subtitle: 'A single cursor',
                            focusNode: focus,
                            onTap: () async {},
                          ),
                          SettingsToggleTile(
                            key: const ValueKey('toggle'),
                            icon: Icons.check,
                            title: 'Toggle',
                            subtitle: 'One focus stop',
                            value: true,
                            onChanged: (_) {},
                          ),
                          const SettingsInfoTile(
                            key: ValueKey('info'),
                            icon: Icons.info,
                            title: 'Version',
                            value: 'Original',
                          ),
                          SettingsTile(
                            key: const ValueKey('disabled'),
                            icon: Icons.lock,
                            title: 'Disabled tile',
                            subtitle: 'Unavailable',
                            enabled: false,
                            onTap: () async {},
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SettingsSelectDropdown(
                        key: const ValueKey('dropdown'),
                        options: const [
                          SettingsSelectOption(
                            'a',
                            'Selected option',
                            'Selected subtitle',
                          ),
                          SettingsSelectOption('b', 'Other option'),
                        ],
                        value: 'a',
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              );
              promised.addAll([
                find.byKey(const ValueKey('header')),
                find.byType(SettingsSection),
                for (final tone in SettingsBannerTone.values)
                  find.byKey(ValueKey('banner-$tone')),
                for (final key in [
                  'hero',
                  'tile',
                  'toggle',
                  'info',
                  'disabled',
                  'dropdown',
                ])
                  find.byKey(ValueKey(key)),
                find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_SettingsSwatches',
                ),
              ]);
            } else if (scene.endsWith('_connections')) {
              final wide = scene == 'wide_connections';
              f.width = wide ? 1100 : 390;
              focus = f.node('golden-first-card');
              child = f.summary(media: wide, mdblist: wide, first: focus);
              for (final title in [
                'Real Debrid',
                'TorBox',
                'Premiumize',
                'AllDebrid',
                'PikPak',
                'WebDAV',
                'Indexers',
                'IPTV',
                'Policy',
                'Trakt',
                'Simkl',
                if (wide) 'Media servers',
                if (wide) 'MDBList',
              ]) {
                promised.add(
                  find.byWidgetPredicate(
                    (w) => w is ConnectionCard && w.info.title == title,
                  ),
                );
              }
            } else {
              child = const SettingsSkeleton();
              promised.add(
                find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_SkeletonHeader',
                ),
              );
            }
            await tester.pumpWidget(f.host(child));
            await tester.pump();
            focus?.requestFocus();
            await tester.pump();
            await tester.pump(
              Duration(milliseconds: scene == 'phone_skeleton' ? 400 : 300),
            );
            if (scene == 'phone_skeleton') {
              final sections = find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_SkeletonSection',
              );
              expect(sections, findsNWidgets(3));
              for (var i = 0; i < 3; i++) {
                promised.add(sections.at(i));
              }
            }
            final bounds = Offset.zero & size;
            for (final finder in promised) {
              expect(finder, findsOneWidget);
              expect(
                tester.getRect(finder).overlaps(bounds),
                isTrue,
                reason: '$scene promised widget outside capture',
              );
            }
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byKey(settingsWidgetsCapture),
              matchesGoldenFile(
                '../../../goldens/settings_widgets/$platform/$scene.png',
              ),
            );
          },
          size: size,
          spotlight: scene == 'tv_spotlight_gallery',
        );
      },
      skip:
          Platform.isLinux &&
          !captureLinux &&
          !requireLinux &&
          !File(path).existsSync(),
    );
  }
}
