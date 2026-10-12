import 'dart:async';

import 'package:debrify/services/tracking_source_policy.dart';

/// Delays delivery of an actual immutable policy, leaving subsequent reads
/// free to observe the preference change through the real storage APIs.
class TraktPolicyReads {
  TraktPolicyReads(this.when);
  final bool Function() when;
  bool armed = true;
  final pending = <void Function()>[];
  ZoneSpecification get specification => ZoneSpecification(
    registerUnaryCallback: <R, T>(self, parent, zone, R Function(T) callback) {
      return parent.registerUnaryCallback(zone, (T value) {
        if (armed &&
            when() &&
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
