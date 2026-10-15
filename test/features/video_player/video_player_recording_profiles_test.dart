import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/recording_driver.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;

Future<List<Map<String, Object?>>> artifacts(
  RecordingDriver d,
  String owner,
) async {
  var rows = <Map<String, Object?>>[];
  for (var i = 0; i < 100 && rows.isEmpty; i++) {
    rows = await d.f.finish(d.t, d.f.registry!.listOwnedArtifacts(owner));
    if (rows.isEmpty) await d.f.advance(d.t);
  }
  expect(rows, hasLength(1));
  return rows;
}

void main() {
  for (final timing in ['before-service', 'after-start']) {
    for (final authority in ['valid', 'revoked', 'deleted']) {
      testWidgets(
        'p13 desktop profile handoff $timing owner=$authority pins jobs and artifacts',
        (t) async {
          final d = RecordingDriver(t);
          await d.setup();
          try {
            final a = ProfileRuntime.capture();
            final url = await d.loopback();
            await d.mountRecording(url: url, tee: false);
            d.native.properties['file-format'] = 'mpegts';
            if (timing == 'before-service') d.paths.gate = Completer<String?>();
            d.desktopRecord();
            DesktopRecordingCapture? capture;
            if (timing == 'before-service') {
              await d.f.until(t, () => d.paths.reads > 0);
            } else {
              capture = await d.captured(url);
            }
            await incomingProfile(t, d.f);
            final b = ProfileRuntime.capture();
            final owner = timing == 'before-service'
                ? b.profileId
                : a.profileId;
            final actor = await d.f.finish(
              t,
              d.f.registry!.getProfile(b.profileId),
            );
            Future<void> deleteOutgoing() =>
                d.f.registry!.deleteProfileWithDisposition(
                  id: a.profileId,
                  deleteOwnedResources: true,
                  detachPublicArtifacts: true,
                  actingProfileId: b.profileId,
                  actingAuthorizationRevision: actor!.authorizationRevision,
                  actingSessionEpoch: b.sessionEpoch,
                );
            if (authority == 'revoked') {
              final profile = await d.f.finish(
                t,
                d.f.registry!.getProfile(owner),
              );
              final changed = await d.f.finish(
                t,
                d.f.registry!.updateProfile(
                  id: owner,
                  policy: ProfilePolicy(
                    enabled: {...profile!.policy.enabled}
                      ..remove(ProfileFeature.recordings),
                  ),
                  actingProfileId: b.profileId,
                  actingAuthorizationRevision: actor!.authorizationRevision,
                  actingSessionEpoch: b.sessionEpoch,
                ),
              );
              if (owner == b.profileId) {
                ProfilePolicyGuard.updateActiveProfile(changed);
              }
            }
            if (authority == 'deleted') {
              if (timing == 'before-service') {
                await d.f.finish(t, deleteOutgoing());
                expect(
                  await d.f.finish(t, d.f.registry!.getProfile(a.profileId)),
                  isNull,
                );
              } else {
                await expectLater(
                  d.f.finish(t, deleteOutgoing()),
                  throwsA(
                    isA<StateError>().having(
                      (e) => e.message,
                      'active-job blocker',
                      'Active jobs must finish or be cancelled first',
                    ),
                  ),
                );
                expect(capture!.isActive, isTrue);
              }
            }
            d.paths.gate?.complete(d.paths.path);
            if (timing == 'before-service' && authority == 'revoked') {
              await d.f.until(t, () => d.errors.isNotEmpty);
              expect(DesktopRecordingService.instance.activeCount, 0);
              expect(d.errors.single, isA<StateError>());
              expect(
                (await d.f.finish(
                  t,
                  d.f.registry!.listJobOwnership(),
                )).where((j) => j['backend'] == 'desktopRecording'),
                isEmpty,
              );
            } else {
              capture ??= await d.captured(url);
              expect(capture.ownerProfileId, owner);
              final jobs = await d.f.finish(
                t,
                d.f.registry!.listJobOwnership(),
              );
              expect(
                jobs.singleWhere(
                  (j) => j['external_job_id'] == capture!.jobId,
                )['owner_profile_id'],
                owner,
              );
              if (authority == 'revoked') {
                await t.runAsync(
                  () => Future<void>.delayed(const Duration(seconds: 6)),
                );
                await d.f.advance(t, const Duration(milliseconds: 100));
                await d.f.until(t, () => !capture!.isActive);
              } else {
                await d.f.finish(t, capture.stop());
              }
              final saved = await artifacts(d, owner);
              expect(
                saved.single['canonical_path'],
                File(capture.path).absolute.path,
              );
              expect(saved.single['owner_profile_id'], owner);
              expect(saved.single['size_bytes'], greaterThanOrEqualTo(188));
              expect(
                await d.f.finish(
                  t,
                  d.f.registry!.listOwnedArtifacts(
                    timing == 'before-service' ? a.profileId : b.profileId,
                  ),
                ),
                isEmpty,
              );
              if (authority == 'deleted' && timing == 'after-start') {
                await d.f.finish(t, deleteOutgoing());
                expect(
                  await d.f.finish(t, d.f.registry!.getProfile(owner)),
                  isNull,
                );
                final rows = await t.runAsync(() async {
                  final db = await databaseFactory.openDatabase(
                    '${d.f.directory.path}/profiles.db',
                    options: OpenDatabaseOptions(
                      readOnly: true,
                      singleInstance: false,
                    ),
                  );
                  try {
                    return await db.query(
                      'owned_artifacts',
                      where: 'canonical_path = ?',
                      whereArgs: [File(capture!.path).absolute.path],
                    );
                  } finally {
                    await db.close();
                  }
                });
                expect(rows!.single['owner_profile_id'], isNull);
                expect(rows.single['ownership_state'], 'detached');
                final terminal = await d.f.finish(
                  t,
                  d.f.registry!.listJobOwnership(),
                );
                expect(
                  terminal.singleWhere(
                    (j) => j['external_job_id'] == capture!.jobId,
                  )['detached_owner_token'],
                  rows.single['detached_owner_token'],
                );
              }
              expect(
                await t.runAsync(() => File(capture!.path).exists()),
                isTrue,
              );
              expect(d.errors, isEmpty);
            }
          } finally {
            await d.close();
          }
        },
      );
    }
  }
}
