import 'dart:async';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing resolved transport; no dependency change.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'iptv_workflow_driver.dart';
import 'local_completion_driver.dart';
import 'vp_fixture_actions.dart';

class IptvPreferenceWrites extends InMemorySharedPreferencesStore {
  IptvPreferenceWrites(super.values) : super.withData();
  final writes = <(String, Object)>[];
  final saved = <String>{};
  String? heldKey;
  final gate = Completer<void>();
  bool entered = false;
  static Future<IptvPreferenceWrites> install() async {
    final store = IptvPreferenceWrites(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add((key, value));
    if (heldKey != null && key.endsWith(heldKey!) && !gate.isCompleted) {
      entered = true;
      await gate.future;
    }
    final result = await super.setValue(type, key, value);
    saved.add(key);
    return result;
  }

  Future<Object?> physical(ProfileScope scope, String key) async =>
      (await getAll())['flutter.${scope.preferenceKey(key)}'];
  void release() {
    if (!gate.isCompleted) {
      gate.complete();
    }
  }
}

Future<({ProfileScope current, ProfileScope intermediate})> iptvHandoff(
  IptvWorkflowDriver d,
  ProfileScope a,
  String variant,
) async {
  final b = await completionIncomingProfile(d.t, d.f);
  if (variant == 'ABA') {
    return (current: await completionActivate(d.t, d.f, a), intermediate: b);
  }
  if (variant == 'delete') {
    final actor = await d.f.finish(d.t, d.f.registry!.getProfile(b.profileId));
    await d.f.finish(
      d.t,
      d.f.registry!.deleteProfileWithDisposition(
        id: a.profileId,
        deleteOwnedResources: true,
        detachPublicArtifacts: true,
        actingProfileId: b.profileId,
        actingAuthorizationRevision: actor!.authorizationRevision,
        actingSessionEpoch: b.sessionEpoch,
      ),
    );
  }
  return (current: ProfileRuntime.capture(), intermediate: b);
}

Future<List<Map<String, Object?>>> iptvPhysicalHistory(
  IptvWorkflowDriver d,
  ProfileScope scope,
) async {
  final file = scope.fileIn(d.f.directory, 'documents', 'debrify_tv.db');
  if (!await file.exists()) {
    return [];
  }
  final db = await databaseFactoryFfi.openDatabase(
    file.path,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    return await db.query('iptv_watch_history');
  } finally {
    await db.close();
  }
}

/// Hold an executed production await by its stack frame and returned value.
/// The ordinal distinguishes runScoped's adoption wait from admitted handle
/// delivery; no database handle or application outcome is substituted.
class IptvAwaitDelivery {
  IptvAwaitDelivery(this.frame, this.accepts, {this.skip = 0});
  final String frame;
  final bool Function(Object?) accepts;
  int skip;
  bool armed = true;
  final pending = <void Function()>[];
  final frames = <String>[];
  Result run<Result>(Result Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      registerUnaryCallback:
          <R, T>(self, parent, zone, R Function(T) callback) {
            final stack = StackTrace.current.toString();
            final selected =
                stack
                    .split('\n')
                    .where((s) => s.contains('package:debrify/'))
                    .firstOrNull
                    ?.contains(frame) ??
                false;
            return parent.registerUnaryCallback(zone, (T value) {
              if (armed &&
                  selected &&
                  accepts(value) &&
                  (R.toString() == 'void' || R.toString() == 'dynamic')) {
                if (skip > 0) {
                  skip--;
                  return callback(value);
                }
                armed = false;
                frames.add(stack);
                pending.add(
                  VpFixtureActions.heldCallback(
                    'iptv await $frame',
                    () => zone.runUnary(callback, value),
                  ),
                );
                return null as R;
              }
              return callback(value);
            });
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
