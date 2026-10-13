import 'dart:async';

import 'vp_fixture_actions.dart';

import 'package:debrify/services/profiles/profile_async_authorization.dart';

/// Holds the real capability at the player's await continuation, after the
/// service has performed its authorization. No capability or result is forged.
class MdblistCapabilityReads {
  final pending = <void Function()>[];
  bool armed = true;

  ZoneSpecification get specification => ZoneSpecification(
    registerUnaryCallback: <R, T>(self, parent, zone, R Function(T) callback) {
      // Other startup consumers (notably addon subtitles) also capture real
      // capabilities. Route only the player's await, using the first app frame
      // at callback registration; both the original and moved method have this
      // name. This selects a transport barrier, not a source-body assertion.
      final frames = StackTrace.current.toString().split('\n');
      final appFrame = frames
          .where((f) => f.contains('package:debrify/'))
          .firstOrNull;
      final playerAwait = appFrame?.contains('initMdblistScrobble') ?? false;
      return parent.registerUnaryCallback(zone, (T value) {
        if (armed &&
            playerAwait &&
            value is ProfileAsyncAuthorization &&
            (R.toString() == 'void' || R.toString() == 'dynamic')) {
          armed = false;
          pending.add(
            VpFixtureActions.heldCallback(
              'mdblist_capability_reads.dart',
              () => zone.runUnary(callback, value),
            ),
          );
          return null as R;
        }
        return callback(value);
      });
    },
  );

  T run<T>(T Function() body) =>
      runZoned(body, zoneSpecification: specification);

  void release() {
    armed = false;
    final callbacks = List<void Function()>.of(pending);
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}
