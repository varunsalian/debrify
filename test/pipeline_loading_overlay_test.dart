import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';

void main() {
  Future<PipelineLoadingOverlay> showOverlay(
    WidgetTester tester, {
    bool bound = false,
    bool hasCacheCheck = true,
    PlayLoaderStyle style = PlayLoaderStyle.classic,
    PlayLoaderArt? art,
    VoidCallback? onCancel,
  }) async {
    late PipelineLoadingOverlay handle;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                handle = PipelineLoadingOverlay.show(
                  context,
                  // No posterUrl → no Image.network in the test.
                  title: 'The Last of Us',
                  subtitle: 'S01E05',
                  providerLabel: 'TorBox',
                  providerCode: 'TB',
                  providerColor: const Color(0xFF35D6B8),
                  bound: bound,
                  hasCacheCheck: hasCacheCheck,
                  style: style,
                  art: art,
                  onCancel: onCancel,
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump(); // build the dialog
    await tester.pump(const Duration(milliseconds: 320)); // finish fade-in
    return handle;
  }

  testWidgets('renders the full search checklist and advances stages',
      (tester) async {
    final handle = await showOverlay(tester);

    expect(find.text('Searching sources'), findsOneWidget);
    expect(find.text("Checking what's cached"), findsOneWidget);
    expect(find.text('Preparing your stream'), findsOneWidget);
    expect(find.text('Starting playback'), findsOneWidget);
    expect(find.text('The Last of Us'), findsOneWidget);
    expect(find.text('TorBox'), findsOneWidget);

    handle.setStage(PlayLoadStage.searching, sourceCount: 24);
    await tester.pump();
    expect(find.text('24 found'), findsOneWidget);

    handle.setStage(PlayLoadStage.cacheCheck, cachedCount: 6);
    await tester.pump();
    expect(find.text('6 ready'), findsOneWidget);

    handle.setStage(PlayLoadStage.preparing);
    await tester.pump();
    handle.setStage(PlayLoadStage.starting);
    await tester.pump();
    expect(tester.takeException(), isNull);

    handle.dismiss();
    await tester.pump(); // start the pop
    await tester.pump(const Duration(seconds: 1)); // finish the reverse fade
    expect(find.text('The Last of Us'), findsNothing);
  });

  testWidgets('bound mode shows only the short checklist', (tester) async {
    await showOverlay(tester, bound: true);
    expect(find.text('Searching sources'), findsNothing);
    expect(find.text("Checking what's cached"), findsNothing);
    expect(find.text('Preparing your stream'), findsOneWidget);
    expect(find.text('Starting playback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stage not in this overlay is ignored (no backwards jump)',
      (tester) async {
    // Provider with no cache step: cacheCheck is not a displayed stage.
    final handle = await showOverlay(tester, hasCacheCheck: false);
    expect(find.text("Checking what's cached"), findsNothing);

    // An out-of-list update must not disturb the current stage.
    handle.setStage(PlayLoadStage.cacheCheck, cachedCount: 6);
    await tester.pump();
    expect(find.text("Checking what's cached"), findsNothing);
    // Then a real stage still advances normally.
    handle.setStage(PlayLoadStage.preparing);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('setStage is monotonic — a backward stage does not rewind, '
      'but its counts still merge', (tester) async {
    final handle = await showOverlay(tester); // full checklist
    handle.setStage(PlayLoadStage.preparing);
    await tester.pump();

    // Re-reporting an earlier stage (pack-first fell through to episode
    // search) must not rewind the checklist — but its count still updates.
    handle.setStage(PlayLoadStage.searching, sourceCount: 30);
    await tester.pump();
    expect(find.text('30 found'), findsOneWidget); // count merged
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop width renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await showOverlay(tester);
    expect(find.text('Preparing your stream'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel invokes the callback', (tester) async {
    var cancelled = false;
    await showOverlay(tester, onCancel: () => cancelled = true);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancelled, isTrue);
  });

  testWidgets('system Back both cancels AND dismisses the overlay',
      (tester) async {
    var cancelled = false;
    await showOverlay(tester, onCancel: () => cancelled = true);
    expect(find.text('The Last of Us'), findsOneWidget);

    // Simulate the hardware/TV Back button.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // finish reverse fade

    expect(cancelled, isTrue);
    // The regression this guards: Back must not leave the overlay stuck.
    expect(find.text('The Last of Us'), findsNothing);
  });

  testWidgets('short screen scrolls instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await showOverlay(tester, onCancel: () {});
    expect(tester.takeException(), isNull); // no RenderFlex overflow
    expect(find.text('The Last of Us'), findsOneWidget);
  });
  testWidgets('setNote shows, updates, survives setStage, and hides on null',
      (tester) async {
    final handle = await showOverlay(tester);

    // Hidden by default — plays without filters look exactly as before.
    expect(find.byIcon(Icons.filter_alt_rounded), findsNothing);

    handle.setNote('Matching your filters (1080p \u00b7 WEB) \u00b7 12 sources');
    await tester.pump();
    expect(
      find.text('Matching your filters (1080p \u00b7 WEB) \u00b7 12 sources'),
      findsOneWidget,
    );

    // A stage advance must not clobber the note.
    handle.setStage(PlayLoadStage.preparing);
    await tester.pump();
    expect(
      find.text('Matching your filters (1080p \u00b7 WEB) \u00b7 12 sources'),
      findsOneWidget,
    );

    // Non-monotonic: the note can change to a relax message...
    handle.setNote('No full filter match \u2014 trying without language match');
    await tester.pump();
    expect(
      find.text('No full filter match \u2014 trying without language match'),
      findsOneWidget,
    );

    // ...and null hides the line entirely.
    handle.setNote(null);
    await tester.pump();
    expect(find.byIcon(Icons.filter_alt_rounded), findsNothing);
  });
  // ── Marquee ───────────────────────────────────────────────────────────────
  // Art with no image URLs: the layout is exercised without any network image
  // (which would 400 in a widget test), while the meta line is fully painted.
  const art = PlayLoaderArt(
    yearLabel: '2024',
    ratingLabel: '8.5',
    runtimeLabel: '2h 46m',
    certificate: 'PG-13',
    genreLabel: 'Sci-Fi · Adventure',
  );

  testWidgets('marquee shows the live stage, its count, and the meta line',
      (tester) async {
    final handle = await showOverlay(
      tester,
      style: PlayLoaderStyle.marquee,
      art: art,
      onCancel: () {},
    );

    // One live sentence, not the four-row checklist.
    expect(find.text('Searching sources'), findsOneWidget);
    expect(find.text('Preparing your stream'), findsNothing);
    // The rail carries the other stages in short form.
    expect(find.text('SEARCH'), findsOneWidget);
    expect(find.text('CACHE'), findsOneWidget);
    expect(find.text('PREPARE'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
    // Meta line from the detail page's data.
    expect(find.text('IMDb 8.5'), findsOneWidget);
    expect(find.text('2h 46m'), findsOneWidget);
    expect(find.text('PG-13'), findsOneWidget);
    // Title as type (no logo art on this play) and the provider chip.
    expect(find.text('The Last of Us'), findsOneWidget);
    expect(find.text('TorBox'), findsOneWidget);

    handle.setStage(PlayLoadStage.searching, sourceCount: 24);
    await tester.pump();
    expect(find.text('24 found'), findsOneWidget);

    handle.setStage(PlayLoadStage.cacheCheck, cachedCount: 6);
    await tester.pump();
    expect(find.text("Checking what's cached"), findsOneWidget);
    // The sticky source count must not keep reading on the cache stage.
    expect(find.text('24 found'), findsNothing);
    expect(find.text('6 ready'), findsOneWidget);

    handle.setStage(PlayLoadStage.starting);
    await tester.pump();
    expect(find.text('Starting playback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marquee renders with no art at all, and Cancel still works',
      (tester) async {
    var cancelled = false;
    await showOverlay(
      tester,
      style: PlayLoaderStyle.marquee,
      onCancel: () => cancelled = true,
    );
    // Degrades to the ground gradient + the title as type.
    expect(find.text('The Last of Us'), findsOneWidget);
    expect(find.text('IMDb 8.5'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancelled, isTrue);
  });

  testWidgets('marquee plates a poster-only play (the Continue Watching shape)',
      (tester) async {
    await showOverlay(
      tester,
      style: PlayLoaderStyle.marquee,
      // No backdrop, no logo — a Continue Watching row after art derivation
      // failed to find wide art. The plate must still be the poster.
      art: const PlayLoaderArt(posterUrl: 'https://art.example/poster.jpg'),
    );
    final plate = tester.widget<Image>(find.byType(Image));
    expect(
      (plate.image as NetworkImage).url,
      'https://art.example/poster.jpg',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('marquee rail segments actually paint — done fills, active crawls',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final handle = await showOverlay(tester, style: PlayLoaderStyle.marquee);

    // Stage 1 of 4: only the active segment carries a fill.
    var fills = find.byKey(PipelineLoadingOverlay.railFillKey);
    expect(fills, findsOneWidget);
    // The regression: a fill that builds but has zero height paints nothing.
    // Assert real pixels, not mere existence.
    var size = tester.getSize(fills);
    expect(size.height, greaterThan(0));
    expect(size.width, greaterThan(0));

    // Third of four stages: two completed fills plus the active one.
    handle.setStage(PlayLoadStage.preparing);
    await tester.pump();
    fills = find.byKey(PipelineLoadingOverlay.railFillKey);
    expect(fills, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      expect(tester.getSize(fills.at(i)).height, greaterThan(0));
    }
    // A completed segment fills its whole track; the active one does not.
    final done = tester.getSize(fills.at(0)).width;
    final active = tester.getSize(fills.at(2)).width;
    expect(active, lessThan(done));
  });

  testWidgets('marquee keeps a spinner running on every stage', (tester) async {
    final handle = await showOverlay(tester, style: PlayLoaderStyle.marquee);
    // Present from the first stage to the last — the plate must never look
    // frozen while a slow resolve is still working.
    for (final stage in PlayLoadStage.values) {
      handle.setStage(stage);
      await tester.pump();
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'no spinner on $stage',
      );
    }
    // Indeterminate (spinning), not a fixed arc, when motion is allowed.
    expect(
      tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      ).value,
      isNull,
    );
  });

  testWidgets('marquee spinner holds a static arc under reduced motion',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => PipelineLoadingOverlay.show(
                    context,
                    title: 'The Last of Us',
                    providerLabel: 'TorBox',
                    providerCode: 'TB',
                    providerColor: const Color(0xFF35D6B8),
                    style: PlayLoaderStyle.marquee,
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.value, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marquee logo art still announces the title to a screen reader',
      (tester) async {
    await showOverlay(
      tester,
      style: PlayLoaderStyle.marquee,
      art: const PlayLoaderArt(logoUrl: 'https://art.example/logo.png'),
    );
    // The image never loads under the test binding (every request 400s), so
    // this asserts the property rather than the rendered semantics tree: when
    // the logo DOES load it replaces the title Text outright, and without this
    // label the plate would announce no title at all.
    expect(
      tester.widget<Image>(find.byType(Image)).semanticLabel,
      'The Last of Us',
    );
    // The failed load falls back to the title as type — also announced.
    expect(find.text('The Last of Us'), findsOneWidget);
  });

  testWidgets('marquee bound mode shows only the two live stages',
      (tester) async {
    await showOverlay(tester, style: PlayLoaderStyle.marquee, bound: true);
    expect(find.text('SEARCH'), findsNothing);
    expect(find.text('CACHE'), findsNothing);
    expect(find.text('PREPARE'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('Preparing your stream'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Phone (portrait column), desktop and TV (left-column landscape) each lay
  // the same body out differently — all three must fit.
  for (final (name, size) in const [
    ('phone', Size(360, 640)),
    ('desktop', Size(1440, 900)),
    ('TV', Size(1920, 1080)),
  ]) {
    testWidgets('marquee fits $name without overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await showOverlay(
        tester,
        style: PlayLoaderStyle.marquee,
        art: art,
        onCancel: () {},
      );
      expect(tester.takeException(), isNull);
      expect(find.text('The Last of Us'), findsOneWidget);
      expect(find.text('Searching sources'), findsOneWidget);
    });
  }

  testWidgets('landscape layout renders the note; setNote after dismiss is a no-op',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final handle = await showOverlay(tester);
    handle.setNote('Matching your filters \u00b7 3 sources');
    await tester.pump();
    expect(find.text('Matching your filters \u00b7 3 sources'), findsOneWidget);
    expect(tester.takeException(), isNull);

    handle.dismiss();
    await tester.pumpAndSettle();
    // Dismissed: setNote must be a silent no-op, not a crash or a ghost note.
    handle.setNote('after dismiss');
    await tester.pump();
    expect(find.text('after dismiss'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
