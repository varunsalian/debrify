import 'package:debrify/services/home_return_cache.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cache = HomeReturnCache<String>();
  final loadedAt = DateTime.utc(2026, 9, 14);
  late ProfileSessionOwner owner;
  setUp(() {
    ProfileSessionMemory.clearAll();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    owner = ProfileSessionMemory.captureOwner();
  });
  tearDown(ProfileRuntime.debugReset);

  void save(String value, {int? revision, ProfileSessionOwner? asOwner}) =>
      cache.store(
        asOwner ?? owner,
        value,
        revision: revision ?? HomeReturnCache.revision,
        loadedAt: loadedAt,
      );

  test(
    'same-session board is available once and expires from original load',
    () {
      save('board');
      expect(
        cache.take(owner, now: loadedAt.add(const Duration(minutes: 4))),
        'board',
      );
      expect(cache.take(owner, now: loadedAt), isNull);
      save('board');
      expect(
        cache.take(owner, now: loadedAt.add(const Duration(minutes: 5))),
        isNull,
      );
    },
  );

  for (final change in <String, void Function()>{
    'Home settings': MainPageBridge.notifyHomeSettingsChanged,
    'integrations': MainPageBridge.notifyIntegrationChanged,
    'addons': StremioService.instance.invalidateCache,
  }.entries) {
    test('${change.key} invalidate saved and in-flight snapshots', () {
      final revision = HomeReturnCache.revision;
      save('old');
      change.value();
      expect(cache.take(owner, now: loadedAt), isNull);
      save('late old', revision: revision);
      expect(cache.take(owner, now: loadedAt), isNull);
    });
  }

  test(
    'profile retirement rejects late disposal without replacing new content',
    () {
      save('outgoing');
      ProfileSessionMemory.clearAll();
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'incoming', dataGeneration: 1, sessionEpoch: 1),
      );
      final incoming = ProfileSessionMemory.captureOwner();
      expect(cache.take(incoming, now: loadedAt), isNull);
      save('incoming', asOwner: incoming);
      save('late outgoing');
      expect(cache.take(incoming, now: loadedAt), 'incoming');
    },
  );
}
