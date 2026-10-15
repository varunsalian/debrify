import 'dart:async';

import 'vp_fixture_actions.dart';

/// Hold delivery of a real transport/service result to its awaiting caller.
/// No State calls, substituted results or production work are introduced.
class RecordingDelivery {
  RecordingDelivery(this.accepts);
  final bool Function(Object?) accepts;
  bool armed = true;
  final pending = <void Function()>[];
  ZoneSpecification get specification => ZoneSpecification(
    registerUnaryCallback: <R, T>(self, parent, zone, R Function(T) callback) =>
        parent.registerUnaryCallback(zone, (T value) {
          if (armed &&
              accepts(value) &&
              (R.toString() == 'void' || R.toString() == 'dynamic')) {
            armed = false;
            pending.add(
              VpFixtureActions.heldCallback(
                'recording_delivery.dart',
                () => zone.runUnary(callback, value),
              ),
            );
            return null as R;
          }
          return callback(value);
        }),
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
