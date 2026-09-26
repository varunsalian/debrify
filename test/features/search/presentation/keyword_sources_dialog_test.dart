import 'dart:async';

import 'package:debrify/features/search/application/keyword_sources_controller.dart';
import 'package:debrify/features/search/application/keyword_sources_dependencies.dart';
import 'package:debrify/features/search/data/keyword_sources_repository.dart';
import 'package:debrify/features/search/models/keyword_source.dart';
import 'package:debrify/features/search/models/search_session.dart';
import 'package:debrify/features/search/presentation/keyword_sources_dialog.dart';
import 'package:debrify/features/search/presentation/source_toggle_row.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSources implements KeywordSourcesRepository {
  @override
  bool isCurrent = true;
  var choices = [
    const KeywordSource(
      id: 'registry',
      label: 'Registry source',
      enabled: true,
    ),
    const KeywordSource(id: 'custom', label: 'Custom indexer', enabled: false),
  ];
  var reads = 0;
  final writes = <(String, bool)>[];
  Future<List<KeywordSource>> Function()? fetch;
  Future<void> Function()? save;
  @override
  Future<List<KeywordSource>> load() async {
    reads++;
    return fetch == null ? choices : fetch!();
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    writes.add((id, enabled));
    choices = [
      for (final s in choices) s.id == id ? s.withEnabled(enabled) : s,
    ];
    await save?.call();
  }
}

void main() {
  late FakeSources repository;
  late SearchSession session;
  late ProviderContainer container;
  late BuildContext host;
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    repository = FakeSources();
    session = SearchSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  Future<void> mount(WidgetTester tester, {bool settles = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keywordSourcesRepositoryProvider.overrideWith(
            (ref, key) => repository,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => KeywordSourcesDialog(session: session),
                ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(host);
    await tester.tap(find.text('Open'));
    if (settles) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
    'engine defaults, Select, bulk writes and reopening retain choices',
    (tester) async {
      await mount(tester);
      expect(
        tester
            .widgetList<SourceToggleRow>(find.byType(SourceToggleRow))
            .map((s) => s.enabled),
        [true, false],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(repository.writes, [('registry', false)]);
      await tester.tap(find.text('Enable all'));
      await tester.pumpAndSettle();
      expect(repository.writes, [
        ('registry', false),
        ('registry', true),
        ('custom', true),
      ]);
      await tester.tap(find.text('Custom indexer'));
      await tester.pumpAndSettle();
      expect(repository.writes.last, ('custom', false));
      expect(repository.reads, 1);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(container.exists(keywordSourcesProvider(session)), isFalse);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(repository.reads, 2);
      expect(
        tester
            .widgetList<SourceToggleRow>(find.byType(SourceToggleRow))
            .map((s) => s.enabled),
        [true, false],
      );
      expect(repository.writes.length, 4);
    },
  );

  testWidgets('pending writes are handled after dismissal without retry', (
    tester,
  ) async {
    final saved = Completer<void>();
    repository.save = () => saved.future;
    await mount(tester);
    await tester.tap(find.text('Disable all'));
    await tester.pump();
    expect(repository.writes, [('registry', false), ('custom', false)]);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    saved.completeError(StateError('storage unavailable'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(repository.writes.length, 2);
    expect(container.exists(keywordSourcesProvider(session)), isFalse);
  });

  testWidgets('profile replacement hides choices and rejects a late load', (
    tester,
  ) async {
    final pending = Completer<List<KeywordSource>>();
    repository.fetch = () => pending.future;
    await mount(tester, settles: false);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'next', dataGeneration: 1, sessionEpoch: 2),
    );
    await tester.pump();
    pending.complete(repository.choices);
    await tester.pump();
    expect(find.text('Registry source'), findsNothing);
    expect(container.read(keywordSourcesProvider(session)), isNull);
    expect(repository.reads, 1);
    expect(repository.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty engines show the existing message without bulk actions', (
    tester,
  ) async {
    repository.choices = [];
    await mount(tester);
    expect(find.text('No search sources installed.'), findsOneWidget);
    expect(find.text('Enable all'), findsNothing);
    expect(find.text('Disable all'), findsNothing);
  });

  testWidgets(
    'failed loading keeps its presentation without an automatic retry',
    (tester) async {
      repository.fetch = () async => throw StateError('unavailable');
      await mount(tester, settles: false);
      await tester.pump(const Duration(seconds: 20));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repository.reads, 1);
      expect(repository.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
