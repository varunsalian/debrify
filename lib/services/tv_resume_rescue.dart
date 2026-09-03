import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../utils/app_storage.dart';
import 'diagnostic_log.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_session.dart';
import 'storage_service.dart';

/// Crash-durable resume rescue for the native Android TV player.
///
/// The native player persists nothing itself: every position ping crosses a
/// MethodChannel into this process's Dart isolate, which writes the resume
/// stores. When the process dies mid-playback (decoder crash, LMK kill, OOM)
/// everything since the last delivered ping is lost — the 2026-09-03 field
/// report came back "75 minutes left" after watching well past that point.
///
/// The rescue is two files in `filesDir` (== [AppStorage.support] on Android):
///
///  * `tv_resume_stage.owner.json` — written HERE at launch: which profile
///    started playback, the content type, the imdbId. Dart owns identity.
///  * `tv_resume_stage.pos.json` — written by the native player every
///    progress tick with the same values it sends over the channel. Kotlin
///    owns position.
///
/// Both are deleted after every clean finish and after every reconcile, so
/// they exist only across an abnormal exit. The reconcile itself is fenced so
/// it can only ever deepen state that already exists:
///
///  * it never CREATES an entry — the live 5-second path already created one
///    before the crash, and a missing entry means the user (or a completion)
///    removed it, which a rescue must not undo (the ghost-row class of bug);
///  * it never moves a position backward, never marks anything watched, and
///    ignores snapshots at 95%+ (completion territory belongs to the live
///    path and connected trackers only);
///  * it only runs for the profile that was playing, and leaves the files in
///    place for that profile's next activation otherwise.
class TvResumeRescue {
  TvResumeRescue._();

  static const String _ownerFileName = 'tv_resume_stage.owner.json';
  static const String _positionFileName = 'tv_resume_stage.pos.json';
  static const String _positionTmpFileName = 'tv_resume_stage.pos.json.tmp';

  /// A snapshot older than this is presumed orphaned (its profile was never
  /// activated again); resume points themselves do not expire, but a rescue
  /// file with no owner coming back for it should not wait forever.
  static const Duration _staleAfter = Duration(days: 7);

  /// Never rescue into completion territory: 95 is the ceiling the completion
  /// threshold settings allow, so anything at or above it is the live path's
  /// business, not a rescue's.
  static const double _maxRescuePercent = 95.0;

  static bool _started = false;
  static bool _running = false;
  static VoidCallback? _scopeListener;

  /// True between [recordLaunch] and [clearAfterCleanFinish] in THIS process:
  /// the stage files belong to a live session, and a reconcile racing in
  /// (a profile scope re-publish fires the listener) must not consume them —
  /// it would delete the owner mid-playback and leave the rest of the session
  /// unprotected. A process death resets this to false, which is exactly when
  /// the files become rescuable.
  static bool _sessionActive = false;

  /// Idempotent. Registers for profile activations and immediately attempts
  /// one reconcile (covering legacy mode, where the scope notifier never
  /// fires, and a scope already installed by bootstrap).
  static Future<void> start() async {
    if (_started || kIsWeb || !Platform.isAndroid) return;
    _started = true;
    _scopeListener = () => unawaited(_reconcileOnce());
    ProfileSession.notifier.addListener(_scopeListener!);
    await _reconcileOnce();
  }

  /// Called by the launcher right before native playback starts: stamps who
  /// is playing so a later reconcile can prove the snapshot is theirs. Also
  /// clears any leftover position file so a stale snapshot from a previous
  /// title can never ride along under the new owner.
  static Future<void> recordLaunch({
    required String contentType,
    String? imdbId,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final profileId = _activeProfileId();
      if (profileId == null) return;
      _sessionActive = true;
      await _delete(_positionFileName);
      await _delete(_positionTmpFileName);
      final owner = <String, Object?>{
        'profileId': profileId,
        'contentType': contentType,
        if (imdbId != null && imdbId.isNotEmpty) 'imdbId': imdbId,
        'launchedAtMs': DateTime.now().millisecondsSinceEpoch,
      };
      final file = await _file(_ownerFileName);
      await file.writeAsString(jsonEncode(owner), flush: true);
    } catch (error) {
      // Never let bookkeeping break a playback launch.
      debugPrint('TvResumeRescue: recordLaunch failed: $error');
    }
  }

