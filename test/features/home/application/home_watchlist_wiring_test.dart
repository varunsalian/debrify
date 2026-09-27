import 'dart:convert';
import 'package:debrify/features/home/application/home_watchlist_controller.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default reader retains storage ordering/filtering and groups accepted titles',
    () async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(ProfileRuntime.debugReset);
      SharedPreferences.setMockInitialValues({
        'my_watchlist_v1': jsonEncode([
          {
            'key': 'movie:tt1',
            'addedAt': 1,
            'item': {
              'id': 'tt1',
              'name': 'Older',
              'type': 'movie',
              'poster': 'poster',
            },
          },
          {
            'key': 'series:tt2',
            'addedAt': 3,
            'item': {'id': 'tt2', 'name': 'Show', 'type': 'series'},
          },
          {
            'key': 'movie:tt3',
            'addedAt': 2,
            'item': {'id': 'tt3', 'name': 'Newer', 'type': 'movie'},
          },
          {'key': 'bad', 'addedAt': 99, 'item': 'corrupt'},
        ]),
      });
      final c = ProviderContainer.test();
      final key = (
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
      );
      c.listen(homeWatchlistProvider(key), (_, _) {});
      final controller = c.read(homeWatchlistProvider(key).notifier);
      await controller.load(isCurrent: () => true, onRows: () {});
      expect(controller.current.movies.map((i) => i.name), ['Newer', 'Older']);
      expect(controller.current.movies.last.poster, 'poster');
      expect(controller.current.series.single.name, 'Show');
    },
  );
}
