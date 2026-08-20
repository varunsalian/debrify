import 'package:debrify/screens/settings/settings_spotlight_shell.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _categories = [
  SettingsCategoryDefinition(
    icon: Icons.link_rounded,
    label: 'Connections',
    subtitle: 'Services and storage',
    eyebrow: 'Connections',
    title: 'Services, all in one place.',
    description: 'See what is ready before opening a provider.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.history_rounded,
    label: 'Trackers',
    subtitle: 'History and watchlists',
    eyebrow: 'Trackers',
    title: 'Keep your watch history moving.',
    description: 'Connect the services that remember what you watch.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.home_rounded,
    label: 'Home & Display',
    subtitle: 'Navigation and home',
    eyebrow: 'Home & Display',
    title: 'Shape the way in.',
    description: 'Choose how home and navigation meet your screen.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.auto_awesome_rounded,
    label: 'Appearance',
    subtitle: 'Look and layout',
    eyebrow: 'Appearance',
    title: 'Make it feel like yours.',
    description: 'Choose a Look, then tune only what matters.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.play_circle_outline_rounded,
    label: 'Playback',
    subtitle: 'Player and quick play',
    eyebrow: 'Playback',
    title: 'Set the handoff to play.',
    description: 'Tune player, torrent, and quick-play behavior.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.search_rounded,
    label: 'Search',
    subtitle: 'Filters and sources',
    eyebrow: 'Search',
    title: 'Make every result count.',
    description: 'Control filters, providers, and search engines.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.live_tv_rounded,
    label: 'Live TV & DVR',
    subtitle: 'Channels and recordings',
    eyebrow: 'Live TV & DVR',
    title: 'Keep live viewing close.',
    description: 'Manage channels, recordings, and Debrify TV.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.devices_rounded,
    label: 'Devices',
    subtitle: 'Remote control',
    eyebrow: 'Devices',
    title: 'Let your screens work together.',
    description: 'Pair a remote or send setup to another device.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.inventory_2_outlined,
    label: 'Data & Backup',
    subtitle: 'Storage and restore',
    eyebrow: 'Data & Backup',
    title: 'Keep your setup portable.',
    description: 'Clean local data or create a restorable backup.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.info_outline_rounded,
    label: 'About',
    subtitle: 'Version and community',
    eyebrow: 'About',
    title: 'Updates and community.',
    description: 'Check your build or find the people behind Debrify.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.warning_amber_rounded,
    label: 'Danger Zone',
    subtitle: 'Reset Debrify',
    eyebrow: 'Danger Zone',
    title: 'Start over, deliberately.',
    description: 'Destructive actions stay isolated.',
    destructive: true,
  ),
];

Widget _categoryBody(int index) {
  if (index == 3) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsLookHero(
          label: 'Spotlight',
          subtitle: 'Full-bleed art, borderless focus, and ambient detail.',
          onTap: _noop,
        ),
        const SizedBox(height: 18),
        SettingsSection(
          title: 'Presets',
          blurb: 'One pick sets theme, layouts, and launch motion together.',
          children: [
            SettingsTile(
              icon: Icons.tune_rounded,
              title: 'Advanced',
              subtitle: 'Spotlight defaults',
              onTap: _noop,
            ),
          ],
        ),
        const SizedBox(height: 18),
        SettingsSection(
          title: 'Theme',
          blurb: 'Colour, focus, and motion. Applies everywhere.',
          children: [
            SettingsTile(
              icon: Icons.light_mode_rounded,
              title: 'Text Brightness',
              subtitle: 'Bright',
              onTap: _noop,
            ),
            SettingsTile(
              icon: Icons.animation_rounded,
              title: 'Launch Animation',
              subtitle: 'Horizon',
              onTap: _noop,
            ),
          ],
        ),
      ],
    );
  }
  return SettingsSection(
    title: '',
    children: [
      SettingsTile(
        icon: _categories[index].icon,
        title: '${_categories[index].label} row',
        subtitle: 'Fixture destination',
        onTap: _noop,
      ),
    ],
  );
}

Future<void> _noop() async {}

