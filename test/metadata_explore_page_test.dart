import 'dart:async';
import 'dart:io';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:debrify/services/metadata_explore_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_test/flutter_test.dart';

class ExploreService extends MetadataExploreService {
  int calls = 0;
  late Future<MetadataExploreData> Function(int) respond;
  @override
  Future<MetadataExploreData> details(
    StremioMeta item,
    MetadataPreferences prefs,
  ) => respond(++calls);
}

const loaded = MetadataExploreData(
  people: [
    {'id': 3, 'name': 'Person'},
  ],
);
void main() {
  setUp(ProfileRuntime.debugReset);
  tearDown(ProfileRuntime.debugReset);
  Future<void> open(WidgetTester tester, ExploreService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MetadataExplorePage(
          item: const StremioMeta(id: 'tmdb:1', type: 'movie', name: 'Movie'),
          preferences: MetadataPreferences(features: {MetadataFeature.people}),
          onOpen: (_) {},
          service: service,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('socket failure recovers automatically after one second', (
    tester,
  ) async {
    final service = ExploreService()
      ..respond = (n) async {
        if (n == 1) throw const SocketException('Disconnected');
        return loaded;
      };
    await open(tester, service);
    expect(service.calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Could not load. Retry'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(service.calls, 2);
    expect(find.text('Person'), findsOneWidget);
  });
  testWidgets('stops after two retries and permits a manual retry', (
    tester,
  ) async {
    final service = ExploreService()
      ..respond = (_) async => throw const SocketException('Disconnected');
    await open(tester, service);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(service.calls, 3);
    expect(find.text('Could not load. Retry'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(service.calls, 3);
    service.respond = (_) async => loaded;
    await tester.tap(find.text('Could not load. Retry'));
    await tester.pumpAndSettle();
    expect(service.calls, 4);
    expect(find.text('Person'), findsOneWidget);
  });
  testWidgets(
    'partial content stays visible through retries and full failure',
    (tester) async {
      final service = ExploreService()
        ..respond = (n) async {
          if (n > 1) throw const SocketException('Disconnected');
          return const MetadataExploreData(
            people: [
              {'id': 3, 'name': 'Person'},
            ],
            unavailable: {MetadataFeature.franchises},
          );
        };
      await open(tester, service);
      expect(find.text('Person'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Person'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Person'), findsOneWidget);
      expect(find.text('Some sections could not load. Retry'), findsOneWidget);
    },
  );
  testWidgets('disposal cancels a pending retry', (tester) async {
    final service = ExploreService()
      ..respond = (_) async => throw const SocketException('Disconnected');
    await open(tester, service);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(service.calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('profile change cancels retry and rejects an in-flight result', (
    tester,
  ) async {
    final pending = Completer<MetadataExploreData>();
    final service = ExploreService()
      ..respond = (n) async {
        if (n == 1) throw const SocketException('Disconnected');
        return pending.future;
      };
    await open(tester, service);
    await tester.pump(const Duration(seconds: 1));
    ProfileRuntime.scope.value = ProfileScope(
      profileId: 'other',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    await tester.pump();
    pending.complete(loaded);
    await tester.pump(const Duration(seconds: 5));
    expect(service.calls, 2);
    expect(find.text('Person'), findsNothing);
    expect(
      find.text('Profile changed. Go back to browse your current profile.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('Franchise shortcut focuses and activates its first title', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.initializeLegacy();
    final service = ExploreService()
      ..respond = (_) async => MetadataExploreData(
        franchiseName: 'Movie collection',
        franchise: List.generate(
          30,
          (i) => StremioMeta(
            id: 'tt${133093 + i}',
            type: 'movie',
            name: 'Movie $i',
          ),
        ),
      );
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MetadataExplorePage(
          item: const StremioMeta(id: 'tmdb:1', type: 'movie', name: 'Movie'),
          preferences: MetadataPreferences(
            features: {MetadataFeature.franchises},
          ),
          isTelevision: true,
          onOpen: (item) => opened.add(item.id),
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rail = tester.widget<ListView>(find.byType(ListView));
    rail.controller!.jumpTo(rail.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Movie 0'), findsNothing);
    final shortcut = find.widgetWithText(OutlinedButton, 'Franchise');
    Focus.of(tester.element(find.text('Franchise'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(shortcut, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, ['tt133093']);
    expect(tester.takeException(), isNull);
  });
}
