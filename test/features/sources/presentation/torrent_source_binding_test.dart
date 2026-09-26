import 'dart:async';

import 'package:debrify/features/sources/presentation/torrent_source_binding.dart';
import 'package:debrify/models/series_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const pin = SeriesSource(
  torrentHash: 'hash',
  torrentName: 'Source',
  debridService: 'rd',
  debridTorrentId: '',
  boundAt: 1,
);

class Fixture {
  late BuildContext context;
  final events = <String>[];
  bool active = true;
  String imdb = 'tt1';
  Future<String?> Function() pick = () async => 'debrid';
  Future<({bool ready, String? failureMessage})> Function(String) prepare =
      (_) async => (ready: true, failureMessage: null);
  Future<bool> Function(SeriesSource) save = (_) async => true;
  VoidCallback onDismiss = () {};
  SeriesSource? written;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
  }

  Future<bool> run() => presentTorrentSourceBinding(
    context,
    imdbId: imdb,
    cancelledProvider: 'cancelled',
    canContinue: () => active,
    pickProvider: () {
      events.add('pick');
      return pick();
    },
    showLoading: (provider) {
      events.add('load:$provider');
      return () {
        events.add('dismiss');
        onDismiss();
      };
    },
    prepare: (provider) {
      events.add('prepare:$provider');
      return prepare(provider);
    },
    describe: (provider) {
      events.add('describe:$provider');
      return pin;
    },
    save: (source) {
      events.add('save');
      written = source;
      return save(source);
    },
    providerLabel: (provider) {
      events.add('label:$provider');
      return 'Real Debrid';
    },
  );
}

void main() {
  for (final reason in ['retired', 'missing identity']) {
    testWidgets('$reason stops before provider selection', (tester) async {
      final f = Fixture();
      if (reason == 'retired') f.active = false;
      if (reason == 'missing identity') f.imdb = '';
      await f.mount(tester);
      expect(await f.run(), isFalse);
      expect(f.events, isEmpty);
    });
  }

  for (final choice in <String?>['cancelled', null]) {
    testWidgets('provider choice $choice creates no loader', (tester) async {
      final f = Fixture()..pick = () async => choice;
      await f.mount(tester);
      expect(await f.run(), isFalse);
      await tester.pump();
      expect(f.events, ['pick']);
      expect(
        find.text('No debrid provider configured. Add one in Settings.'),
        choice == null ? findsOneWidget : findsNothing,
      );
    });
  }

  for (final closeView in [false, true]) {
    testWidgets('retirement during provider choice, closed=$closeView', (
      tester,
    ) async {
      final f = Fixture();
      final picking = Completer<String?>();
      f.pick = () => picking.future;
      await f.mount(tester);
      final work = f.run();
      if (closeView) {
        await tester.pumpWidget(const SizedBox());
      } else {
        f.active = false;
      }
      picking.complete('debrid');
      expect(await work, isFalse);
      expect(f.events, ['pick']);
    });

    testWidgets(
      'retirement during acquisition still dismisses loader, closed=$closeView',
      (tester) async {
        final f = Fixture();
        final preparation = Completer<({bool ready, String? failureMessage})>();
        f.prepare = (_) => preparation.future;
        await f.mount(tester);
        final work = f.run();
        await tester.pump();
        if (closeView) {
          await tester.pumpWidget(const SizedBox());
        } else {
          f.active = false;
        }
        preparation.complete((ready: true, failureMessage: null));
        expect(await work, isFalse);
        expect(f.events, ['pick', 'load:debrid', 'prepare:debrid', 'dismiss']);
        expect(f.written, isNull);
      },
    );
  }

  for (final accepted in [false, true]) {
    testWidgets('loader closes before descriptor/save, accepted=$accepted', (
      tester,
    ) async {
      final f = Fixture()..save = (_) async => accepted;
      await f.mount(tester);
      expect(await f.run(), accepted);
      await tester.pump();
      expect(f.events, [
        'pick',
        'load:debrid',
        'prepare:debrid',
        'dismiss',
        'describe:debrid',
        'save',
      ]);
      expect(f.written, same(pin));
      expect(
        find.text('Source pinned for instant playback.'),
        accepted ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('dismissal retirement is checked before writing', (tester) async {
    final f = Fixture();
    f.onDismiss = () => f.active = false;
    await f.mount(tester);
    expect(await f.run(), isFalse);
    expect(f.events.last, 'dismiss');
    expect(f.written, isNull);
  });

  testWidgets('unexpected preparation failure still releases loader', (
    tester,
  ) async {
    final error = StateError('Preparation failed');
    final f = Fixture()..prepare = (_) async => throw error;
    await f.mount(tester);
    await expectLater(f.run(), throwsA(same(error)));
    expect(f.events.last, 'dismiss');
    expect(f.written, isNull);
  });

  for (final message in <String?>[null, 'Still downloading']) {
    testWidgets('not-ready feedback retains specific/fallback message=$message', (
      tester,
    ) async {
      final f = Fixture()
        ..prepare = (_) async => (ready: false, failureMessage: message);
      await f.mount(tester);
      expect(await f.run(), isFalse);
      await tester.pump();
      expect(
        find.text(
          message ??
              "That source isn't instantly playable on Real Debrid — pick a cached one.",
        ),
        findsOneWidget,
      );
      expect(f.events.contains('label:debrid'), message == null);
      expect(f.written, isNull);
    });
  }

  testWidgets(
    'save completing after retirement retains result without feedback',
    (tester) async {
      final f = Fixture();
      final saving = Completer<bool>();
      f.save = (_) => saving.future;
      await f.mount(tester);
      final work = f.run();
      await tester.pump();
      f.active = false;
      saving.complete(true);
      expect(await work, isTrue);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}
