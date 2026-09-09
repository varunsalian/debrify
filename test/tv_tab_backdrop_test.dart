import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/app_tab_switcher.dart';
import 'package:debrify/widgets/tv_ambient_art_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TabPage extends StatefulWidget {
  const _TabPage({required this.id, required this.disposed});

  final String id;
  final List<String> disposed;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> {
  final node = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.id.startsWith('home')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          MainPageBridge.tvAmbientArt.value =
              'https://example.invalid/${widget.id}.jpg';
        }
      });
    }
  }

  @override
  void dispose() {
    widget.disposed.add(widget.id);
    if (widget.id.startsWith('home')) {
      // Match Home's tree-lock-safe cleanup. A retained outgoing page would
      // run this AFTER the replacement Home has published its new artwork.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MainPageBridge.tvAmbientArt.value = null;
      });
    }
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    child: SizedBox.expand(child: Text(widget.id)),
  );
}

Widget _app(Widget child) => MaterialApp(
  home: AppThemeScope(theme: AppThemes.legacy, child: child),
);

Finder _tabWidgets(Type type) => find.descendant(
  of: find.byType(AppTabSwitcher),
  matching: find.byType(type),
);

void main() {
  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
    MainPageBridge.tvAmbientArt.value = null;
    MainPageBridge.tvHeroTint.value = null;
  });

  testWidgets('Android tab switch paints and retains only the incoming page', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    final disposed = <String>[];
    Widget page(int index, String id, double entrance) => _app(
      AppTabSwitcher(
        selectedIndex: index,
        isTelevision: true,
        entranceAnimation: AlwaysStoppedAnimation(entrance),
        child: _TabPage(id: id, disposed: disposed),
      ),
    );
    await tester.pumpWidget(page(15, 'home-1', 1));
    await tester.pumpWidget(page(6, 'settings', 0));

    expect(disposed, ['home-1']);
    expect(find.text('home-1'), findsNothing);
    expect(find.text('settings'), findsOneWidget);
    expect(_tabWidgets(FadeTransition), findsOneWidget);
    expect(_tabWidgets(SlideTransition), findsNothing);
    await tester.pump(const Duration(milliseconds: 75));
    final opacity = tester
        .widget<FadeTransition>(_tabWidgets(FadeTransition))
        .opacity
        .value;
    expect(opacity, closeTo(0.5, 0.01));
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      tester.widget<FadeTransition>(_tabWidgets(FadeTransition)).opacity.value,
      1,
    );
    // The old 300ms shell entrance animation is still zero, but cannot make
    // the selected Android TV page transparent anymore.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid Android switches cannot clear the replacement Home art', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    final disposed = <String>[];
    Widget page(int index, String id) => _app(
      Stack(
        fit: StackFit.expand,
        children: [
          TvAmbientArtStage(homeActive: index == 15),
          AppTabSwitcher(
            selectedIndex: index,
            isTelevision: true,
            entranceAnimation: const AlwaysStoppedAnimation(0),
            child: _TabPage(id: id, disposed: disposed),
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(15, 'home-1'));
    await tester.pump();
    await tester.pumpWidget(page(6, 'settings'));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(disposed, ['home-1']);
    await tester.pumpWidget(page(17, 'search'));
    expect(find.byType(CachedNetworkImage), findsNothing);
    await tester.pumpWidget(page(15, 'home-2'));
    await tester.pump();
    expect(MainPageBridge.tvAmbientArt.value, endsWith('/home-2.jpg'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(MainPageBridge.tvAmbientArt.value, endsWith('/home-2.jpg'));
    expect(find.byType(_TabPage), findsOneWidget);
    expect(disposed, ['home-1', 'settings', 'search']);
    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .imageUrl,
      endsWith('/home-2.jpg'),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('off Home Android removes even an in-flight backdrop crossfade', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    MainPageBridge.tvAmbientArt.value = 'https://example.invalid/one.jpg';
    await tester.pumpWidget(_app(const TvAmbientArtStage()));
    MainPageBridge.tvAmbientArt.value = 'https://example.invalid/two.jpg';
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(_app(const TvAmbientArtStage(homeActive: false)));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    // A late publisher must not light another tab, even before cleanup runs.
    MainPageBridge.tvAmbientArt.value = 'https://example.invalid/late.jpg';
    MainPageBridge.tvHeroTint.value = Colors.red;
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(TvAmbientArtStage),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      AppThemes.legacy.shell.ink,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home still crossfades between its own artwork', (tester) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    MainPageBridge.tvAmbientArt.value = 'https://example.invalid/one.jpg';
    await tester.pumpWidget(_app(const TvAmbientArtStage()));
    MainPageBridge.tvAmbientArt.value = 'https://example.invalid/two.jpg';
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
    expect(
      tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
      const Duration(milliseconds: 220),
    );
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('same Android tab rebuild preserves state and focus', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    final disposed = <String>[];
    Widget page(double entrance) => _app(
      AppTabSwitcher(
        selectedIndex: 6,
        isTelevision: true,
        entranceAnimation: AlwaysStoppedAnimation(entrance),
        child: _TabPage(id: 'settings', disposed: disposed),
      ),
    );
    await tester.pumpWidget(page(1));
    final state = tester.state<_TabPageState>(find.byType(_TabPage));
    state.node.requestFocus();
    await tester.pump();
    await tester.pumpWidget(page(0));
    expect(tester.state(find.byType(_TabPage)), same(state));
    expect(state.node.hasFocus, isTrue);
    expect(disposed, isEmpty);
    expect(
      tester.widget<FadeTransition>(_tabWidgets(FadeTransition)).opacity.value,
      1,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final television in [true, false]) {
    testWidgets('legacy transitions unchanged (tvOS=$television)', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(false);
      PlatformUtil.debugSetTvOS(television);
      final disposed = <String>[];
      const entrance = AlwaysStoppedAnimation(0.25);
      Widget page(int index) => _app(
        AppTabSwitcher(
          selectedIndex: index,
          isTelevision: television,
          entranceAnimation: entrance,
          child: _TabPage(id: 'tab-$index', disposed: disposed),
        ),
      );
      await tester.pumpWidget(page(6));
      await tester.pumpWidget(page(17));
      expect(find.byType(_TabPage), findsNWidgets(2));
      expect(disposed, isEmpty);
      expect(_tabWidgets(FadeTransition), findsNWidgets(3));
      expect(
        tester
            .widgetList<FadeTransition>(_tabWidgets(FadeTransition))
            .where((fade) => identical(fade.opacity, entrance)),
        hasLength(1),
      );
      expect(
        _tabWidgets(SlideTransition),
        television ? findsNothing : findsNWidgets(2),
      );
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration(milliseconds: television ? 150 : 350),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(disposed, ['tab-6']);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tvOS shell backdrop behavior remains unchanged', (tester) async {
    PlatformUtil.debugSetAndroidTvCached(false);
    PlatformUtil.debugSetTvOS(true);
    MainPageBridge.tvAmbientArt.value = 'https://example.invalid/apple-tv.jpg';
    await tester.pumpWidget(_app(const TvAmbientArtStage(homeActive: false)));
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
