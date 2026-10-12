import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/profiles/profile_preferences.dart';

/// Suspend delivery of a real decoded storage payload to its awaiter. No
/// source is replaced, no State is accessed, and the original storage reader
/// still decodes and validates its own JSON. The marker is an ignored sibling
/// of the real show maps; it identifies only this case's snapshot completion.
class TraktSnapshotReads {
  TraktSnapshotReads(
    this.marker, {
    this.skip = 0,
    this.multiple = false,
    this.when,
  });
  final String marker;
  int skip;
  final bool multiple;
  final bool Function()? when;
  bool armed = true;
  final pending = <void Function()>[];
  int deliveries = 0;

  ZoneSpecification get specification => ZoneSpecification(
    registerUnaryCallback: <R, T>(self, parent, zone, R Function(T) callback) {
      return parent.registerUnaryCallback(zone, (T value) {
        if (armed &&
            value is Map &&
            value['__vp_snapshot_case__'] == marker &&
            (when?.call() ?? true) &&
            (R.toString() == 'void' || R.toString() == 'dynamic')) {
          if (skip > 0) {
            skip--;
            return callback(value);
          }
          if (!multiple) armed = false;
          deliveries++;
          pending.add(() => zone.runUnary(callback, value));
          return null as R;
        }
        return callback(value);
      });
    },
  );

  Future<void> seed(
    Map<String, Map<String, double>> shows, {
    String store = 'episode_trakt_progress_v2',
  }) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      store,
      jsonEncode({
        '__vp_snapshot_case__': marker,
        for (final show in shows.entries) 'imdb_${show.key}': show.value,
      }),
    );
  }

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
