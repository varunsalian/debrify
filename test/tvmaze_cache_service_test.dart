import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/tvmaze_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TVMazeCacheService.debugSetPersistentCacheSupported(false);
  });

  tearDown(() {
    TVMazeCacheService.debugSetPersistentCacheSupported(null);
    ProfileRuntime.debugReset();
  });

  test(
    'unsupported platforms keep TVMaze responses out of preferences',
    () async {
      await TVMazeCacheService.setList('episodes_1139', <Map<String, dynamic>>[
        <String, dynamic>{'id': 1, 'name': 'Pilot'},
      ]);

      expect(await TVMazeCacheService.getList('episodes_1139'), isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );
}
