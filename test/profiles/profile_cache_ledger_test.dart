import 'dart:io';

import 'package:debrify/services/profiles/profile_cache_ledger.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProfileScope scopeFor(String id, int generation, int epoch) => ProfileScope(
    profileId: id,
    dataGeneration: generation,
    sessionEpoch: epoch,
  );

  setUp(ProfileCacheLedger.debugReset);
  tearDown(ProfileCacheLedger.debugReset);

  test('a partial warm leaves later caches on the previous scope', () {
    // The property the whole ledger exists for. Stamping every cache in one
    // call at the end of the warm would report success for caches a throw
    // never reached — and a cache still serving the outgoing profile is
    // exactly the leak this is meant to make visible.
    final first = scopeFor('alpha', 1, 1);
    ProfileCacheLedger.stamp('Trakt', first);
    ProfileCacheLedger.stamp('Engines', first);

    // A second warm that gets through Trakt and then throws.
    final second = scopeFor('beta', 1, 2);
    ProfileCacheLedger.stamp('Trakt', second);

    final snapshot = ProfileCacheLedger.snapshot();
    expect(snapshot['Trakt'], ProfileCacheLedger.keyFor(second));
    expect(
      snapshot['Engines'],
      ProfileCacheLedger.keyFor(first),
      reason: 'an unreached cache must still show the scope it actually holds',
    );
  });

  test('the key carries generation and epoch, not just the profile', () {
    // Re-entering the same profile mints a new epoch, and a cache warmed for
    // the previous session is still stale. Keying on profile id alone would
    // call that a match.
    expect(
      ProfileCacheLedger.keyFor(scopeFor('alpha', 3, 12)),
      'p.alpha.g.3.e.12',
    );
    expect(
      ProfileCacheLedger.keyFor(scopeFor('alpha', 3, 12)),
      isNot(ProfileCacheLedger.keyFor(scopeFor('alpha', 3, 13))),
    );
    expect(
      ProfileCacheLedger.keyFor(scopeFor('alpha', 3, 12)),
      isNot(ProfileCacheLedger.keyFor(scopeFor('alpha', 4, 12))),
    );
  });

  test('a cache that reports its own scope can disagree', () {
    // EngineRegistry measures rather than declares: it can hold engines for a
    // scope nobody stamped, which is the disagreement worth surfacing.
    ProfileCacheLedger.stamp('Trakt', scopeFor('alpha', 1, 2));
    ProfileCacheLedger.stampRaw('Engines', 'p.beta.g.1.e.1');
    ProfileCacheLedger.stampRaw('Unloaded', null);

    final snapshot = ProfileCacheLedger.snapshot();
    expect(snapshot['Engines'], 'p.beta.g.1.e.1');
    expect(snapshot['Unloaded'], 'unloaded');
    expect(snapshot['Engines'], isNot(snapshot['Trakt']));
  });

  test('snapshot is sorted and immutable', () {
    ProfileCacheLedger.stamp('Zulu', scopeFor('alpha', 1, 1));
    ProfileCacheLedger.stamp('Alpha', scopeFor('alpha', 1, 1));
    final snapshot = ProfileCacheLedger.snapshot();
    expect(snapshot.keys.toList(), <String>['Alpha', 'Zulu']);
    expect(() => snapshot['x'] = 'y', throwsUnsupportedError);
  });

  test('the warm path stamps per group, not once at the end', () {
    // Source-level, like profile_source_guard_test: the ordering property
    // cannot be observed through the real participant without standing up the
    // whole app, but a single trailing stamp would silently destroy it.
    final source = File(
      'lib/services/profiles/profile_app_lifecycle_participant.dart',
    ).readAsStringSync();
    final warmed = '_warmed('.allMatches(source).length;
    expect(
      warmed,
      greaterThan(5),
      reason: 'each warmed cache must be stamped as it is warmed',
    );
    expect(
      source,
      contains('ProfileCacheLedger.stampRaw'),
      reason: 'EngineRegistry reports its measured scope rather than a stamp',
    );
  });
}
