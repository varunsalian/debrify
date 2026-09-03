import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../utils/app_storage.dart';
import 'diagnostic_log.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';
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
///  * it applies to SINGLE content only: series/collection progress is
///    authoritative in the series playback-state store, whose watched-union
///    and ghost-purge invariants a rescue must not write around;
///  * it only runs for the profile that was playing — the storage writes are
///    executed under that captured [ProfileScope], so a profile switch racing
///    the reconcile cannot redirect them (codex review round 1, finding 4);
///  * a position snapshot older than its owner's launch stamp is discarded,
///    so a straggler write from a previous session can never pair with a new
///    owner (codex review round 1, finding 5).
///
/// The existing-row and deepen-only checks read immediately before writing;
/// a concurrent writer in that gap (remote import, sync apply) could still
/// interleave, but the reconcile runs once at startup before the UI exists,
/// and the staged value is at most one crash old — the same trust the live
/// 5-second path already extends (codex review round 1, finding 3: accepted).
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
  static bool _pendingKick = false;
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
    if (_running) {
      // A profile activation arrived mid-reconcile; run again when the
      // current pass finishes instead of dropping the notification.
      _pendingKick = true;
      return;
    }
    _running = true;
    try {
      do {
        _pendingKick = false;
        await _reconcile();
      } while (_pendingKick);
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

    // Type-defensive extraction: a corrupt-but-parseable stage must land in a
    // cleanup path, not throw past it and wedge every later activation on the
    // same files (codex review round 1, finding 10).
    final ownerProfileId = _asString(owner['profileId']);
    final launchedAtMs = _asInt(owner['launchedAtMs']);
    final updatedAtMs = _asInt(position['updatedAtMs']);
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
    if (updatedAtMs <= 0 || age > _staleAfter || age.isNegative) {
      await clearAfterCleanFinish();
      return;
    }
    // Session binding: the position must postdate its owner's launch. A
    // queued stage write draining from a PREVIOUS session carries an older
    // stamp and must not pair with this owner.
    if (launchedAtMs <= 0 || updatedAtMs < launchedAtMs) {
      await clearAfterCleanFinish();
      return;
    }
    if (ownerProfileId == null || ownerProfileId != activeId) {
      // Another profile's session: leave the stage for its activation, which
      // lands here again through the scope listener.
      return;
    }

    // Pin the verified profile for the storage work below. In committed mode
    // the zone override makes every StorageService call resolve to this
    // scope even if the active profile changes mid-await; legacy mode has no
    // scopes to race.
    final ProfileScope? capturedScope =
        ProfileRuntime.isProfileCommitted ? ProfileSession.notifier.value : null;
    if (ProfileRuntime.isProfileCommitted && capturedScope == null) return;

    try {
      final resumeId = _asString(position['resumeId']);
      final positionMs = _asInt(position['positionMs']);
      final durationMs = _asInt(position['durationMs']);
      final stagedUrl = _asString(position['url']);
      final contentType = _asString(owner['contentType']);
      final imdbId = _asString(owner['imdbId']);
      if (resumeId == null ||
          resumeId.isEmpty ||
          contentType != 'single' ||
          positionMs <= 0 ||
          durationMs <= 0 ||
          positionMs * 100.0 / durationMs >= _maxRescuePercent) {
        return;
      }

      Future<void> applyRescue() async {
        var rescuedState = false;
        var rescuedResume = false;

        // Playback-state map (drives Continue Watching). Deepen-only, and
        // only an entry the live path already created; getVideoPlaybackState
        // also returns null for a movie marked finished, which keeps a rescue
        // from resurrecting a completed one.
        final state = await StorageService.getVideoPlaybackState(
          videoTitle: resumeId,
        );
        final stateUrl = (stagedUrl != null && stagedUrl.isNotEmpty)
            ? stagedUrl
            : _asString(state?['url']);
        if (state != null &&
            stateUrl != null &&
            _asInt(state['positionMs']) < positionMs) {
          await StorageService.saveVideoPlaybackState(
            videoTitle: resumeId,
            videoUrl: stateUrl,
            positionMs: positionMs,
            durationMs: durationMs,
            speed: (state['speed'] as num?)?.toDouble() ?? 1.0,
            aspect: _asString(state['aspect']) ?? 'contain',
            imdbId: imdbId ?? _asString(state['imdbId']),
          );
          rescuedState = true;
        }

        // The per-video resume store — the second sink the live path writes
        // for single content.
        final resume = await StorageService.getVideoResume(resumeId);
        if (resume != null && _asInt(resume['positionMs']) < positionMs) {
          await StorageService.upsertVideoResume(resumeId, {
            'positionMs': positionMs,
            'durationMs': durationMs,
            'speed': (resume['speed'] as num?)?.toDouble() ?? 1.0,
            'aspect': _asString(resume['aspect']) ?? 'contain',
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
          rescuedResume = true;
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
      }

      if (capturedScope != null) {
        await ProfileRuntime.withCapturedScope(capturedScope, applyRescue);
      } else {
        await applyRescue();
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

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;

  static String? _asString(Object? value) => value is String ? value : null;

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
