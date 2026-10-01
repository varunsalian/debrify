import 'dart:convert';

import 'package:debrify/features/home/application/home_playback_providers.dart';
import 'package:debrify/features/home/data/home_catalog_playback_readers.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_series_resume_dependencies_test.dart' show history;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'Play borrows the exact label resolver and tracker memo for its view',
    () async {
      final container = ProviderContainer.test();
      final owner = ProfileSessionMemory.captureOwner();
      final session = HomeCatalogSession(owner: owner, viewIdentity: Object());
      final other = HomeCatalogSession(owner: owner, viewIdentity: Object());
      final label = container.listen(
        homeSeriesResumeResolverProvider(session),
        (_, _) {},
      );
      final tracker = container.listen(
        homeTrackerResumeRepositoryProvider(session),
        (_, _) {},
      );
      final play = container.read(homeCatalogPlaybackResolverProvider(session));
      expect(play.seriesResume, same(label.read()));
      expect(play.trackers, same(tracker.read()));
      final second = container.read(homeCatalogPlaybackResolverProvider(other));
      expect(second.seriesResume, isNot(same(play.seriesResume)));
      expect(second.trackers, isNot(same(play.trackers)));
      await container.pump();
      expect(
        container.read(homeSeriesResumeResolverProvider(session)),
        same(play.seriesResume),
      );
      label.close();
      tracker.close();
    },
  );

  test(
    'local readers use originating namespace and reject retired owners',
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
      ProfileRuntime.initializeCommitted(origin);
      SharedPreferences.setMockInitialValues({
        origin.preferenceKey('playback_state_v1'): jsonEncode({
          ...jsonDecode(history(season: 2, episode: 3)) as Map<String, dynamic>,
          'video_fixture': {
            'type': 'video',
            'imdbId': 'ttMovie',
            'updatedAt': 1,
          },
        }),
        other.preferenceKey('playback_state_v1'): history(
          season: 8,
          episode: 9,
        ),
      });
      final readers = HomeCatalogPlaybackReaders(
        ProfileSessionMemory.captureOwner(),
      );
      final result = await ProfileRuntime.withCapturedScope(
        other,
        () => readers.localById('tt123', isCurrent: () => true),
      );
      expect(result?['season'], 2);
      expect(result?['episode'], 3);
      expect(
        await ProfileRuntime.withCapturedScope(
          other,
          () => readers.movieStarted('ttMovie', isCurrent: () => true),
        ),
        isTrue,
      );
      expect(
        await readers.movieStarted('missing', isCurrent: () => true),
        isFalse,
      );
      ProfileSessionMemory.clearAll();
      expect(
        await readers.movieStarted('ttMovie', isCurrent: () => true),
        isNull,
      );
      expect(await readers.localById('tt123', isCurrent: () => true), isNull);
      expect(
        await readers.localByTitle('Exact Title', isCurrent: () => true),
        isNull,
      );
    },
  );
}
