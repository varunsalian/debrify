import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';
import 'package:debrify/widgets/iptv/iptv_stage_panel.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Origin pin for the IPTV *preview-stage machinery* — the builders that
/// compose the leaf stage widgets into a stage: the Command Center cockpit
/// (`_buildCockpitStage`), its identity header (`_cockpitIdentity`), the touch
/// tablet's preview rail (`_buildPreviewRail`) and the shared 16:9 preview
/// surface (`_buildPreviewStage`).
///
/// Everything drives the real [IptvResultsView]: these builders are private
/// members of the view's State, so the only honest way to pin them is through
/// the public widget. Assertions therefore lean on rendered copy, text styles,
/// layout constants (paddings, radii, aspect ratio) and the public child
/// widgets the stage composes ([IptvStagePanel], [HeroTrailerBackdrop]) rather
/// than on any private type name.
///
/// Harness copied from `test/iptv_stage_widgets_origin_pin_test.dart`
/// (sqflite_ffi + an in-memory DebrifyTvDatabase, one seeded favourite,
/// `focusFirstFilter()` + arrow-down to land stage focus).
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
    // Resolution sits mid-name on purpose: the cockpit identity has to pull
    // "(1080p)" out of the title AND collapse the double space it leaves.
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

  void sizeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The stage's 16:9 video surface — one per composed stage.
  Finder previewSurface() => find.byWidgetPredicate(
    (w) => w is AspectRatio && w.aspectRatio == 16 / 9,
  );

  Finder paddingOf(EdgeInsets value) =>
      find.byWidgetPredicate((w) => w is Padding && w.padding == value);

  group('cockpit stage (TV / desktop pointer)', () {
    Future<void> focusFirstChannel(WidgetTester tester) async {
      tester
          .state<IptvResultsViewState>(find.byType(IptvResultsView))
          .focusFirstFilter();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('nothing focused: cockpit mounts, stage body is empty', (
      tester,
    ) async {
      sizeView(tester);
      await pumpView(tester, isTelevision: true);
      await drain(tester);

      // The cockpit row is the layout the stage lives in — rail, guide, stage.
      expect(find.byKey(const ValueKey('iptv-cockpit')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('iptv-tablet-two-pane')),
        findsNothing,
      );
      // The stage's outer padding is always there...
      expect(paddingOf(const EdgeInsets.fromLTRB(4, 16, 14, 16)), findsOneWidget);
      // ...but with no channel shown the body collapses to SizedBox.expand:
      // no preview surface, no identity, no stage panel.
      expect(previewSurface(), findsNothing);
      expect(find.byType(IptvStagePanel), findsNothing);
      expect(find.text('CH 4  Sky News HD'), findsNothing);
    });

    testWidgets('focused with preview on: identity, preview surface, panel', (
      tester,
    ) async {
      sizeView(tester);
      await pumpView(tester, isTelevision: true);
      await drain(tester);
      await focusFirstChannel(tester);

      // ── the stage shell ──────────────────────────────────────────────
      final clip = tester.widget<ClipRRect>(
        find
            .ancestor(
              of: find.byType(IptvStagePanel),
              matching: find.byType(ClipRRect),
            )
            .last,
      );
      expect(clip.borderRadius, AppThemes.legacy.shape.br(10));
      // No styled tokens on the legacy look, so the stage's own ground — the
      // ColoredBox inside the clip — is the theme's stage background.
      expect(
        tester
            .widgetList<ColoredBox>(
              find.ancestor(
                of: find.byType(IptvStagePanel),
                matching: find.byType(ColoredBox),
              ),
            )
            .map((w) => w.color),
        contains(AppThemes.legacy.iptv.stageBg),
      );
      expect(
        find.ancestor(
          of: find.byType(IptvStagePanel),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );

      // ── the identity block ───────────────────────────────────────────
      expect(paddingOf(const EdgeInsets.fromLTRB(16, 12, 16, 0)), findsOneWidget);
      final title = find.text('CH 4  Sky News HD');
      expect(title, findsOneWidget);
      final titleText = tester.widget<Text>(title);
      expect(titleText.maxLines, 1);
      expect(titleText.overflow, TextOverflow.ellipsis);
      expect(titleText.style!.fontSize, 15.5);
      expect(titleText.style!.fontWeight, FontWeight.w800);
      expect(titleText.style!.height, 1.1);
      expect(titleText.style!.color, AppThemes.legacy.core.tx);

      // Group and the resolution lifted out of the name, dot-joined. The
      // tablet rail prints the same string at 12/w600, so match the cockpit's
      // own 10.5/w600.
      final sub = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data == 'News  •  1080p' &&
            w.style?.fontSize == 10.5 &&
            w.style?.fontWeight == FontWeight.w600,
      );
      expect(sub, findsOneWidget);

      // 34x34 logo chip leading the identity row (the tablet rail's is 46x46).
      final identityRow = find
          .ancestor(of: title, matching: find.byType(Row))
          .first;
      final plate = tester.renderObject<RenderBox>(
        find.descendant(of: identityRow, matching: find.byType(Container)).first,
      );
      expect(plate.size, const Size(34, 34));

      // ── the preview surface ──────────────────────────────────────────
      expect(previewSurface(), findsOneWidget);
      // Preview is on and nothing suppresses it, so the backdrop mounts for
      // the focused channel and the chip says TUNING (no frames yet).
      expect(find.byType(HeroTrailerBackdrop), findsOneWidget);
      final backdrop = tester.widget<HeroTrailerBackdrop>(
        find.byType(HeroTrailerBackdrop),
      );
      expect(backdrop.videoUrl, 'http://h/sky');
      expect(backdrop.live, isTrue);
      expect(backdrop.enabled, isTrue);
      expect(backdrop.imageUrl, isNull);
      expect(backdrop.startDelay, const Duration(milliseconds: 900));
      expect(backdrop.ambientVolume, 100);
      expect(backdrop.imageBlurSigma, 0);
      expect(backdrop.videoBlurSigma, 0);
      // Not a Stremio channel: no first-frame stall timeout.
      expect(backdrop.firstFrameTimeout, isNull);
      expect(find.text('TUNING'), findsOneWidget);
      expect(find.text('PREVIEW OFF'), findsNothing);

      // ── the stage panel ──────────────────────────────────────────────
      final panel = tester.widget<IptvStagePanel>(find.byType(IptvStagePanel));
      expect(panel.key, const ValueKey('stage-http://h/sky'));
      expect(panel.channel.url, 'http://h/sky');
      expect(panel.isTelevision, isTrue);
      // Seeded into the Favorites list, so the stage opens already-favourited.
      expect(panel.isFavorited, isTrue);
      expect(panel.isRecordingThis, isFalse);
      // Legacy look: no styled tokens.
      expect(panel.tokens, isNull);
      // Live channel (not a series), so the favourite action is wired.
      expect(panel.onToggleFavorite, isNotNull);
      // A plain http url is not EPG-capable and not schedulable, so the
      // Guide and Schedule seams stay null.
      expect(panel.onOpenFullSchedule, isNull);
      expect(panel.onScheduleProgramme, isNull);
      expect(panel.onPlayProgramme, isNotNull);
      expect(panel.onExitLeft, isNotNull);
      // The panel's own copy: the Watch action (a non-EPG channel gets no
      // day-schedule section at all).
      expect(find.text('Watch'), findsOneWidget);
      expect(find.text('TODAY'), findsNothing);
    });

    testWidgets('preview off: no backdrop, the rest of the stage is intact', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'iptv_defaults_initialized': true,
        'iptv_channel_preview_enabled': false,
      });
      sizeView(tester);
      await pumpView(tester, isTelevision: true);
      await drain(tester);
      await focusFirstChannel(tester);

      // The 16:9 surface still composes — only the video is withheld.
      expect(previewSurface(), findsOneWidget);
      expect(find.byType(HeroTrailerBackdrop), findsNothing);
      expect(find.text('PREVIEW OFF'), findsOneWidget);
      expect(find.text('TUNING'), findsNothing);
      // Identity and panel are unaffected by the preview setting.
      expect(find.text('CH 4  Sky News HD'), findsOneWidget);
      expect(find.byType(IptvStagePanel), findsOneWidget);
      expect(find.text('Watch'), findsOneWidget);
    });
  });

  group('touch tablet preview rail', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('two-pane rail: preview surface, info, fullscreen + hint', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      sizeView(tester);

      await pumpView(tester, isTelevision: false);
      await drain(tester);

      // The tablet arrangement, not the cockpit.
      expect(find.byKey(const ValueKey('iptv-tablet-two-pane')), findsOneWidget);
      expect(find.byKey(const ValueKey('iptv-cockpit')), findsNothing);

      // The rail's own padding, and the same 16:9 preview surface the cockpit
      // uses (this layout settles a channel into the stage on its own).
      expect(paddingOf(const EdgeInsets.fromLTRB(14, 16, 12, 16)), findsOneWidget);
      expect(previewSurface(), findsOneWidget);
      // The rail's identity block, at its own 16.5/w800 (the cockpit's is
      // 15.5/w800) — proof the rail composes IptvRailInfo, not the cockpit's.
      final railTitle = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data == 'CH 4  Sky News HD' &&
            w.style?.fontSize == 16.5,
      );
      expect(railTitle, findsOneWidget);
      // The cockpit's stage panel never mounts on this layout.
      expect(find.byType(IptvStagePanel), findsNothing);

      // The touch-selector extras: a full-width launch button and the scroll
      // hint that replaces the pointer's hover copy.
      final watch = find.byKey(const ValueKey('iptv-tablet-watch-fullscreen'));
      expect(watch, findsOneWidget);
      expect(find.text('Watch fullscreen'), findsOneWidget);
      expect(
        find.descendant(of: watch, matching: find.byIcon(Icons.fullscreen_rounded)),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNotNull,
      );
      final hint = find.text('Scroll channels through the arrow to preview');
      expect(hint, findsOneWidget);
      final hintText = tester.widget<Text>(hint);
      expect(hintText.style!.fontSize, 11.5);
      expect(hintText.style!.fontWeight, FontWeight.w600);
      expect(hintText.style!.letterSpacing, 0.1);
      expect(
        hintText.style!.color,
        AppThemes.legacy.seeAll.accent2.withValues(alpha: 0.66),
      );
      expect(paddingOf(const EdgeInsets.only(top: 9)), findsOneWidget);
      // The pointer-layout hint is NOT the one this rail shows.
      expect(
        find.text('Hover a channel to preview  ·  Click to watch'),
        findsNothing,
      );

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('preview off: the rail swaps its hint copy', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'iptv_defaults_initialized': true,
        'iptv_channel_preview_enabled': false,
      });
      sizeView(tester);

      await pumpView(tester, isTelevision: false);
      await drain(tester);

      expect(
        find.text('Preview is off · choose Watch fullscreen'),
        findsOneWidget,
      );
      expect(
        find.text('Scroll channels through the arrow to preview'),
        findsNothing,
      );
      expect(find.byType(HeroTrailerBackdrop), findsNothing);
      // The button and the surface stay: only the video and the copy change.
      expect(previewSurface(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('iptv-tablet-watch-fullscreen')),
        findsOneWidget,
      );

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('empty shelf: the rail floors, button disabled, hint stays', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      sizeView(tester);

      // Drop the favourite but keep a custom list, so the page still lands on
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

      // The rail still composes its whole column — surface, hint, button —
      // with no channel in it.
      expect(previewSurface(), findsOneWidget);
      expect(find.text('Browse channels to preview'), findsOneWidget);
      expect(find.byType(HeroTrailerBackdrop), findsNothing);
      expect(find.text('CH 4  Sky News HD'), findsNothing);
      final watch = find.byKey(const ValueKey('iptv-tablet-watch-fullscreen'));
      expect(watch, findsOneWidget);
      // No channel: the launch button is disabled and shows the non-series
      // label/icon.
      expect(tester.widget<FilledButton>(watch).onPressed, isNull);
      expect(find.text('Watch fullscreen'), findsOneWidget);
      expect(
        find.text('Scroll channels through the arrow to preview'),
        findsOneWidget,
      );

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
