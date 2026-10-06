import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/alldebrid_files_fixture.dart';

void main() {
  setUp(() {
    PlatformUtil.debugSetAndroidTvCached(true);
    TvDisplayStorage.tvKeyboardEnabledCached = false;
  });
  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    TvDisplayStorage.tvKeyboardEnabledCached = true;
  });

  testWidgets(
    'review live web notification clears the retained root search controller',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t, query: ' Library ');
      final controller = t
          .widget<TextField>(find.byType(TextField))
          .controller!;
      expect(controller.text, 'Library');
      MainPageBridge.notifyAllDebridFocusWebDownloads();
      await f.until(
        t,
        () => f.requests.length == 2 && f.member('loadingLinks') == false,
      );
      expect(f.member('searchActive'), isFalse);
      expect(f.member('searchQuery'), '');
      expect(
        controller.text,
        '',
        reason:
            'The live handler clears controller text as well as query state',
      );
      await f.tap(t, find.byTooltip('Search links'));
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller, same(controller));
      expect(field.controller!.text, '');
      expect(f.log, [adList(), adLinks()]);
    }),
  );

  testWidgets(
    'review TV content focus inside a magnet keeps Back focused and defers row focus',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.open(t);
      await f.search(t, 'S01', file: true);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(f.focus('backButtonFocusNode').hasFocus, isTrue);
      expect(f.focus('firstItemFocusNode').hasFocus, isFalse);
      expect(MainPageBridge.requestTvContentFocus(), isTrue);
      await t.pump();
      await t.pump();
      expect(f.member('isAtRoot'), isFalse);
      expect(f.focus('backButtonFocusNode').hasFocus, isTrue);
      expect(f.focus('firstItemFocusNode').hasFocus, isFalse);
      expect(f.member('shouldFocusOnLoad'), isTrue);
      expect(f.log, [adList(), adFiles('z9')]);
    }),
  );

  testWidgets(
    'review snackbar stays visible before three seconds and expires after its exit animation',
    (t) => allDebridCase(t, (f) async {
      f.magnets = [adMagnet('z9', hash: '')];
      await f.mount(t);
      await f.action(t, 'Library z9', 'Add to Playlist');
      const message = 'This magnet has no infohash to save.';
      expect(find.text(message), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2999));
      expect(
        find.text(message),
        findsOneWidget,
        reason: 'Still visible immediately before the three-second deadline',
      );
      await t.pump(const Duration(milliseconds: 2));
      await t.pump(const Duration(milliseconds: 300));
      expect(
        find.text(message),
        findsNothing,
        reason: 'Expired after three seconds plus the exit animation',
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(f.log, [adList()]);
    }),
  );

  testWidgets(
    'review AppBar search-files tap focuses the new field without entering text',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.open(t);
      expect(find.byType(TextField), findsNothing);
      expect(f.focus('fileSearchFocusNode').context, isNull);
      await t.tap(find.byTooltip('Search files'));
      await t.pump();
      await t.pump();
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.focusNode, same(f.focus('fileSearchFocusNode')));
      expect(
        field.focusNode!.hasPrimaryFocus,
        isTrue,
        reason: 'The AppBar post-frame callback focuses the field',
      );
      expect(field.controller!.text, '');
      expect(f.member('fileSearchActive'), isTrue);
      expect(f.log, [adList(), adFiles('z9')]);
    }),
  );

  testWidgets(
    'review clear Left returns focus through the screen handler before directional traversal',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      final state = f.key.currentState;
      var directionalTraversals = 0;
      // Framework directional traversal can mask a missing explicit exit. A
      // host that owns traversal keeps the real screen/key dispatch observable.
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: f.navigatorKey,
          navigatorObservers: [f.observer],
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'AllDebridFixtureInter',
          ),
          home: Actions(
            actions: <Type, Action<Intent>>{
              DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
                onInvoke: (_) {
                  directionalTraversals++;
                  return null;
                },
              ),
            },
            child: f.screen(),
          ),
        ),
      );
      await t.pump();
      expect(f.key.currentState, same(state));
      await f.search(t, 'Library');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(f.focus('searchClearFocusNode').hasFocus, isTrue);
      expect(f.focus('searchFocusNode').hasFocus, isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(f.focus('searchFocusNode').hasPrimaryFocus, isTrue);
      expect(f.focus('searchClearFocusNode').hasFocus, isFalse);
      expect(
        directionalTraversals,
        0,
        reason: 'The clear handler consumes Left before host traversal',
      );
      expect(f.member('searchQuery'), 'Library');
      expect(f.log, [adList()]);
    }),
  );

  testWidgets(
    'review search Down releases the field when no first-row target is attached',
    (t) => allDebridCase(t, (f) async {
      f.magnets = [];
      await f.mount(t, query: 'no matching rows');
      await t.tap(find.byType(TextField));
      await t.pump();
      expect(f.member('visibleMagnets'), isEmpty);
      expect(f.focus('firstItemFocusNode').context, isNull);
      expect(f.focus('searchFocusNode').hasPrimaryFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(
        f.focus('searchFocusNode').hasFocus,
        isFalse,
        reason: 'An unattached target must release the editor',
      );
      expect(f.focus('firstItemFocusNode').hasFocus, isFalse);
      expect(f.member('searchQuery'), 'no matching rows');
      expect(f.log, [adList()]);
    }),
  );
}
