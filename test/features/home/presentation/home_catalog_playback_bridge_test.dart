import 'dart:async';

import 'package:debrify/features/home/presentation/home_catalog_playback_bridge.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const selection = AdvancedSearchSelection(
  imdbId: 'custom-series:origin',
  isSeries: true,
  title: 'Show',
  season: 2,
  episode: 3,
);
const meta = PlaybackMeta.catalog(addonId: 'origin', season: 2, episode: 3);

class Harness {
  final pending = Completer<void>();
  final listeners = <VoidCallback>{};
  final events = <String>[];
  late BuildContext context;
  VoidCallback? picker;
  bool current = true;
  Object? metadataError;
  late final bridge = HomeCatalogPlaybackBridge(
    launch:
        (
          context, {
          required imdbId,
          required isMovie,
          season,
          episode,
          required meta,
          openSourcePicker,
        }) {
          expect(context, same(this.context));
          expect(imdbId, selection.imdbId);
          expect(isMovie, false);
          expect(season, 2);
          expect(episode, 3);
          expect(meta, same(buildMetadata));
          picker = openSourcePicker;
          events.add('launch');
          return pending.future;
        },
    addExternalListener: (listener) {
      listeners.add(listener);
      MainPageBridge.addExternalPlayerLaunchListener(listener);
    },
    removeExternalListener: (listener) {
      expect(listeners.remove(listener), true);
      MainPageBridge.removeExternalPlayerLaunchListener(listener);
      events.add('detach');
    },
  );
  PlaybackMeta get buildMetadata => meta;

  Future<void> mount(WidgetTester tester, {bool route = true}) async {
    final child = Builder(
      builder: (context) {
        this.context = context;
        return const SizedBox();
      },
    );
    await tester.pumpWidget(route ? MaterialApp(home: child) : child);
    addTearDown(() {
      for (final listener in listeners) {
        MainPageBridge.removeExternalPlayerLaunchListener(listener);
      }
    });
  }

  Future<void> play() => bridge.play(
    context,
    selection: selection,
    buildMeta: () {
      expect(listeners, hasLength(1));
      events.add('metadata');
      if (metadataError case final error?) throw error;
      return buildMetadata;
    },
    openSourcePicker: () => events.add('sources'),
    isCurrent: () => current,
    refreshBoundSources: () async => events.add('bound'),
    refreshAfterPlayback: () async => events.add('full'),
  );
}

void main() {
  testWidgets(
    'exact selection and lazy metadata reach player; await then refresh',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      final action = h.play();
      expect(h.events, ['metadata', 'launch']);
      h.picker!();
      expect(h.events.last, 'sources');
      h.pending.complete();
      await action;
      expect(h.events, ['metadata', 'launch', 'sources', 'detach', 'full']);
      expect(h.listeners, isEmpty);
    },
  );

  testWidgets('external launch refreshes badges and defers full refresh', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    final action = h.play();
    MainPageBridge.notifyExternalPlayerLaunched();
    expect(h.events, ['metadata', 'launch']);
    h.pending.complete();
    await action;
    expect(h.events, ['metadata', 'launch', 'detach', 'bound']);
    expect(h.listeners, isEmpty);
  });

  testWidgets('covered originating route defers full refresh', (tester) async {
    final h = Harness();
    await h.mount(tester);
    final action = h.play();
    unawaited(
      Navigator.of(
        h.context,
      ).push<void>(MaterialPageRoute(builder: (_) => const Scaffold())),
    );
    await tester.pumpAndSettle();
    h.pending.complete();
    await action;
    expect(h.events.last, 'bound');
    expect(h.listeners, isEmpty);
  });

  testWidgets('origin without a modal route refreshes badges only', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester, route: false);
    final action = h.play();
    h.pending.complete();
    await action;
    expect(h.events.last, 'bound');
  });

  for (final failure in ['metadata', 'launch']) {
    testWidgets('$failure failure propagates and detaches without refresh', (
      tester,
    ) async {
      final h = Harness();
      await h.mount(tester);
      final error = StateError(failure);
      if (failure == 'metadata') h.metadataError = error;
      final action = h.play();
      final assertion = expectLater(action, throwsA(same(error)));
      if (failure == 'launch') h.pending.completeError(error);
      await assertion;
      expect(h.events.last, 'detach');
      expect(h.events, isNot(contains('bound')));
      expect(h.events, isNot(contains('full')));
      expect(h.listeners, isEmpty);
    });
  }

  for (final retirement in ['profile', 'dispose']) {
    testWidgets(
      '$retirement retirement after launch skips feedback and detaches',
      (tester) async {
        final h = Harness();
        await h.mount(tester);
        final action = h.play();
        if (retirement == 'profile') {
          h.current = false;
        } else {
          await tester.pumpWidget(const SizedBox());
        }
        h.pending.complete();
        await action;
        expect(h.events, ['metadata', 'launch', 'detach']);
        expect(h.listeners, isEmpty);
      },
    );

    testWidgets('$retirement retirement before launch performs no work', (
      tester,
    ) async {
      final h = Harness();
      await h.mount(tester);
      if (retirement == 'profile') {
        h.current = false;
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await h.play();
      expect(h.events, isEmpty);
      expect(h.listeners, isEmpty);
    });
  }
}
