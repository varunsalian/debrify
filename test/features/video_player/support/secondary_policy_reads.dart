import 'dart:async';

import 'package:debrify/services/tracking_source_policy.dart';

/// Holds the real immutable policy at this player's MDBList init await.
/// Other policy consumers keep running, including native player setup.
class MdblistPolicyReads {
  MdblistPolicyReads({this.awaitName = 'initMdblistScrobble', this.when});
  final String awaitName;
  final bool Function()? when;
  final pending = <void Function()>[];
  bool armed = true;

  ZoneSpecification get specification => ZoneSpecification(
    registerUnaryCallback: <R, T>(self, parent, zone, R Function(T) callback) {
      final appFrame = StackTrace.current
          .toString()
          .split('\n')
          .where((frame) => frame.contains('package:debrify/'))
          .firstOrNull;
      final playerAwait = appFrame?.contains(awaitName) ?? false;
      return parent.registerUnaryCallback(zone, (T value) {
        if (armed &&
            playerAwait &&
            (when?.call() ?? true) &&
            value is TrackingSourcePolicy &&
            (R.toString() == 'void' || R.toString() == 'dynamic')) {
          armed = false;
          pending.add(() => zone.runUnary(callback, value));
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
