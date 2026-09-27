import 'dart:convert';
import 'package:debrify/features/home/application/home_playlist_controller.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default adapter retains distinct real poster/progress keys and stored ordering',
    () async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(ProfileRuntime.debugReset);
      SharedPreferences.setMockInitialValues({
        'user_playlist_v1': jsonEncode([
          {
            'title': 'One',
            'kind': 'single',
            'rdTorrentId': 'one',
            'addedAt': 1,
            'extension': {
              'fileIds': [3, 4],
            },
          },
          {
            'title': 'Two',
            'kind': 'collection',
            'rdTorrentId': 'two',
            'addedAt': 2,
          },
        ]),
        'playlist_favorites_v1': jsonEncode({'realdebrid|rd:one': true}),
        'playlist_poster_overrides_v1': jsonEncode({
          'rd_one': {'posterUrl': 'override'},
        }),
        'playback_state_v1': jsonEncode({
          'video_one': {'type': 'video', 'positionMs': 50, 'durationMs': 100},
        }),
      });
      final c = ProviderContainer.test();
      final key = (
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
      );
      c.listen(homePlaylistProvider(key), (_, _) {});
      final controller = c.read(homePlaylistProvider(key).notifier);
      await controller.load(isCurrent: () => true, onRows: () {});
      final state = controller.current;
      expect(state.items.map((i) => i.title), ['Two', 'One']);
      final one = state.items.last;
      expect(one.posterUrl, 'override');
      expect(one.dedupeKey, 'realdebrid|rd:one');
      expect(state.progressFor(one), 0.5);
      expect(state.hasProgress(one), isTrue);
      expect(state.isFavorite(one), isTrue);
      expect(one.toLegacyItem()['extension'], {
        'fileIds': [3, 4],
      });
      expect(one.toLegacyItem()['posterUrl'], 'override');
      expect(state.items.first.isCollection, isTrue);
      expect(state.progressFor(state.items.first), isNull);
      expect(state.isFavorite(state.items.first), isFalse);
    },
  );
}
