import 'dart:async';

import 'package:debrify/features/sources/presentation/local_source_picker.dart';
import 'package:debrify/features/sources/presentation/local_source_picker_composition.dart';
import 'package:debrify/features/sources/presentation/source_binding_bridge.dart';
import 'package:debrify/models/series_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const selected = SeriesSource(
  torrentHash: 'fixture',
  torrentName: 'Fixture',
  debridService: SeriesSource.localService,
  debridTorrentId: '/fixture/movie.mp4',
  boundAt: 1,
  localKind: SeriesSource.localKindMovieFile,
);

class Fixture {
  late BuildContext page;
  late SourceBindingBridge bridge;
  bool active = true;
  bool accepted = true;
  String? disabledReason;
  final calls = <String>[];
  BuildContext? receivedContext;
  bool Function()? receivedGuard;
  SeriesSource? written;
  Future<SeriesSource?> Function() pick = () async => selected;

  bool _isActive() => active;
  late final guard = _isActive;
  LocalSourcePicker get picker => LocalSourcePicker(
    androidFolderSelection: false,
    disabledReason: disabledReason,
    file: (context, {canContinue}) {
      receivedContext = context;
      receivedGuard = canContinue;
      calls.add('file');
      return pick();
    },
    movieFolder: (context, {required title, year, canContinue}) {
      receivedContext = context;
      receivedGuard = canContinue;
      calls.add('movie:$title:$year');
      return pick();
    },
    seriesFolder: (context, {required title, canContinue}) {
      receivedContext = context;
      receivedGuard = canContinue;
      calls.add('series:$title');
      return pick();
    },
  );

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [localSourcePickerProvider.overrideWithValue(picker)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            page = context;
            bridge = ref.read(sourceBindingBridgeProvider);
            return const Scaffold();
          },
        ),
      ),
    ),
  );

  Future<bool> bind({bool movie = false, String imdbId = 'tt-fixture'}) =>
      bridge.pinLocal(
        page,
        imdbId: imdbId,
        isMovie: movie,
        title: 'Fixture',
        year: '2020',
        canContinue: guard,
        saveBinding: (source) async {
          calls.add('save');
          written = source;
          return accepted;
        },
      );
}

void main() {
  for (final mode in ['file', 'folder', 'series']) {
    testWidgets('picker override reaches production local binding: $mode', (
      tester,
    ) async {
      final f = Fixture();
      await f.mount(tester);
      final pending = f.bind(movie: mode != 'series');
      if (mode != 'series') {
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(mode == 'file' ? 'Pick Video File' : 'Pick Folder'),
        );
      }
      await tester.pumpAndSettle();
      expect(await pending, isTrue);
      expect(f.receivedContext, same(f.page));
      expect(f.receivedGuard, same(f.guard));
      expect(f.written, same(selected));
      expect(f.calls, [
        switch (mode) {
          'file' => 'file',
          'folder' => 'movie:Fixture:2020',
          _ => 'series:Fixture',
        },
        'save',
      ]);
      expect(find.text('Local source pinned.'), findsOneWidget);
    });
  }

  test('nested picker scopes do not replace parent or sibling bridges', () {
    final parent = ProviderContainer.test();
    final original = parent.read(sourceBindingBridgeProvider);
    final available = Fixture();
    final disabled = Fixture()..disabledReason = 'Unavailable fixture';
    final first = ProviderContainer.test(
      parent: parent,
      overrides: [localSourcePickerProvider.overrideWithValue(disabled.picker)],
    );
    final second = ProviderContainer.test(
      parent: parent,
      overrides: [
        localSourcePickerProvider.overrideWithValue(available.picker),
      ],
    );
    expect(
      first.read(sourceBindingBridgeProvider).localBindingAvailable,
      isFalse,
    );
    expect(
      second.read(sourceBindingBridgeProvider).localBindingAvailable,
      isTrue,
    );
    expect(first.read(sourceBindingBridgeProvider), isNot(same(original)));
    expect(second.read(sourceBindingBridgeProvider), isNot(same(original)));
    expect(parent.read(sourceBindingBridgeProvider), same(original));
    expect(parent.read(localSourcePickerProvider), same(localSourcePicker));
    first.dispose();
    expect(
      second.read(sourceBindingBridgeProvider).localBindingAvailable,
      isTrue,
    );
    expect(parent.read(sourceBindingBridgeProvider), same(original));
    expect(available.calls, isEmpty);
    expect(disabled.calls, isEmpty);
  });

  testWidgets('disabled scoped picker controls availability and feedback', (
    tester,
  ) async {
    final f = Fixture()..disabledReason = 'Unavailable fixture';
    await f.mount(tester);
    expect(f.bridge.localBindingAvailable, isFalse);
    expect(await f.bind(), isFalse);
    await tester.pump();
    expect(find.text('Unavailable fixture'), findsOneWidget);
    expect(f.calls, isEmpty);
  });

  for (final stage in [
    'entry',
    'pending',
    'missing_identity',
    'rejected_write',
  ]) {
    testWidgets('injected local action retains guards: $stage', (tester) async {
      final f = Fixture();
      final response = Completer<SeriesSource?>();
      if (stage == 'entry') f.active = false;
      if (stage == 'pending') f.pick = () => response.future;
      if (stage == 'rejected_write') f.accepted = false;
      await f.mount(tester);
      final pending = f.bind(
        imdbId: stage == 'missing_identity' ? '' : 'tt-fixture',
      );
      if (stage == 'pending') {
        await tester.pump();
        f.active = false;
        response.complete(selected);
      }
      expect(await pending, isFalse);
      await tester.pump();
      expect(f.written, stage == 'rejected_write' ? same(selected) : isNull);
      expect(f.calls, switch (stage) {
        'entry' || 'missing_identity' => isEmpty,
        'pending' => ['series:Fixture'],
        _ => ['series:Fixture', 'save'],
      });
      expect(find.text('Local source pinned.'), findsNothing);
    });
  }
}
