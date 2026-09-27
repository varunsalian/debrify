import 'package:debrify/features/home/data/home_tracking_policy_repository.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in WatchProgressSource.values) {
    for (final connected in [true, false]) {
      test(
        '$mode connected=$connected keeps read order and content policy',
        () async {
          final calls = <String>[];
          final repository = HomeTrackingPolicyRepository(
            isOwnerCurrent: () => true,
            readTargets: (_) async {
              calls.add('targets');
              return {TrackingSource.trakt};
            },
            readProgress: () async {
              calls.add('progress');
              return mode;
            },
            hasCredential: (source, _) async {
              calls.add(source.name);
              return connected;
            },
            fallbackDisconnected: (source, _) async {
              calls.add('fallback');
              return false;
            },
            readTicks: () async {
              calls.add('ticks');
              return {TrackingSource.simkl};
            },
          );
          final result = await repository.loadForContent(
            'tt123',
            isCurrent: () => true,
          );
          final dedicated = ![
            WatchProgressSource.smart,
            WatchProgressSource.local,
          ].contains(mode);
          expect(calls, [
            'targets',
            'progress',
            if (dedicated) mode.name,
            if (dedicated && !connected) 'fallback',
            'ticks',
          ]);
          expect(
            result!.progressSource,
            dedicated && !connected ? WatchProgressSource.smart : mode,
          );
          expect(result.scrobbleTargets, {TrackingSource.trakt});
          expect(result.homeTickSources, {TrackingSource.simkl});
          calls.clear();
          final local = await repository.loadForContent(
            'medialibrary:1',
            isCurrent: () => true,
          );
          expect(local!.progressSource, WatchProgressSource.local);
          expect(
            calls.first,
            'targets',
          ); // No custom-ID shortcut around migration/fallback.
          expect(calls.last, 'ticks');
          if (dedicated && !connected) expect(calls, contains('fallback'));
        },
      );
    }
  }

  for (final retiredAt in [
    'start',
    'targets',
    'progress',
    'credential',
    'fallback',
    'ticks',
  ]) {
    for (final retireOwner in [false, true]) {
      test(
        'retired ${retireOwner ? 'owner' : 'view'} at $retiredAt stops continuation',
        () async {
          var current = retiredAt != 'start';
          final calls = <String>[];
          void visit(String step) {
            calls.add(step);
            if (step == retiredAt) current = false;
          }

          final repository = HomeTrackingPolicyRepository(
            isOwnerCurrent: () => !retireOwner || current,
            readTargets: (_) async {
              visit('targets');
              return {};
            },
            readProgress: () async {
              visit('progress');
              return WatchProgressSource.trakt;
            },
            hasCredential: (_, guard) async {
              expect(guard(), isTrue);
              visit('credential');
              return false;
            },
            fallbackDisconnected: (_, guard) async {
              expect(guard(), isTrue);
              visit('fallback');
              return true;
            },
            readTicks: () async {
              visit('ticks');
              return {};
            },
          );
          expect(
            await repository.loadForContent(
              null,
              isCurrent: () => retireOwner || current,
            ),
            isNull,
          );
          expect(calls, retiredAt == 'start' ? isEmpty : isNotEmpty);
          if (calls.isNotEmpty) expect(calls.last, retiredAt);
        },
      );
    }
  }

  test('reader errors propagate without retry or fallback', () async {
    var reads = 0;
    final repository = HomeTrackingPolicyRepository(
      isOwnerCurrent: () => true,
      readTargets: (_) async {
        reads++;
        throw StateError('fixture');
      },
      readProgress: () async => throw UnimplementedError(),
      hasCredential: (_, _) async => throw UnimplementedError(),
      fallbackDisconnected: (_, _) async => throw UnimplementedError(),
      readTicks: () async => throw UnimplementedError(),
    );
    await expectLater(
      repository.loadForContent(null, isCurrent: () => true),
      throwsStateError,
    );
    expect(reads, 1);
  });
}
