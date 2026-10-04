import 'package:debrify/screens/merged_series_detail_screen.dart'
    show mergedDetailTestAccess;
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/merged_detail_fixture.dart';

void main() {
  testWidgets('opening and playback return keep the host reload order', (
    t,
  ) async {
    await mergedDetailCase(t, (f) async {
      f.xtream = true;
      await f.mount(t);
      expect(
        f.calls
            .where((c) => ['resume', 'trakt', 'simkl', 'mdblist'].contains(c))
            .toList(),
        ['resume', 'trakt', 'simkl', 'mdblist'],
      );
      f.calls.clear();
      MainPageBridge.notifyPlaybackReturned();
      await f.until(t, () => f.calls.contains('mdblist'));
      expect(
        f.calls
            .where((c) => ['resume', 'trakt', 'simkl', 'mdblist'].contains(c))
            .toList(),
        ['resume', 'trakt', 'simkl', 'mdblist'],
      );
      await t.pumpWidget(const SizedBox.shrink());
      f.calls.clear();
      MainPageBridge.notifyPlaybackReturned();
      await t.pump();
      expect(f.calls, isEmpty);
    });
  });
  testWidgets(
    'a covered route ignores playback return then refreshes on didPopNext',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.xtream = true;
        await f.mount(t);
        f.calls.clear();
        f.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Cover')),
          ),
        );
        await t.pump(const Duration(milliseconds: 400));
        MainPageBridge.notifyPlaybackReturned();
        await t.pump();
        expect(f.calls, isEmpty);
        f.navigator.currentState!.pop();
        await t.pump(const Duration(milliseconds: 400));
        await f.until(t, () => f.calls.contains('mdblist'));
        expect(
          f.calls
              .where((c) => ['resume', 'trakt', 'simkl', 'mdblist'].contains(c))
              .toList(),
          ['resume', 'trakt', 'simkl', 'mdblist'],
        );
      });
    },
  );
  for (final name in ['tracking source', 'movie finished', 'MDBList watched']) {
    testWidgets(
      '$name mutation increments once before unmount and does no read afterward',
      (t) async {
        await mergedDetailCase(t, (f) async {
          f.xtream = true;
          await f.mount(t);
          final notifier = switch (name) {
            'tracking source' => TrackingSourceStorage.trackingSourceRevision,
            'movie finished' => MovieProgressStorage.movieFinishedRevision,
            _ => MdblistService.instance.watchedRevision,
          };
          final before = f.access['movieGeneration'] as int;
          notifier.value++;
          await t.pump();
          expect(f.access['movieGeneration'], before + 1);
          final state = f.key.currentState!;
          await t.pumpWidget(const SizedBox.shrink());
          // Snapshot the disposed State through the frozen accessor: distinguishes
          // an unwanted post-unmount read/generation bump from no publication.
          final disposed = mergedDetailTestAccess(state)['movieGeneration'];
          notifier.value++;
          await t.pump();
          expect(mergedDetailTestAccess(state)['movieGeneration'], disposed);
        });
      },
    );
  }
  testWidgets(
    'metadata preference revision resets collections and increments guards once',
    (t) async {
      await mergedDetailCase(t, (f) async {
        await f.mount(t);
        f.calls.clear();
        final generation = f.access['metadataGeneration'] as int;
        final trailer = f.access['trailerGeneration'] as int;
        MetadataPreferencesService.revision.value++;
        await f.until(
          t,
          () => (f.access['metadataGeneration'] as int) > generation,
        );
        // Metadata increments once; trailer reset and loading each increment.
        expect(f.access['metadataGeneration'], generation + 1);
        expect(f.access['trailerGeneration'], trailer + 2);
        expect(f.calls, ['recommendations']);
        expect(f.access['recommendations'], isA<List>());
        final list = f.access['recommendations'] as List;
        list.add(f.item);
        list.removeLast();
      });
    },
  );
  testWidgets(
    'profile scope notification reloads metadata only and does not publish after unmount',
    (t) async {
      await mergedDetailCase(t, (f) async {
        await f.mount(t);
        f.calls.clear();
        final state = f.key.currentState!;
        final before = f.access['metadataGeneration'] as int;
        ProfileRuntime.scope.value = ProfileScope(
          profileId: 'merged-other',
          dataGeneration: 1,
          sessionEpoch: 1,
        );
        await f.until(
          t,
          () => (f.access['metadataGeneration'] as int) > before,
        );
        expect(f.access['metadataGeneration'], before + 1);
        expect(f.calls, ['recommendations']);
        await t.pumpWidget(const SizedBox.shrink());
        final disposed = mergedDetailTestAccess(state)['metadataGeneration'];
        ProfileRuntime.scope.value = ProfileScope(
          profileId: 'merged-third',
          dataGeneration: 1,
          sessionEpoch: 2,
        );
        MetadataPreferencesService.revision.value++;
        await t.pump();
        expect(mergedDetailTestAccess(state)['metadataGeneration'], disposed);
      });
    },
  );
}
