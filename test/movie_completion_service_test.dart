import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/movie_completion_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';

void main() {
  for (final mode in WatchProgressSource.values) {
    for (final completed in TrackingSource.values) {
      test(
        '$mode completion from $completed respects progress not scrobble/ticks',
        () async {
          final policy = TrackingSourcePolicy(
            scrobbleTargets: {},
            progressSource: mode,
            homeTickSources: {},
          );
          final reads = <TrackingSource>[];
          final result = await MovieCompletionService.load(
            'tt001',
            policy: policy,
            read: (source) async {
              reads.add(source);
              return source == completed;
            },
          );
          expect(result, policy.progressFrom(completed));
          expect(
            reads.toSet(),
            TrackingSource.values.where(policy.progressFrom).toSet(),
          );
        },
      );
    }
  }
  test('failed provider does not hide successful smart completion', () async {
    const policy = TrackingSourcePolicy(
      scrobbleTargets: {},
      progressSource: WatchProgressSource.smart,
      homeTickSources: {},
    );
    expect(
      await MovieCompletionService.load(
        'tt001',
        policy: policy,
        read: (source) async {
          if (source == TrackingSource.trakt) throw StateError('offline');
          return source == TrackingSource.mdblist;
        },
      ),
      true,
    );
  });
}
