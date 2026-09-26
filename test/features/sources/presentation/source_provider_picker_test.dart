import 'dart:async';

import 'package:debrify/features/sources/presentation/source_provider_picker.dart';
import 'package:debrify/widgets/provider_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Fixture {
  late BuildContext context;
  bool active = true;
  Future<(List<String>, String?)?> Function() load = () async =>
      (['torbox', 'debrid'], null);
  final options = <String>[];
  final writes = <String>[];
  Future<void> Function(String) persist = (_) async {};

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

  Future<String?> run({bool guarded = true}) => pickSourceProvider(
    context,
    cancelledProvider: 'cancelled',
    loadConfiguration: load,
    canContinue: guarded ? () => active : null,
    optionFor: (provider) {
      options.add(provider);
      return ProviderPickerOption(
        id: provider,
        label: provider,
        gradient: const [Colors.blue, Colors.blueAccent],
        icon: Icons.movie,
      );
    },
    remember: (provider) {
      writes.add(provider);
      return persist(provider);
    },
  );
}

void main() {
  for (final (configuration, expected) in <((List<String>, String?)?, String?)>[
    (null, 'cancelled'),
    ((<String>[], null), null),
    ((['only'], null), 'only'),
    ((['first', 'preferred'], 'preferred'), 'preferred'),
  ]) {
    testWidgets(
      'configuration $configuration returns $expected without dialog',
      (tester) async {
        final f = Fixture()..load = () async => configuration;
        await f.mount(tester);
        expect(await f.run(), expected);
        expect(f.options, isEmpty);
        expect(f.writes, isEmpty);
        expect(find.byType(Dialog), findsNothing);
      },
    );
  }

  testWidgets('retirement during configuration rejects even the default', (
    tester,
  ) async {
    final f = Fixture();
    final loading = Completer<(List<String>, String?)?>();
    f.load = () => loading.future;
    await f.mount(tester);
    final work = f.run();
    f.active = false;
    loading.complete((['first', 'preferred'], 'preferred'));
    expect(await work, 'cancelled');
    expect(f.options, isEmpty);
  });

  for (final guarded in [false, true]) {
    testWidgets(
      'closed view preserves guarded/default fast path, guarded=$guarded',
      (tester) async {
        final f = Fixture();
        final loading = Completer<(List<String>, String?)?>();
        f.load = () => loading.future;
        await f.mount(tester);
        final work = f.run(guarded: guarded);
        await tester.pumpWidget(const SizedBox());
        loading.complete((['first', 'preferred'], 'preferred'));
        expect(await work, guarded ? 'cancelled' : 'preferred');
        expect(f.options, isEmpty);
      },
    );
  }

  for (final remember in [false, true]) {
    testWidgets('real dialog preserves order and remember=$remember', (
      tester,
    ) async {
      final f = Fixture();
      await f.mount(tester);
      final work = f.run();
      await tester.pumpAndSettle();
      expect(f.options, ['torbox', 'debrid']);
      if (remember) {
        await tester.tap(find.text('Remember my choice'));
        await tester.pump();
      }
      await tester.tap(find.text('debrid'));
      await tester.pumpAndSettle();
      expect(await work, 'debrid');
      expect(f.writes, remember ? ['debrid'] : isEmpty);
    });
  }

  testWidgets('dismissing dialog returns cancellation without writing', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    final work = f.run();
    await tester.pumpAndSettle();
    Navigator.of(f.context).pop();
    await tester.pumpAndSettle();
    expect(await work, 'cancelled');
    expect(f.writes, isEmpty);
  });

  testWidgets('retired remembered selection does not invoke writer', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    final work = f.run();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remember my choice'));
    await tester.pump();
    f.active = false;
    await tester.tap(find.text('torbox'));
    await tester.pumpAndSettle();
    expect(await work, 'cancelled');
    expect(f.writes, isEmpty);
  });

  testWidgets('remember is awaited and caller retains post-write guard', (
    tester,
  ) async {
    final f = Fixture();
    final saving = Completer<void>();
    f.persist = (_) => saving.future;
    await f.mount(tester);
    var finished = false;
    final work = f.run().then((value) {
      finished = true;
      return value;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remember my choice'));
    await tester.pump();
    await tester.tap(find.text('torbox'));
    await tester.pumpAndSettle();
    expect(f.writes, ['torbox']);
    expect(finished, isFalse);
    f.active = false;
    saving.complete();
    expect(await work, 'torbox');
  });
}