Future<void> _pumpShell(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme = AppThemes.byId('spotlight');
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
      builder: (context, child) => AppThemeScope(
        theme: theme,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: SettingsSpotlightShell(
          categories: _categories,
          onOpenSearch: () {},
          compactSummary: SettingsSpotlightSummaryCard(
            eyebrow: 'Service health',
            title: 'Everything looks ready.',
            subtitle: 'Two services are configured.',
            actionLabel: 'Manage connections',
            tone: SettingsSummaryTone.good,
            onTap: () {},
          ),
          categoryBuilder: (context, index) => _categoryBody(index),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('connection health accepts configured and flags degraded states', () {
    ConnectionInfo info(String status, {bool connected = true}) =>
        ConnectionInfo(
          title: 'Fixture',
          connected: connected,
          status: status,
          caption: '',
          onTap: _noop,
        );

    expect(settingsConnectionIsReady(info('Active')), isTrue);
    expect(settingsConnectionIsReady(info('Configured')), isTrue);
    expect(settingsConnectionNeedsAttention(info('Inactive')), isTrue);
    expect(settingsConnectionNeedsAttention(info('Premium expired')), isTrue);
    expect(
      settingsConnectionNeedsAttention(info('Not connected', connected: false)),
      isFalse,
    );
  });

  test('breakpoints keep narrow tablets out of a cramped split pane', () {
    expect(settingsSurfaceClassForWidth(390), SettingsSurfaceClass.compact);
    expect(settingsSurfaceClassForWidth(719), SettingsSurfaceClass.compact);
    expect(settingsSurfaceClassForWidth(720), SettingsSurfaceClass.medium);
    expect(settingsSurfaceClassForWidth(1079), SettingsSurfaceClass.medium);
    expect(settingsSurfaceClassForWidth(1080), SettingsSurfaceClass.expanded);
  });

  testWidgets('phone root opens a category and system back restores the root', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(390, 844));

    expect(find.byKey(const Key('settings-compact-root')), findsOneWidget);
    expect(find.text('Everything looks ready.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('settings-category-3')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-compact-detail')), findsOneWidget);
    expect(find.text('Make it feel like yours.'), findsOneWidget);
    expect(find.text('Spotlight'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-compact-root')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app-shell back restores phone settings before leaving its tab', (
    tester,
  ) async {
    addTearDown(() => MainPageBridge.setActiveTab(null));
    MainPageBridge.setActiveTab('settings');
    await _pumpShell(tester, const Size(390, 844));

    await tester.tap(find.byKey(const ValueKey<String>('settings-category-3')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-compact-detail')), findsOneWidget);
    expect(MainPageBridge.handleBackNavigation(), isTrue);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-compact-root')), findsOneWidget);
    expect(MainPageBridge.handleBackNavigation(), isFalse);
  });

  testWidgets('320dp phone uses one-column cards without overflow', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(320, 700));

    expect(find.byKey(const Key('settings-compact-root')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape phone remains a scrollable compact dashboard', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(667, 375));

    expect(find.byKey(const Key('settings-compact-root')), findsOneWidget);
    expect(find.byKey(const Key('settings-wide-shell')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone remains usable with 200 percent text', (tester) async {
    await _pumpShell(tester, const Size(320, 700), textScale: 2);

    final appearance = find.byKey(
      const ValueKey<String>('settings-category-3'),
    );
    await tester.scrollUntilVisible(
      appearance,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(appearance);
    await tester.pumpAndSettle();
    await tester.tap(appearance);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-compact-detail')), findsOneWidget);
    expect(find.text('Make it feel like yours.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary compact actions retain accessible touch targets', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(390, 844));

    final searchInk = find.ancestor(
      of: find.text('Search settings'),
      matching: find.byType(InkWell),
    );
    final firstCategoryInk = find.descendant(
      of: find.byKey(const ValueKey<String>('settings-category-0')),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(searchInk).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(firstCategoryInk).height, greaterThanOrEqualTo(44));
  });

  testWidgets('tablet and desktop keep the rail and selected pane together', (
    tester,
  ) async {
    for (final size in [const Size(800, 900), const Size(1280, 800)]) {
      await _pumpShell(tester, size);

      expect(find.byKey(const Key('settings-wide-shell')), findsOneWidget);
      expect(find.byKey(const Key('settings-compact-root')), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('settings-rail-3')));
      await tester.pumpAndSettle();

      expect(find.text('Make it feel like yours.'), findsOneWidget);
      expect(find.text('Spotlight'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('phone Spotlight settings visual', (tester) async {
    await _pumpShell(tester, const Size(390, 844));
    await expectLater(
      find.byType(SettingsSpotlightShell),
      matchesGoldenFile('goldens/settings_spotlight_phone.png'),
    );
  });

  testWidgets('phone Spotlight appearance visual', (tester) async {
    await _pumpShell(tester, const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey<String>('settings-category-3')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SettingsSpotlightShell),
      matchesGoldenFile('goldens/settings_spotlight_phone_appearance.png'),
    );
  });

  testWidgets('tablet Spotlight appearance visual', (tester) async {
    await _pumpShell(tester, const Size(800, 900));
    await tester.tap(find.byKey(const ValueKey<String>('settings-rail-3')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SettingsSpotlightShell),
      matchesGoldenFile('goldens/settings_spotlight_tablet.png'),
    );
  });

  testWidgets('desktop Spotlight appearance visual', (tester) async {
    await _pumpShell(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const ValueKey<String>('settings-rail-3')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SettingsSpotlightShell),
      matchesGoldenFile('goldens/settings_spotlight_desktop.png'),
    );
  });
}
