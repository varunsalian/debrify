import 'dart:convert';
import 'package:debrify/features/home/application/home_bound_counts_dependencies.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ProfileRuntime.debugReset);
  tearDown(ProfileRuntime.debugReset);
  const source = SeriesSource(
    torrentHash: 'hash',
    torrentName: 'fixture',
    debridService: 'rd',
    debridTorrentId: '1',
    boundAt: 1,
  );
  test(
    'default reader retains legacy migration in the originating profile and rejects retired access',
    () async {
      final first = ProfileScope(
        profileId: 'first',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final next = ProfileScope(
        profileId: 'next',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      final legacy = jsonEncode(source.toJson());
      final second = jsonEncode([source.toJson(), source.toJson()]);
      SharedPreferences.setMockInitialValues({
        first.preferenceKey('series_source_tt1'): legacy,
        next.preferenceKey('series_source_tt1'): second,
      });
      ProfileRuntime.initializeCommitted(first);
      final container = ProviderContainer.test();
      HomeCatalogSession session() => HomeCatalogSession(
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
      );
      final repository = container
          .listen(homeBoundCountsRepositoryProvider(session()), (_, _) {})
          .read();
      expect(await repository.read(['tt1'], isCurrent: () => true), {'tt1': 1});
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(first.preferenceKey('series_source_tt1'))!),
        isA<List>(),
      );
      expect(prefs.getString(next.preferenceKey('series_source_tt1')), second);
      ProfileRuntime.publish(next);
      await expectLater(
        repository.read(['tt1'], isCurrent: () => true),
        throwsStateError,
      );
      final current = container
          .listen(homeBoundCountsRepositoryProvider(session()), (_, _) {})
          .read();
      expect(await current.read(['tt1'], isCurrent: () => true), {'tt1': 2});
    },
  );
  test('cancelled default read cannot migrate a legacy record', () async {
    ProfileRuntime.initializeLegacy();
    final legacy = jsonEncode(source.toJson());
    SharedPreferences.setMockInitialValues({'series_source_tt1': legacy});
    final container = ProviderContainer.test();
    final key = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    final repository = container
        .listen(homeBoundCountsRepositoryProvider(key), (_, _) {})
        .read();
    await expectLater(
      repository.readCount('tt1', () => false),
      throwsStateError,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('series_source_tt1'),
      legacy,
    );
  });
}
