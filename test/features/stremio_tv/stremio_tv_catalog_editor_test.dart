import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'dart:async';
import 'dart:convert';
import 'package:debrify/features/stremio_tv/application/stremio_tv_providers.dart';
import 'package:debrify/features/stremio_tv/data/stremio_tv_catalog_editor.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const movie = StremioMeta(id: 'tt123', name: 'Fixture', type: 'movie');

class Fixture {
  var current = true, accept = true;
  List<Map<String, dynamic>> rows = [];
  final writes = <Map<String, dynamic>>[];
  late final editor = StremioTvCatalogEditor(
    isCurrent: () => current,
    read: () async => rows,
    add: (value, guard) async {
      if (!guard()) return false;
      writes.add(value);
      return accept;
    },
    update: (value, guard) async {
      if (!guard()) return false;
      writes.add(value);
      return accept;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(ProfileRuntime.debugReset);
  test(
    'compatible options keep sorting, fallback labels and immutable snapshots',
    () async {
      final f = Fixture()
        ..rows = [
          {
            'id': 'b',
            'name': 'beta',
            'items': [{}],
          },
          {'id': 's', 'type': 'series'},
          {'id': 'a', 'name': 'Alpha'},
          {'id': 'missing'},
        ];
      final rows = (await f.editor.load('movie'))!;
      expect(rows.map((c) => c.id), ['missing', 'a', 'b']);
      expect(rows.first.name, 'Unknown');
      expect(rows.first.searchName, '');
      expect(rows.last.itemCount, 1);
      expect(() => rows.clear(), throwsUnsupportedError);
    },
  );
  test(
    'creation trims name, preserves payload and rejects duplicate names',
    () async {
      final f = Fixture();
      final result = await f.editor.createCatalogWithItem(
        catalogName: '  Weekend Movies  ',
        item: movie,
        canContinue: () => true,
      );
      expect(result!.createdNew, isTrue);
      expect(f.writes.single['name'], 'Weekend Movies');
      expect(f.writes.single['type'], 'movie');
      expect(f.writes.single['id'], startsWith('weekend_movies_'));
      expect(f.writes.single['items'], [movie.toJson()]);
      f.rows = f.writes.toList();
      expect(
        (await f.editor.createCatalogWithItem(
          catalogName: 'Weekend Movies',
          item: movie,
          canContinue: () => true,
        ))!.duplicate,
        isTrue,
      );
      expect(f.writes.length, 1);
    },
  );
  test(
    'append preserves catalog fields and detects an existing IMDb alias',
    () async {
      final f = Fixture()
        ..rows = [
          {'id': 'channel', 'name': 'Mine', 'custom': 'keep', 'items': []},
        ];
      expect(
        (await f.editor.addItemToCatalog(
          catalogId: 'channel',
          item: movie,
          canContinue: () => true,
        ))!.duplicate,
        isFalse,
      );
      expect(f.writes.single['custom'], 'keep');
      expect(f.writes.single['updatedAt'], isNotNull);
      f.rows = [
        {
          'id': 'channel',
          'name': 'Mine',
          'items': [
            {
              'id': 'addon-alias',
              'imdb_id': 'tt123',
              'type': 'movie',
              'name': 'Old',
            },
          ],
        },
      ];
      // Use the model serializer for the existing IMDb alias contract.
      f.rows.single['items'] = [
        const StremioMeta(
          id: 'addon-alias',
          imdbId: 'tt123',
          name: 'Old',
          type: 'movie',
        ).toJson(),
      ];
      expect(
        (await f.editor.addItemToCatalog(
          catalogId: 'channel',
          item: movie,
          canContinue: () => true,
        ))!.duplicate,
        isTrue,
      );
      expect(f.writes.length, 1);
    },
  );
  test(
    'rejected persistence and invalid inputs never report successful creation',
    () async {
      final f = Fixture()..accept = false;
      expect(
        await f.editor.createCatalogWithItem(
          catalogName: 'Mine',
          item: movie,
          canContinue: () => true,
        ),
        isNull,
      );
      expect(
        await f.editor.createCatalogWithItem(
          catalogName: '  ',
          item: movie,
          canContinue: () => true,
        ),
        isNull,
      );
      expect(
        await f.editor.addItemToCatalog(
          catalogId: 'missing',
          item: movie,
          canContinue: () => true,
        ),
        isNull,
      );
      expect(f.writes.length, 1);
    },
  );
  test(
    'actual preference budget refusal cannot report a created channel',
    () async {
      final origin = ProfileScope(
        profileId: 'origin',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeCommitted(origin);
      SharedPreferences.setMockInitialValues({});
      ProfilePreferenceBudget.debugEnforcedOverride = true;
      addTearDown(ProfilePreferenceBudget.debugReset);
      final container = ProviderContainer.test();
      final editor = container.read(stremioTvCatalogEditorFactoryProvider)();
      expect(
        await editor.createCatalogWithItem(
          catalogName: 'x' * ProfilePreferenceBudget.limitBytes,
          item: movie,
          canContinue: () => true,
        ),
        isNull,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          origin.preferenceKey('stremio_tv_local_catalogs_v1'),
        ),
        isNull,
      );
    },
  );
  for (final create in [false, true]) {
    for (final retire in ['none', 'view', 'profile']) {
      test(
        'real catalog persistence captures origin: create=$create retirement=$retire',
        () async {
          final origin = ProfileScope(
            profileId: 'origin',
            dataGeneration: 1,
            sessionEpoch: 1,
          );
          final other = ProfileScope(
            profileId: 'other',
            dataGeneration: 1,
            sessionEpoch: 2,
          );
          ProfileRuntime.debugReset();
          ProfileRuntime.initializeCommitted(origin);
          const key = 'stremio_tv_local_catalogs_v1';
          final original = jsonEncode([
            {'id': 'channel', 'name': 'Mine', 'type': 'movie', 'items': []},
          ]);
          SharedPreferences.setMockInitialValues({
            origin.preferenceKey(key): original,
            other.preferenceKey(key): '[]',
          });
          final container = ProviderContainer.test();
          final editor = container.read(
            stremioTvCatalogEditorFactoryProvider,
          )();
          final entered = Completer<void>(), release = Completer<void>();
          final snapshot = ProfilePreferences.captureMutationSnapshot((
            _,
          ) async {
            entered.complete();
            await release.future;
          });
          await entered.future;
          var current = true, completed = false;
          final pending = ProfileRuntime.withCapturedScope(
            other,
            () => create
                ? editor.createCatalogWithItem(
                    catalogName: 'New',
                    item: movie,
                    canContinue: () => current,
                  )
                : editor.addItemToCatalog(
                    catalogId: 'channel',
                    item: movie,
                    canContinue: () => current,
                  ),
          ).whenComplete(() => completed = true);
          await Future<void>.delayed(const Duration(milliseconds: 40));
          expect(completed, isFalse);
          if (retire == 'view') current = false;
          if (retire == 'profile') {
            ProfileSessionMemory.clearAll();
            ProfileRuntime.publish(other);
          }
          release.complete();
          await snapshot;
          final result = await pending;
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString(other.preferenceKey(key)), '[]');
          if (retire == 'none') {
            expect(result, isNotNull);
            final rows =
                jsonDecode(prefs.getString(origin.preferenceKey(key))!) as List;
            expect(rows.length, create ? 2 : 1);
            expect((rows.last['items'] as List).single['id'], 'tt123');
          } else {
            expect(result, isNull);
            expect(prefs.getString(origin.preferenceKey(key)), original);
          }
        },
      );
    }
  }
}
