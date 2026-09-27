import 'dart:async';

import 'package:debrify/features/home/models/home_random_playback_preparation.dart';
import 'package:debrify/features/home/presentation/home_random_playback_action.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/random_playback_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const selection = AdvancedSearchSelection(
  imdbId: 'tt123',
  isSeries: true,
  title: 'Show',
  season: 2,
  episode: 3,
);
const item = StremioMeta(
  id: 'catalog:custom',
  type: 'series',
  name: 'Catalog title',
);
final addon = StremioAddon(
  id: 'origin',
  name: 'Origin',
  baseUrl: 'https://fixture.invalid',
  manifestUrl: 'https://fixture.invalid/manifest.json',
  addedAt: DateTime.utc(2026),
);

class ActionHarness {
  bool current = true;
  final prepared = <bool>[];
  final messages = <String>[];
  final launches =
      <
        ({AdvancedSearchSelection selection, String addonId, StremioMeta item})
      >[];
  Future<HomeRandomPlaybackPreparation> Function() prepare = () async =>
      const HomeRandomPlaybackPreparation.ready(selection);
  final playing = Completer<void>();
  Future<void>? pending;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                pending = runHomeRandomPlayback(
                  context: context,
                  item: item,
                  addon: addon,
                  isCurrent: () => current,
                  prepare: (continuous) {
                    prepared.add(continuous);
                    return prepare();
                  },
                  showMessage: messages.add,
                  launch:
                      (
                        value, {
                        required metadataAddonId,
                        required catalogItem,
                      }) async {
                        launches.add((
                          selection: value,
                          addonId: metadataAddonId,
                          item: catalogItem,
                        ));
                        await playing.future;
                      },
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> once(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final continuous in [false, true]) {
    testWidgets(
      'choice dispatches once with original catalog metadata: continuous=$continuous',
      (tester) async {
        final h = ActionHarness();
        await h.open(tester);
        expect(h.prepared, isEmpty);
        expect(find.text(item.name), findsOneWidget);
        if (continuous) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        await h.once(tester);
        await h.pending;
        expect(h.prepared, [continuous]);
        expect(h.launches, hasLength(1));
        expect(h.launches.single.selection, same(selection));
        expect(h.launches.single.addonId, addon.id);
        expect(h.launches.single.item.sourceAddon, same(addon));
        expect(h.launches.single.item.id, item.id);
        expect(
          h.playing.isCompleted,
          isFalse,
        ); // Handoff is dispatched, not awaited.
        expect(h.messages, isEmpty);
        h.playing.complete();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Cancel closes without resolving dependencies or dispatching', (
    tester,
  ) async {
    final h = ActionHarness();
    await h.open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await h.pending;
    expect(h.prepared, isEmpty);
    expect(h.launches, isEmpty);
    expect(h.messages, isEmpty);
  });

  testWidgets('retired action does not open the dialog', (tester) async {
    final h = ActionHarness()..current = false;
    await h.open(tester);
    await h.pending;
    expect(find.byType(RandomPlaybackDialog), findsNothing);
    expect(h.prepared, isEmpty);
  });

  testWidgets(
    'retirement while choosing does not resolve preparation dependencies',
    (tester) async {
      final h = ActionHarness();
      await h.open(tester);
      h.current = false;
      await h.once(tester);
      await h.pending;
      expect(h.prepared, isEmpty);
      expect(h.launches, isEmpty);
      expect(h.messages, isEmpty);
    },
  );

  for (final unmount in [false, true]) {
    testWidgets(
      'pending preparation cannot dispatch after ${unmount ? 'unmount' : 'profile retirement'}',
      (tester) async {
        final wait = Completer<HomeRandomPlaybackPreparation>();
        final h = ActionHarness()..prepare = () => wait.future;
        await h.open(tester);
        await h.once(tester);
        expect(h.prepared, [false]);
        if (unmount) {
          await tester.pumpWidget(const SizedBox());
        } else {
          h.current = false;
        }
        wait.complete(const HomeRandomPlaybackPreparation.ready(selection));
        await h.pending;
        expect(h.launches, isEmpty);
        expect(h.messages, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final result in [
    const HomeRandomPlaybackPreparation.loadFailed(),
    const HomeRandomPlaybackPreparation.noEpisodes(),
    const HomeRandomPlaybackPreparation.retired(),
  ]) {
    testWidgets('${result.status} retains message behavior without launching', (
      tester,
    ) async {
      final h = ActionHarness()..prepare = () async => result;
      await h.open(tester);
      await h.once(tester);
      await h.pending;
      expect(h.launches, isEmpty);
      expect(h.messages, switch (result.status) {
        HomeRandomPlaybackStatus.loadFailed => [
          'Could not load episodes. Please retry.',
        ],
        HomeRandomPlaybackStatus.noEpisodes => [
          'Couldn\'t load episodes for "Catalog title".',
        ],
        _ => <String>[],
      });
    });
  }

  testWidgets(
    'preparation exceptions retain propagation without launch or replacement message',
    (tester) async {
      final wait = Completer<HomeRandomPlaybackPreparation>();
      final h = ActionHarness()..prepare = () => wait.future;
      await h.open(tester);
      await h.once(tester);
      final error = StateError('addon lookup failed');
      final expectation = expectLater(h.pending, throwsA(same(error)));
      wait.completeError(error);
      await expectation;
      expect(h.messages, isEmpty);
      expect(h.launches, isEmpty);
    },
  );
}
