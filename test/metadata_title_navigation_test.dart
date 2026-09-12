import 'dart:async';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/metadata_title_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const native = StremioMeta(id: 'tmdb:1', type: 'movie', name: 'Title');
  const resolved = StremioMeta(id: 'tt1234567', type: 'movie', name: 'Title');

  Future<void> mount(
    WidgetTester tester,
    StremioMeta item,
    ValueChanged<StremioMeta> onOpen,
    Future<StremioMeta> Function(StremioMeta) resolve,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                unawaited(
                  openMetadataTitle(context, item, onOpen, resolve: resolve),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
  }

  testWidgets('existing IMDb titles retain their immediate navigation path', (
    tester,
  ) async {
    StremioMeta? opened;
    var reads = 0;
    await mount(tester, resolved, (item) => opened = item, (_) async {
      reads++;
      return native;
    });
    expect(opened, same(resolved));
    expect(reads, 0);
    expect(find.text('Loading title…'), findsNothing);
  });

  testWidgets('native selection resolves only on open and displays progress', (
    tester,
  ) async {
    final pending = Completer<StremioMeta>();
    StremioMeta? opened;
    await mount(tester, native, (item) => opened = item, (_) => pending.future);
    expect(opened, isNull);
    expect(find.text('Loading title…'), findsOneWidget);
    pending.complete(resolved);
    await tester.pumpAndSettle();
    expect(opened, same(resolved));
    expect(find.text('Loading title…'), findsNothing);
  });

  testWidgets('leaving the source page discards a late identity result', (
    tester,
  ) async {
    final pending = Completer<StremioMeta>();
    var opens = 0;
    await mount(tester, native, (_) => opens++, (_) => pending.future);
    await tester.pumpWidget(const SizedBox());
    pending.complete(resolved);
    await tester.pumpAndSettle();
    expect(opens, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable identity keeps the native title usable', (
    tester,
  ) async {
    StremioMeta? opened;
    final pending = Completer<StremioMeta>();
    await mount(tester, native, (item) => opened = item, (_) => pending.future);
    pending.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(opened, same(native));
    expect(tester.takeException(), isNull);
  });

  for (final newerFinishesFirst in [false, true]) {
    testWidgets(
      'overlapping lookups keep the latest notice (newer finishes first: $newerFinishesFirst)',
      (tester) async {
        final first = Completer<StremioMeta>();
        final second = Completer<StremioMeta>();
        var reads = 0;
        await mount(tester, native, (_) {}, (_) {
          return reads++ == 0 ? first.future : second.future;
        });
        await tester.tap(find.text('Open'));
        await tester.pump();
        expect(reads, 2);
        expect(find.text('Loading title…'), findsOneWidget);

        final early = newerFinishesFirst ? second : first;
        final late = newerFinishesFirst ? first : second;
        early.complete(resolved);
        await tester.pumpAndSettle();
        expect(
          find.text('Loading title…'),
          newerFinishesFirst ? findsNothing : findsOneWidget,
        );
        late.complete(resolved);
        await tester.pumpAndSettle();
        expect(find.text('Loading title…'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
