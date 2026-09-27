import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/trakt/trakt_service.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/mdblist/mdblist_service.dart';
import '../models/home_tracker_authentication.dart';

/// Preserve each service's authentication/refresh policy and originating scope.
final homeTrackerAuthReaderProvider = Provider.autoDispose
    .family<HomeTrackerAuthReader, HomeTrackerAuthSession>(
      (ref, session) => () async {
        if (session.view.owner != ProfileSessionMemory.captureOwner()) {
          return false;
        }
        Future<bool> read() => switch (session.tracker) {
          HomeTracker.trakt => TraktService.instance.isAuthenticated(),
          HomeTracker.simkl => SimklService.instance.isAuthenticated(),
          HomeTracker.mdblist => MdblistService.instance.isAuthenticated(),
        };
        final scope = session.view.owner.scope;
        return scope == null
            ? read()
            : ProfileRuntime.withCapturedScope(scope, read);
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
