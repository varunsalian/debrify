import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Origin pin for the IPTV preview-stage widgets that live at the tail of
/// `iptv_results_view.dart`: the stage floor and its tuning-wave painter, the
/// LIVE/TUNING/PREVIEW OFF status chip and its signal-bar painter, and the
/// tablet rail's identity block.
///
/// Everything here drives the real [IptvResultsView] — the widgets under test
/// are private to that library, so the only honest way to pin them is through
/// the public view. Assertions deliberately avoid naming the private classes
/// (they get renamed when the widgets move) and lean on rendered text, painter
/// geometry and the animation-scheduling behaviour instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // Skip the first-run iptv-org seed: the pin only needs the Favorites
      // shelf, which lands without any network-backed provider.
      'iptv_defaults_initialized': true,
    });
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
          ),
        );
    // Resolution sits mid-name on purpose: the rail/identity split has to pull
    // "(1080p)" out AND collapse the double space it leaves behind.
    await IptvPrefs.setIptvChannelInList(
      IptvPrefs.iptvFavoritesListId,
      'http://h/sky',
      true,
      channelName: 'Sky News (1080p) HD',
      group: 'News',
      channelNumber: 4,
      duration: -1,
    );
  });

  tearDown(() async {
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    IptvMediaStore.debugResetMigration();
  });

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pumpView(WidgetTester tester, {required bool isTelevision}) {
    return tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: Scaffold(
            body: IptvResultsView(
              searchQuery: '',
              isTelevision: isTelevision,
            ),
          ),
        ),
      ),
    );
  }

  /// Every CustomPaint in the tree that actually carries a painter. The stage
  /// is the only thing in this page that paints, so the count is a stable
  /// stand-in for "the tuning painters are mounted".
  List<CustomPaint> painters(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .where((w) => w.painter != null)
      .toList();

  group('cockpit stage (TV)', () {
    Future<void> focusFirstChannel(WidgetTester tester) async {
      tester
          .state<IptvResultsViewState>(find.byType(IptvResultsView))
          .focusFirstFilter();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('nothing focused: the stage paints nothing at all', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpView(tester, isTelevision: true);
      await drain(tester);

      expect(painters(tester), isEmpty);
      expect(find.text('TUNING'), findsNothing);
      expect(find.text('PREVIEW OFF'), findsNothing);
    });

    testWidgets('focused with preview on: TUNING chip, waves + bars painters', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpView(tester, isTelevision: true);
      await drain(tester);
      await focusFirstChannel(tester);

      // Chip: no frames yet, so the label is TUNING, drawn on the black-glass
      // pill regardless of theme.
      expect(find.text('TUNING'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
      expect(find.text('PREVIEW OFF'), findsNothing);
      final chipContainer = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('TUNING'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (chipContainer.decoration! as BoxDecoration).color,
        const Color(0xB00B0918),
      );
      final chipLabel = tester.widget<Text>(find.text('TUNING'));
      expect(chipLabel.style!.fontSize, 9.5);
      expect(chipLabel.style!.fontWeight, FontWeight.w800);
      expect(chipLabel.style!.letterSpacing, 1.0);

      // Exactly two painters: the floor's tuning waves (full stage rect) and
      // the chip's signal bars (the 9x9 slot in front of the label).
      final paints = painters(tester);
      expect(paints, hasLength(2));
      final sizes = [
        for (final p in paints)
          tester.renderObject<RenderBox>(find.byWidget(p)).size,
      ];
      expect(sizes, contains(const Size(9, 9)));
      final waves = sizes.firstWhere((s) => s != const Size(9, 9));
      expect(waves.width, greaterThan(100));
      expect(waves.height, greaterThan(100));

      // Both painters repaint off a running AnimationController, so the
      // binding keeps asking for frames while the stage is tuning.
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);

      // The floor draws the channel's placeholder mark (no logo url stored).
      expect(find.byIcon(Icons.live_tv_rounded), findsWidgets);
    });

    testWidgets('preview disabled: PREVIEW OFF chip, faint dot, no painters', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'iptv_defaults_initialized': true,
        'iptv_channel_preview_enabled': false,
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpView(tester, isTelevision: true);
      await drain(tester);
      await focusFirstChannel(tester);

      expect(find.text('PREVIEW OFF'), findsOneWidget);
      expect(find.text('TUNING'), findsNothing);
      // Static dot, not the animated bars: nothing paints and nothing is
      // scheduling frames any more.
      expect(painters(tester), isEmpty);

      final dot = tester.widget<Container>(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text('PREVIEW OFF'),
                    matching: find.byType(Row),
                  )
                  .first,
              matching: find.byType(Container),
            )
            .last,
      );
      final dotBox = dot.decoration! as BoxDecoration;
      expect(dotBox.shape, BoxShape.circle);
      expect(dotBox.color, AppThemes.legacy.iptv.inkFaint);
      expect(
        tester.renderObject<RenderBox>(find.byWidget(dot)).size,
        const Size(6, 6),
      );
    });
  });

  group('tablet rail identity block', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('logo plate, CH-number title with the resolution pulled out', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpView(tester, isTelevision: false);
      await drain(tester);

      expect(find.byKey(const ValueKey('iptv-tablet-two-pane')), findsOneWidget);

      // The rail's own identity block: "(1080p)" is lifted out of the title
      // into the sub-line and the gap it leaves is collapsed.
      final title = find.text('CH 4  Sky News HD');
      expect(title, findsOneWidget);
      final titleWidget = tester.widget<Text>(title);
      expect(titleWidget.maxLines, 2);
      expect(titleWidget.style!.fontSize, 16.5);
      expect(titleWidget.style!.fontWeight, FontWeight.w800);

      // The channel row prints the same sub-line at 12.5/w500; the rail's is
      // 12/w600, so match on the rail's own style.
      final sub = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data == 'News  •  1080p' &&
            w.style?.fontSize == 12 &&
            w.style?.fontWeight == FontWeight.w600,
      );
      expect(sub, findsOneWidget);

      // 46x46 logo plate leading the identity row.
      final identityRow = find
          .ancestor(of: title, matching: find.byType(Row))
          .first;
      final plate = tester.renderObject<RenderBox>(
        find.descendant(of: identityRow, matching: find.byType(Container)).first,
      );
      expect(plate.size, const Size(46, 46));
      expect(
        find.descendant(
          of: identityRow,
          matching: find.byIcon(Icons.live_tv_rounded),
        ),
        findsOneWidget,
      );

      // Reset inside the body: the binding's debug-var invariant runs before
      // tearDown.
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('empty shelf: the floor shows its browse-me placeholder', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Drop the favorite but keep a custom list, so the page still lands on
      // the (now empty) Favorites shelf and nothing can take stage focus.
      await tester.runAsync(() async {
        await IptvPrefs.setIptvChannelInList(
          IptvPrefs.iptvFavoritesListId,
          'http://h/sky',
          false,
        );
        await IptvPrefs.createIptvList('Kids');
      });

      await pumpView(tester, isTelevision: false);
      await drain(tester);

      expect(find.text('Browse channels to preview'), findsOneWidget);
      final placeholder = tester.widget<Text>(
        find.text('Browse channels to preview'),
      );
      expect(placeholder.style!.fontSize, 12.5);
      expect(placeholder.style!.fontWeight, FontWeight.w600);
      // No channel: the chip collapses entirely and the floor does not tune.
      expect(find.text('TUNING'), findsNothing);
      expect(find.text('PREVIEW OFF'), findsNothing);
      expect(find.text('LIVE'), findsNothing);
      expect(
        painters(tester).map(
          (p) => tester.renderObject<RenderBox>(find.byWidget(p)).size,
        ),
        isNot(contains(const Size(9, 9))),
      );
      // And the rail identity block renders nothing at all.
      expect(find.text('CH 4  Sky News HD'), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
