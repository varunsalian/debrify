import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/presentation/home_board_cell.dart';
import 'package:debrify/features/home/presentation/home_continuation_row.dart';
import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/card_metadata_fixture.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  for (final television in [false, true]) {
    testWidgets(
      'Continue Watching row keeps live progress, borrowed focus and menu dispatch: TV=$television',
      (tester) async {
        final nodes = List.generate(3, (_) => FocusNode());
        addTearDown(() {
          for (final node in nodes) {
            node.dispose();
          }
        });
        final items = List.generate(
          3,
          (i) => StremioMeta(id: '$i', type: 'series', name: 'Item $i'),
        );
        final actions = <String>[];
        var progress = .25;
        var aspect = 2 / 3;
        var titles = true;
        var bound = false;
        var episode = 'S1 · E2';
        final data = CardMetadataFake()
          ..respond = (item) async => MetadataPresentation(item);
        final row = HomeContinuationRow(
          rowId: 'local:series',
          title: 'Continue Watching',
          tag: 'Series',
          kind: HomeContinuationKind.local,
          items: items,
          nodes: nodes,
          progressOf: (item) => item.id == '0' ? progress : null,
          episodeOf: (item) => item.id == '0' ? episode : null,
          remainingMinutesOf: (_) => null,
          episodeArtworkOf: (_) => null,
          onOpen: (item) => actions.add('open:${item.id}'),
          onQuickPlay: (item) => actions.add('quick:${item.id}'),
          onRemove: (item) async => actions.add('remove:${item.id}'),
        );
        Widget page() => ProviderScope(
          overrides: [
            homeCardMetadataRepositoryProvider.overrideWith(
              (ref, epoch) => data.repository(epoch),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: buildHomeContinuationRow(
                row: row,
                header: const Text('Continue Watching'),
                isTelevision: television,
                posterWidth: 160,
                cellHeight: 240,
                aspectRatio: () => aspect,
                showTitleOverlay: () => titles,
                artOf: (_) => null,
                isBound: (_) => bound,
                onLeftEdge: () => actions.add('edge'),
                onFocused: (item) => actions.add('focus:${item.id}'),
                onMenu: (item, col) => actions.add('menu:${item.id}:$col'),
                onUp: (col) => actions.add('up:$col'),
                onDown: (col) => actions.add('down:$col'),
              ),
            ),
          ),
        );
        final firstFrame = page();
        // Preferences/progress may change before the lazy strip materializes.
        progress = .4;
        await tester.pumpWidget(firstFrame);
        HomeBoardCell first() =>
            tester.widgetList<HomeBoardCell>(find.byType(HomeBoardCell)).first;
        expect(first().progress, .4);
        expect(first().episodeLabel, 'S1 · E2');
        expect(first().showWatchedBadge, isFalse);
        expect(first().onQuickPlay, isNull);
        expect(first().rowNodes, same(nodes));
        expect(tester.getSize(find.byType(ListView)).height, 254);
        expect(
          tester
              .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
              .widthFactor,
          .4,
        );
        nodes[0].requestFocus();
        await tester.pump();
        final element = find.byType(HomeBoardCell).evaluate().first;
        progress = .75;
        episode = 'S2 · E3';
        aspect = 16 / 9;
        titles = false;
        bound = true;
        await tester.pumpWidget(page());
        expect(find.byType(HomeBoardCell).evaluate().first, same(element));
        expect(nodes[0].hasFocus, isTrue);
        expect(first().progress, .75);
        expect(first().episodeLabel, 'S2 · E3');
        expect(first().aspectRatio, 16 / 9);
        expect(first().showTitleOverlay, isFalse);
        expect(first().hasBoundSource, isTrue);
        expect(
          tester
              .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
              .widthFactor,
          .75,
        );
        actions.clear();
        if (television) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          expect(nodes[1].hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          expect(actions, containsAllInOrder(['focus:1', 'up:1', 'down:1']));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          expect(actions.last, 'edge');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 501));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.byType(HomeBoardCell).first);
          await tester.longPress(find.byType(HomeBoardCell).first);
        }
        expect(actions.where((value) => value == 'open:0'), hasLength(1));
        expect(actions.where((value) => value == 'menu:0:0'), hasLength(1));
        expect(
          actions.where(
            (value) =>
                value.startsWith('quick:') || value.startsWith('remove:'),
          ),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            home: Focus(focusNode: nodes[0], child: const Text('Reused')),
          ),
        );
        nodes[0].requestFocus();
        await tester.pump();
        expect(nodes[0].hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
