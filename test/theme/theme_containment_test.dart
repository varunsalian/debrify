import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/theme/app_surfaces.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

import 'golden_harness.dart' show disableRuntimeFonts;

/// Containment and live-restyle: the exit criteria the architecture pays for.
///
/// The harness mirrors the production wiring exactly — `MaterialApp.theme`
/// from the controller, the token scope installed in `builder` (above the
/// Navigator) — so what these tests prove is the wiring's contract, not a
/// synthetic one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(disableRuntimeFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppThemeController.instance.select(AppThemes.legacyId);
    AppSurfaceState.instance.reset();
  });

  tearDown(() => AppSurfaceState.instance.reset());

  Widget harness({required Widget home}) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) => MaterialApp(
        // The production observer, so the surface-signal tests exercise the
        // real route bookkeeping rather than a stub.
        navigatorObservers: [AppSurfaceRouteObserver()],
        theme: AppThemeController.instance.themeData,
        builder: (context, child) => AppThemeScope(
          theme: AppThemeController.instance.theme,
          child: child!,
        ),
        home: home,
      ),
    );
  }

  testWidgets('excluded subtree renders legacy regardless of app theme',
      (tester) async {
    await AppThemeController.instance.select('broadsheet');

    late ThemeData insideTheme;
    late AppTheme insideTokens;
    late ThemeData outsideTheme;
    late AppTheme outsideTokens;

    await tester.pumpWidget(harness(
      home: Column(
        children: [
          Builder(builder: (context) {
            outsideTheme = Theme.of(context);
            outsideTokens = AppThemeScope.of(context);
            return const SizedBox.shrink();
          }),
          LegacyThemeBoundary(
            child: Builder(builder: (context) {
              insideTheme = Theme.of(context);
              insideTokens = AppThemeScope.of(context);
              return const SizedBox.shrink();
            }),
          ),
        ],
      ),
    ));

    // Outside: broadsheet (light paper).
    expect(outsideTokens.id, 'broadsheet');
    expect(outsideTheme.brightness, Brightness.light);
    // Inside: today's app, exactly — the boundary shadows BOTH layers.
    expect(insideTokens.isLegacy, isTrue);
    expect(insideTheme.brightness, Brightness.dark);
    expect(insideTheme.colorScheme.surface, const Color(0xFF06080F));
    expect(insideTheme.colorScheme.primary, const Color(0xFF818CF8));
  });

  testWidgets('dialog launched from a frozen context captures the freeze',
      (tester) async {
    await AppThemeController.instance.select('broadsheet');

    late BuildContext frozenContext;
    await tester.pumpWidget(harness(
      home: LegacyThemeBoundary(
        child: Builder(builder: (context) {
          frozenContext = context;
          return const SizedBox.shrink();
        }),
      ),
    ));

    late ThemeData dialogTheme;
    late AppTheme dialogTokens;
    showDialog<void>(
      context: frozenContext,
      builder: (context) {
        dialogTheme = Theme.of(context);
        dialogTokens = AppThemeScope.of(context);
        return const SizedBox.shrink();
      },
    );
    await tester.pumpAndSettle();

    // showDialog captures InheritedThemes from the launching context — and
    // both Theme and AppThemeScope are InheritedThemes, so the freeze rides
    // along without any per-launcher wrapping.
    expect(dialogTokens.isLegacy, isTrue);
    expect(dialogTheme.colorScheme.surface, const Color(0xFF06080F));
  });

  testWidgets('an open route AND an open dialog restyle on theme change',
      (tester) async {
    final routeSurfaces = <Color>[];
    final dialogSurfaces = <Color>[];

    late BuildContext homeContext;
    await tester.pumpWidget(harness(
      home: Builder(builder: (context) {
        homeContext = context;
        return const SizedBox.shrink();
      }),
    ));

    // Push a route, then open a dialog over it.
    late BuildContext routeContext;
    Navigator.of(homeContext).push(MaterialPageRoute<void>(
      builder: (context) => Builder(builder: (context) {
        routeContext = context;
        routeSurfaces.add(Theme.of(context).colorScheme.surface);
        return const Scaffold(body: SizedBox.shrink());
      }),
    ));
    await tester.pumpAndSettle();

    showDialog<void>(
      context: routeContext,
      builder: (context) => Builder(builder: (context) {
        dialogSurfaces.add(Theme.of(context).colorScheme.surface);
        return const SizedBox.shrink();
      }),
    );
    await tester.pumpAndSettle();

    expect(routeSurfaces.last, const Color(0xFF06080F)); // legacy
    expect(dialogSurfaces.last, const Color(0xFF06080F));

    await AppThemeController.instance.select('broadsheet');
    await tester.pumpAndSettle();

    final broadsheetSurface =
        AppThemeController.instance.themeData.colorScheme.surface;
    expect(routeSurfaces.last, broadsheetSurface,
        reason: 'already-open route must restyle in place');
    expect(dialogSurfaces.last, broadsheetSurface,
        reason: 'already-open dialog must restyle in place — it inherits '
            'from above the Navigator, not from a capture');
  });

  testWidgets('pushExcluded route is frozen; surface signal follows the stack',
      (tester) async {
    await AppThemeController.instance.select('broadsheet');

    late BuildContext homeContext;
    await tester.pumpWidget(harness(
      home: Builder(builder: (context) {
        homeContext = context;
        return const SizedBox.shrink();
      }),
    ));

    // Leave bootstrap and land on a themed tab, as the shell does after the
    // splash — otherwise `active` is frozen regardless and every assertion
    // below would pass vacuously.
    AppSurfaceState.instance.publishBootstrap(false);
    AppSurfaceState.instance.publishTab(15); // Home — themed
    expect(AppSurfaceState.instance.active, SurfaceKind.themed,
        reason: 'root route + themed tab must read as themed');

    late AppTheme playerTokens;
    late ThemeData playerTheme;
    pushExcluded<void>(homeContext, (context) {
      playerTokens = AppThemeScope.of(context);
      playerTheme = Theme.of(context);
      return const Scaffold(body: SizedBox.shrink());
    });
    await tester.pumpAndSettle();

    expect(playerTokens.isLegacy, isTrue);
    expect(playerTheme.colorScheme.surface, const Color(0xFF06080F));
    expect(AppSurfaceState.instance.active, SurfaceKind.frozen,
        reason: 'a FrozenLegacyPageRoute on top must read as frozen');

    // A dialog over the frozen route is a PopupRoute — bookkeeping must
    // ignore it and stay frozen.
    showDialog<void>(
      context: homeContext,
      builder: (_) => const SizedBox.shrink(),
    );
    await tester.pumpAndSettle();
    expect(AppSurfaceState.instance.active, SurfaceKind.frozen,
        reason: 'a PopupRoute must not flip the surface signal');
    Navigator.of(homeContext, rootNavigator: true).pop(); // dialog
    await tester.pumpAndSettle();

    Navigator.of(homeContext).pop(); // player
    await tester.pumpAndSettle();
    expect(AppSurfaceState.instance.active, SurfaceKind.themed,
        reason: 'popping the frozen route must hand back to the themed tab');

    // A frozen TAB decides at stack root too.
    AppSurfaceState.instance.publishTab(13); // IPTV — frozen
    expect(AppSurfaceState.instance.active, SurfaceKind.frozen);
  });

  testWidgets('frozen tab body gets a boundary-local ScaffoldMessenger',
      (tester) async {
    await AppThemeController.instance.select('broadsheet');

    final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();
    late BuildContext frozenBody;

    await tester.pumpWidget(ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) => MaterialApp(
        scaffoldMessengerKey: rootMessengerKey,
        theme: AppThemeController.instance.themeData,
        builder: (context, child) => AppThemeScope(
          theme: AppThemeController.instance.theme,
          child: child!,
        ),
        home: AppSurfaces.wrapTab(
          13, // IPTV — frozen
          Scaffold(body: Builder(builder: (context) {
            frozenBody = context;
            return const SizedBox.shrink();
          })),
        ),
      ),
    ));

    final local = ScaffoldMessenger.of(frozenBody);
    expect(identical(local, rootMessengerKey.currentState), isFalse,
        reason: 'frozen surfaces must resolve a boundary-local messenger so '
            'their snackbars render inside the freeze');

    // …and under LEGACY the messenger must NOT exist: root-messenger
    // snackbars survive tab switches, a local queue's die with their
    // subtree, and that lifetime change must never ship to users who kept
    // the default theme.
    await AppThemeController.instance.select(AppThemes.legacyId);
    await tester.pumpAndSettle();
    final underLegacy = ScaffoldMessenger.of(frozenBody);
    expect(identical(underLegacy, rootMessengerKey.currentState), isTrue,
        reason: 'under legacy, frozen surfaces resolve the ROOT messenger — '
            'byte-identical behaviour to before the theme layer');
  });

  test('DetailThemeScope is an InheritedTheme (capture carries it)', () {
    // Compile-time really — but pin the upgrade so a revert to a plain
    // InheritedWidget (which InheritedTheme.capture silently SKIPS) fails.
    const scope = DetailThemeScope(
      theme: DetailThemes.signal,
      child: SizedBox.shrink(),
    );
    expect(scope, isA<InheritedTheme>());
    final appScope = AppThemeScope(
      theme: AppThemes.legacy,
      child: const SizedBox.shrink(),
    );
    expect(appScope, isA<InheritedTheme>());
  });
}