  /// Called after the native player reports a clean finish (and when a launch
  /// fails outright): the live channel delivered everything, so the stage
  /// must not outlive the session and be mistaken for a crash later.
  static Future<void> clearAfterCleanFinish() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _sessionActive = false;
    await _delete(_ownerFileName);
    await _delete(_positionFileName);
    await _delete(_positionTmpFileName);
  }

  static Future<void> _reconcileOnce() async {
    if (_running) return;
    _running = true;
    try {
      await _reconcile();
    } catch (error) {
      debugPrint('TvResumeRescue: reconcile failed: $error');
    } finally {
      _running = false;
    }
  }

  static Future<void> _reconcile() async {
    if (_sessionActive) return; // live session owns the stage files
    final activeId = _activeProfileId();
    if (activeId == null) return; // runtime not ready; a later kick retries

    final owner = await _readJson(_ownerFileName);
    final position = await _readJson(_positionFileName);
    if (owner == null && position == null) return;

    // A half-pair carries nothing rescuable (launch failed before staging, or
    // identity is unprovable). Age everything out together.
    if (owner == null || position == null) {
      await clearAfterCleanFinish();
      return;
    }

    final ownerProfileId = owner['profileId'] as String?;
    final updatedAtMs = (position['updatedAtMs'] as num?)?.toInt() ?? 0;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
    if (updatedAtMs <= 0 || age > _staleAfter || age.isNegative) {
      await clearAfterCleanFinish();
      return;
    }
    if (ownerProfileId == null || ownerProfileId != activeId) {
      // Another profile's session: leave the stage for its activation, which
      // lands here again through the scope listener.
      return;
    }

    final resumeId = position['resumeId'] as String?;
    final positionMs = (position['positionMs'] as num?)?.toInt() ?? 0;
    final durationMs = (position['durationMs'] as num?)?.toInt() ?? 0;
    final stagedUrl = position['url'] as String?;
    final contentType = owner['contentType'] as String?;
    try {
      if (resumeId == null ||
          resumeId.isEmpty ||
          positionMs <= 0 ||
          durationMs <= 0 ||
          positionMs * 100.0 / durationMs >= _maxRescuePercent) {
        return;
      }

      var rescuedState = false;
      var rescuedResume = false;

      // Playback-state map (drives Continue Watching). Deepen-only, and only
      // an entry the live path already created; getVideoPlaybackState also
      // returns null for a movie marked finished, which keeps a rescue from
      // resurrecting a completed one.
      final state = await StorageService.getVideoPlaybackState(
        videoTitle: resumeId,
      );
      final stateUrl = (stagedUrl != null && stagedUrl.isNotEmpty)
          ? stagedUrl
          : state?['url'] as String?;
      if (state != null &&
          stateUrl != null &&
          ((state['positionMs'] as num?)?.toInt() ?? 0) < positionMs) {
        await StorageService.saveVideoPlaybackState(
          videoTitle: resumeId,
          videoUrl: stateUrl,
          positionMs: positionMs,
          durationMs: durationMs,
          speed: (state['speed'] as num?)?.toDouble() ?? 1.0,
          aspect: state['aspect'] as String? ?? 'contain',
          imdbId: owner['imdbId'] as String? ?? state['imdbId'] as String?,
        );
        rescuedState = true;
      }

      // The per-video resume store, singles only — mirroring which store the
      // live path writes for each content type.
      if (contentType == 'single') {
        final resume = await StorageService.getVideoResume(resumeId);
        if (resume != null &&
            ((resume['positionMs'] as num?)?.toInt() ?? 0) < positionMs) {
          await StorageService.upsertVideoResume(resumeId, {
            'positionMs': positionMs,
            'durationMs': durationMs,
            'speed': (resume['speed'] as num?)?.toDouble() ?? 1.0,
            'aspect': resume['aspect'] as String? ?? 'contain',
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
          rescuedResume = true;
        }
      }

      if (rescuedState || rescuedResume) {
        DiagnosticLog.instance.recordEvent(
          source: 'app',
          event: 'tv_resume_rescued',
          fields: <String, Object?>{
            'positionMs': positionMs,
            'durationMs': durationMs,
            'playbackState': rescuedState,
            'videoResume': rescuedResume,
          },
        );
      }
    } finally {
      // Applied or skipped, the snapshot is consumed: a rescue must run at
      // most once per abnormal exit.
      await clearAfterCleanFinish();
    }
  }

  static String? _activeProfileId() {
    if (!ProfileRuntime.isInitialized) return null;
    if (!ProfileRuntime.isProfileCommitted) return 'legacy';
    return ProfileSession.notifier.value?.profileId;
  }

  static Future<File> _file(String name) async {
    final root = await AppStorage.support();
    return File(path.join(root.path, name));
  }

  static Future<Map<String, dynamic>?> _readJson(String name) async {
    try {
      final file = await _file(name);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null; // unreadable == absent; cleanup paths delete it
    }
  }

  static Future<void> _delete(String name) async {
    try {
      final file = await _file(name);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
