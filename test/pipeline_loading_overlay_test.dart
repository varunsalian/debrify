import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';

void main() {
  Future<PipelineLoadingOverlay> showOverlay(
    WidgetTester tester, {
    bool bound = false,
    bool hasCacheCheck = true,
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
