import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/iptv_settings_page.dart';
import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:debrify/screens/settings/iptv_style_page.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    PlatformUtil.debugSetAndroidTvCached(false);
    PlatformUtil.debugSetTvOS(null);
    StorageService.resetProfileCaches();
  });

  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
    ProfileRuntime.debugReset();
  });

  test(
    'default and profile reset use Spotlight without saving a choice',
    () async {
      expect(StorageService.iptvStyleCached, 'spotlight');
      expect(await StorageService.getIptvStyle(), 'spotlight');
      expect(
        (await SharedPreferences.getInstance()).containsKey('iptv_style'),
        isFalse,
      );
      for (final style in ['command', 'edition', 'console', 'spotlight']) {
        await StorageService.setIptvStyle(style);
        StorageService.resetProfileCaches();
        expect(StorageService.iptvStyleCached, 'spotlight');
        expect(await StorageService.getIptvStyle(), style);
      }
    },
  );

  test(
    'Spotlight IPTV style persists and unknown values remain safe',
    () async {
      final write = StorageService.setIptvStyle('spotlight');
      expect(StorageService.iptvStyleCached, 'spotlight');
      await write;
      expect(await StorageService.getIptvStyle(), 'spotlight');

      await StorageService.setIptvStyle('future-style');
      expect(await StorageService.getIptvStyle(), 'spotlight');

      SharedPreferences.setMockInitialValues(const <String, Object>{
        'iptv_style': 'future-style',
      });
      StorageService.resetProfileCaches();
      expect(await StorageService.getIptvStyle(), 'spotlight');
    },
  );

  test('sanitized profiles accept all four IPTV styles only', () {
    bool accepts(Object? value) =>
        SanitizedProfilePreferences.allowsEntry('iptv_style', value);

    for (final value in const ['command', 'edition', 'console', 'spotlight']) {
      expect(accepts(value), isTrue, reason: value);
    }
    expect(accepts('future-style'), isFalse);
    expect(accepts(4), isFalse);
  });

  test('settings metadata exposes Spotlight Guide consistently', () {
    expect(
      kIptvStyleChoices.map((choice) => choice.value),
      orderedEquals(const ['command', 'edition', 'console', 'spotlight']),
    );
    final spotlight = kIptvStyleChoices.last;
    expect(spotlight.label, 'Spotlight Guide');
    expect(spotlight.subtitle, contains('Apple TV'));
    expect(iptvStyleLabel('spotlight'), 'Spotlight Guide');
    expect(iptvStyleLabel('unknown'), 'Spotlight Guide');
  });

  test('appearance is available only on televisions and desktop', () {
    expect(
      IptvSettingsPage.showsAppearance(isTelevision: true, isDesktop: false),
      isTrue,
    );
    expect(
      IptvSettingsPage.showsAppearance(isTelevision: false, isDesktop: true),
      isTrue,
    );
    expect(
      IptvSettingsPage.showsAppearance(isTelevision: false, isDesktop: false),
      isFalse,
    );
  });

  testWidgets('standalone picker selects Spotlight on Apple TV', (
    tester,
  ) async {
    PlatformUtil.debugSetTvOS(true);
    await _mount(tester, const IptvStylePage());
    await tester.pumpAndSettle();

    expect(find.text('Spotlight Guide'), findsOneWidget);
    await tester.tap(find.text('Spotlight Guide'));
    await tester.pumpAndSettle();

    expect(await StorageService.getIptvStyle(), 'spotlight');
    expect(tester.takeException(), isNull);
  });

  testWidgets('two-pane Appearance uses the shared fourth choice', (
    tester,
  ) async {
    final methodNodes = List<FocusNode>.generate(3, (_) => FocusNode());
    addTearDown(() {
      for (final node in methodNodes) {
        node.dispose();
      }
    });
    String? selected;

    await _mount(
      tester,
      IptvSettingsTwoPane(
        playlists: const <IptvPlaylist>[],
        defaultPlaylistId: null,
        refreshingIds: const <String>{},
        customLists: const <IptvListMeta>[],
        startupEnabled: false,
        startupMode: 'last',
        startupChannelLabel: 'Not set',
        lastLiveChannelLabel: 'None',
        hasStartupChannel: false,
        hasLastLiveChannel: false,
        addMethod: 0,
        onAddMethodChanged: (_) {},
        urlFormBuilder: (_) => const SizedBox.shrink(),
        fileFormBuilder: (_) => const SizedBox.shrink(),
        xtreamFormBuilder: (_) => const SizedBox.shrink(),
        urlMethodFocusNode: methodNodes[0],
        fileMethodFocusNode: methodNodes[1],
        xtreamMethodFocusNode: methodNodes[2],
        onSetDefault: (_) {},
        onRefresh: (_) {},
        onEdit: (_) {},
        onDelete: (_) {},
        onCreateList: () {},
        onManageChannelOrder: () {},
        onFocusFirstFormField: () {},
        onListActions: (_) {},
        onToggleStartup: (_) {},
        onStartupModeChanged: (_) {},
        onPickStartupChannel: () {},
        channelPreviewEnabled: true,
        onToggleChannelPreview: (_) {},
        trackContinueWatching: true,
        onToggleTrackContinueWatching: (_) {},
        showAppearanceSection: true,
        iptvStyle: 'spotlight',
        onIptvStyleChanged: (value) => selected = value,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spotlight Guide'), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Spotlight Guide'), findsNWidgets(2));
    await tester.tap(find.text('Spotlight Guide').last);
    expect(selected, 'spotlight');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: AppThemeScope(
      theme: AppThemes.byId('spotlight'),
      child: Scaffold(body: child),
    ),
  ),
);
