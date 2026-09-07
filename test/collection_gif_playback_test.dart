import 'package:debrify/screens/settings/collections_settings_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/services/collection_gif_settings.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/widgets/collections/collection_focus_art.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  test('platform defaults and separate preference keys', () async {
    expect(
      CollectionGifMode.parse(null, touch: true),
      CollectionGifMode.visible,
    );
    expect(
      CollectionGifMode.parse(null, touch: false),
      CollectionGifMode.focused,
    );
    expect(
      CollectionGifMode.parse('invalid', touch: true),
      CollectionGifMode.visible,
    );
    expect(
      CollectionGifSettings.keyFor(true),
      isNot(CollectionGifSettings.keyFor(false)),
    );
    await CollectionGifSettings.write(CollectionGifMode.off);
    expect(await CollectionGifSettings.read(), CollectionGifMode.off);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(
        CollectionGifSettings.keyFor(!CollectionGifSettings.isTouch),
      ),
      isNull,
    );
  });

  Future<void> mount(
    WidgetTester tester, {
    bool focused = false,
    bool hidden = false,
    bool reduced = false,
    String? video,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: Offstage(
              offstage: hidden,
              child: SizedBox(
                width: 100,
                height: 100,
                child: CollectionFocusArt(
                  gifUrl: 'https://example.com/folder.gif',
                  videoUrl: video,
                  focused: focused,
                  applyGifPreference: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('automatic GIFs require visibility and pause in background', (
    tester,
  ) async {
    await CollectionGifSettings.write(CollectionGifMode.visible);
    await mount(tester);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    await mount(tester, hidden: true);
    expect(find.byType(CachedNetworkImage, skipOffstage: false), findsNothing);
    await mount(tester);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    await mount(tester, reduced: true);
    expect(find.byType(CachedNetworkImage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('focus mode and live Off setting suppress GIFs', (tester) async {
    await CollectionGifSettings.write(CollectionGifMode.focused);
    await mount(tester);
    expect(find.byType(CachedNetworkImage), findsNothing);
    await mount(tester, focused: true);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    await CollectionGifSettings.write(CollectionGifMode.off);
    MainPageBridge.notifyHomeSettingsChanged();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('settings shows one GIF dropdown and saves its selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: const CollectionsSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dropdown = find.byType(SettingsSelectDropdown);
    expect(dropdown, findsOneWidget);
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(await CollectionGifSettings.read(), CollectionGifMode.off);
    expect(find.byType(SettingsSelectDropdown), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('automatic GIF mode never starts an unfocused video', (
    tester,
  ) async {
    await CollectionGifSettings.write(CollectionGifMode.visible);
    await mount(tester, video: 'https://example.com/video.mp4');
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byType(HeroTrailerBackdrop), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
