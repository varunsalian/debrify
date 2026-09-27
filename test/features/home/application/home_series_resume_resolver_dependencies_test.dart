import 'package:debrify/features/home/application/home_series_resume_dependencies.dart';
import 'package:debrify/features/home/application/home_series_resume_resolver_dependencies.dart';
import 'package:debrify/features/home/application/home_tracker_resume_dependencies.dart';
import 'package:debrify/features/home/application/home_tracking_policy_dependencies.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/home_series_resume_repository_test.dart' as signals;
import '../data/home_series_resume_resolver_test.dart' as resolver;

void main() {
  test(
    'view caches are isolated and provider disposal retires retained resolver',
    () async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(ProfileRuntime.debugReset);
      final f = resolver.Fixture();
      final container = ProviderContainer.test(
        overrides: [
          homeSeriesResumeRepositoryProvider.overrideWith(
            (ref, owner) => f.source.repository,
          ),
          homeTrackerResumeRepositoryProvider.overrideWith(
            (ref, session) => f.tracker.repository,
          ),
          homeTrackingPolicyRepositoryProvider.overrideWith(
            (ref, owner) => f.resolver.policies,
          ),
        ],
      );
      final owner = ProfileSessionMemory.captureOwner();
      final a = HomeCatalogSession(owner: owner, viewIdentity: Object());
      final b = HomeCatalogSession(owner: owner, viewIdentity: Object());
      final subscriptionA = container.listen(
        homeSeriesResumeResolverProvider(a),
        (_, _) {},
      );
      final subscriptionB = container.listen(
        homeSeriesResumeResolverProvider(b),
        (_, _) {},
      );
      final first = subscriptionA.read(), second = subscriptionB.read();
      Future<Object?> read(value) => value.resolve(
        signals.show,
        availability: () => (trakt: false, simkl: false, mdblist: false),
        cachedTrakt: () => null,
        isCurrent: () => true,
      );
      expect(await read(first), isNotNull);
      expect(await read(first), isNotNull);
      expect(await read(second), isNotNull);
      expect(f.localReads, 2);
      subscriptionA.close();
      await container.pump();
      expect(await read(first), isNull);
      expect(await read(second), isNotNull);
      second.clear();
      expect(await read(second), isNotNull);
      expect(f.localReads, 3);
      subscriptionB.close();
    },
  );
}
