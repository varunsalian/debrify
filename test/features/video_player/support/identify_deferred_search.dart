import 'dart:async';

import 'vp_fixture_actions.dart';

/// Holds the Future() timer created by the rendered sheet's initial-search
/// builder. Its first setter has not run; entry is separate from completion.
class IdentifyDeferredSearch {
  final pending = <void Function()>[];
  bool armed = true;
  T run<T>(T Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final frame = StackTrace.current
            .toString()
            .split('\n')
            .where((f) => f.contains('package:debrify/'))
            .firstOrNull;
        if (armed &&
            duration == Duration.zero &&
            (frame?.contains('showIdentifyTitleSearchSheet') ?? false)) {
          armed = false;
          return parent.createTimer(zone, duration, () {
            pending.add(
              VpFixtureActions.heldCallback(
                'identify-deferred-search',
                () => zone.run(callback),
              ),
            );
          });
        }
        return parent.createTimer(zone, duration, callback);
      },
    ),
  );
  void release() {
    armed = false;
    final callbacks = List<void Function()>.of(pending);
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}
