import 'dart:async';
import 'package:debrify/features/home/application/home_tracker_authentication_dependencies.dart';
import 'package:debrify/features/home/models/home_tracker_authentication.dart';

import 'package:debrify/features/search/application/lists_search_controller.dart';
import 'package:debrify/features/search/application/lists_search_dependencies.dart';
import 'package:debrify/features/search/models/search_session.dart';
import 'package:debrify/features/search/models/search_mode.dart';
import 'package:debrify/features/search/presentation/search_mode_toggle.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/golden_harness.dart' show disableRuntimeFonts;
import '../fakes/fake_lists_search_repository.dart';

const choice = MdblistListChoice(id: 9876, name: 'Refactor list', itemCount: 3);
typedef Result = MdblistResult<List<MdblistListChoice>>;

void main() {
  late FakeListsSearchRepository repository;
  late GlobalKey<NavigatorState> navigator;
  late List<SearchSession> sessions;
  late StateSetter rebuildScreen;
  late ProviderContainer container;
  late bool showScreen;
  HomeTrackerAuthReader? mdblistAuthentication;

  setUp(() {
    disableRuntimeFonts();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({'mdblist_api_key': 'test-key'});
    MainPageBridge.setActiveTab('search');
    StremioService.instance.invalidateCache();
    repository = FakeListsSearchRepository();
    repository.fetch = (_) async => const MdblistResult.success([choice]);
    navigator = GlobalKey<NavigatorState>();
    sessions = [];
    showScreen = true;
    mdblistAuthentication = null;
  });

  tearDown(() {
    MainPageBridge.setActiveTab(null);
    StremioService.instance.invalidateCache();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  Future<void> drive(
    WidgetTester tester,
    FutureOr<void> Function() action,
  ) async {
    await tester.runAsync(
      () => http.runWithClient(() async {
        await action();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }, () => MockClient((_) async => http.Response('{}', 404))),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await drive(
      tester,
      () => tester.pumpWidget(
        ProviderScope(
          overrides: [
            if (mdblistAuthentication != null)
              homeTrackerAuthReaderProvider.overrideWith(
                (ref, session) => session.tracker == HomeTracker.mdblist
                    ? mdblistAuthentication!
                    : () async => false,
              ),
            listsSearchRepositoryProvider.overrideWith((ref, session) {
              sessions.add(session);
              return repository;
            }),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuildScreen = setState;
                return showScreen
                    ? SearchScreen(searchMode: true)
                    : const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(SearchScreen)),
    );
    expect(sessions, hasLength(1));
    expect(repository.queries, isEmpty);
    // The real auth availability read is asynchronous (including cold vault
    // setup). Wait for its observable result rather than assuming one frame.
    for (var i = 0; i < 20 && find.text('Lists').evaluate().isEmpty; i++) {
      await drive(tester, () {});
    }
    expect(find.text('Lists'), findsOneWidget);
    await tester.tap(find.text('Lists'));
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await drive(tester, () {
      tester
          .widget<TvTextField>(find.byType(TvTextField).first)
          .onSubmitted
          ?.call(query);
    });
  }

  testWidgets(
    'repeated screen visits dispose old families without replaying search',
    (tester) async {
      await mount(tester);
      await submit(tester, 'movies');
      for (var visit = 0; visit < 3; visit++) {
        final outgoing = sessions.last;
        rebuildScreen(() => showScreen = false);
        await tester.pump();
        await tester.pump();
        expect(container.exists(listsSearchProvider(outgoing)), isFalse);
        expect(
          container.exists(listsSearchRepositoryProvider(outgoing)),
          isFalse,
        );
        await drive(tester, () => rebuildScreen(() => showScreen = true));
        expect(sessions, hasLength(visit + 2));
        expect(
          container.read(listsSearchProvider(sessions.last)).query,
          isEmpty,
        );
      }
      expect(repository.queries, ['movies']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mode changes retain an accepted Lists search without fetching twice',
    (tester) async {
      await mount(tester);
      await submit(tester, 'movies');
      await drive(tester, () => tester.tap(find.text('Catalog').first));
      expect(
        tester.widget<SearchModeToggle>(find.byType(SearchModeToggle)).mode,
        SearchMode.catalog,
      );
      await drive(tester, () => tester.tap(find.text('Lists')));
      expect(find.text('Refactor list'), findsOneWidget);
      expect(repository.queries, ['movies']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'production Lists search survives rebuild, pushed consumer and dialog',
    (tester) async {
      await mount(tester);
      await submit(tester, 'movies');
      expect(repository.queries, ['movies']);
      expect(find.text('Refactor list'), findsOneWidget);
      rebuildScreen(() {});
      await tester.pump();
      expect(find.text('Refactor list'), findsOneWidget);
      expect(sessions, hasLength(1));
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Text(
                  'route:${ref.watch(listsSearchProvider(sessions.single)).query}',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('route:movies'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(SearchScreen)),
          builder: (_) => Consumer(
            builder: (context, ref, _) => AlertDialog(
              content: Text(
                'dialog:${ref.watch(listsSearchProvider(sessions.single)).query}',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('dialog:movies'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Refactor list'), findsOneWidget);
      expect(repository.queries, ['movies']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'covered Search accepts one completion and retains it on return',
    (tester) async {
      final pending = Completer<Result>();
      repository.fetch = (_) => pending.future;
      await mount(tester);
      await submit(tester, 'movies');
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await drive(
        tester,
        () => pending.complete(const MdblistResult.success([choice])),
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Refactor list'), findsOneWidget);
      expect(repository.queries, ['movies']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('clearing the production field rejects late Lists results', (
    tester,
  ) async {
    final pending = Completer<Result>();
    repository.fetch = (_) => pending.future;
    await mount(tester);
    await submit(tester, 'movies');
    await drive(
      tester,
      () => tester.enterText(find.byType(TextField).first, ''),
    );
    await drive(
      tester,
      () => pending.complete(const MdblistResult.success([choice])),
    );
    expect(find.text('Refactor list'), findsNothing);
    expect(container.read(listsSearchProvider(sessions.single)).query, isEmpty);
    expect(
      container.read(listsSearchProvider(sessions.single)).searching,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'disconnect falls back to Catalog; reconnect searches retained text once',
    (tester) async {
      final pending = Completer<Result>();
      repository.fetch = (_) => pending.future;
      await mount(tester);
      await submit(tester, 'movies');
      await drive(tester, () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('mdblist_api_key');
        MainPageBridge.notifyIntegrationChanged();
      });
      expect(
        tester.widget<SearchModeToggle>(find.byType(SearchModeToggle)).mode,
        SearchMode.catalog,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'movies',
      );
      expect(
        container.read(listsSearchProvider(sessions.single)).query,
        isEmpty,
      );
      await drive(
        tester,
        () => pending.complete(const MdblistResult.success([choice])),
      );
      expect(
        container.read(listsSearchProvider(sessions.single)).results,
        isEmpty,
      );
      repository.fetch = (_) async => const MdblistResult.success([choice]);
      await drive(tester, () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('mdblist_api_key', 'test-key');
        MainPageBridge.notifyIntegrationChanged();
      });
      await drive(tester, () => tester.tap(find.text('Lists')));
      expect(find.text('Refactor list'), findsOneWidget);
      expect(repository.queries, ['movies', 'movies']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('older authentication cannot undo a newer Lists disconnect', (
    tester,
  ) async {
    final older = Completer<bool>();
    var reads = 0;
    mdblistAuthentication = () {
      reads++;
      return reads == 1
          ? Future.value(true)
          : reads == 2
          ? older.future
          : Future.value(false);
    };
    await mount(tester);
    await submit(tester, 'movies');
    await drive(tester, MainPageBridge.notifyIntegrationChanged);
    expect(reads, 2);
    await drive(tester, MainPageBridge.notifyIntegrationChanged);
    expect(reads, 3);
    expect(find.text('Lists'), findsNothing);
    await drive(tester, () => older.complete(true));
    expect(find.text('Lists'), findsNothing);
    expect(
      tester.widget<SearchModeToggle>(find.byType(SearchModeToggle)).mode,
      SearchMode.catalog,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'movies',
    );
    expect(
      container.read(listsSearchProvider(sessions.single)).results,
      isEmpty,
    );
    expect(repository.queries, ['movies']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'outgoing profile clears retained state before its route disposes',
    (tester) async {
      final pending = Completer<Result>();
      repository.fetch = (_) => pending.future;
      await mount(tester);
      await submit(tester, 'movies');
      repository.isCurrent = false;
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'incoming', dataGeneration: 1, sessionEpoch: 2),
      );
      await tester.pump();
      expect(
        container.read(listsSearchProvider(sessions.single)).query,
        isEmpty,
      );
      await drive(
        tester,
        () => pending.complete(const MdblistResult.success([choice])),
      );
      expect(find.text('Refactor list'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
