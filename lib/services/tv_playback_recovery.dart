import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diagnostic_log.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';
import 'storage_service.dart';
import 'webdav_sync/webdav_sync_tombstones.dart';

/// Restores the two pieces of state lost when Android reclaims MainActivity
/// underneath the separate native TV player: the unlocked return path and the
/// latest locally persisted playback position.
class TvPlaybackRecovery {
  TvPlaybackRecovery._();

  static const MethodChannel _channel = MethodChannel(
    'debrify/tv_playback_recovery',
  );
  static const Duration _staleAfter = Duration(days: 7);
  static ProfileScope? _gateBypass;
  static int _fallbackSessionId = Random().nextInt(0x7ffffffe) + 1;

  static Future<int> allocateSessionId() async {
    try {
      final id = await _channel.invokeMethod<int>('allocatePlaybackSession');
      if (id == null || id <= 0 || id > 0x7fffffff) {
        throw StateError('Missing native playback session');
      }
      return id;
    } catch (error, stackTrace) {
      DiagnosticLog.instance.recordError(
        source: 'tv_playback_recovery',
        event: 'session_allocation_fallback',
        durable: true,
        error: error,
        stackTrace: stackTrace,
      );
      // Keep the signed Int range expected by Android. A random isolate seed
      // plus a counter remains usable even when the recovery channel fails.
      _fallbackSessionId = _fallbackSessionId == 0x7fffffff
          ? 1
          : _fallbackSessionId + 1;
      return _fallbackSessionId;
    }
  }

  /// Runs after profile bootstrap but before the first app frame.
  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid || !ProfileRuntime.isProfileCommitted) {
      return;
    }
    final scope = ProfileRuntime.capture();
    int? returningSessionId;
    try {
      returningSessionId = await _channel.invokeMethod<int>(
        'claimPlaybackReturnSession',
        {'profileId': scope.profileId, 'dataGeneration': scope.dataGeneration},
      );
    } catch (_) {
      // A missing/failed native proof must fail closed at the profile gate.
    }
    if (returningSessionId != null) _gateBypass = scope;

    try {
      final encoded = await _channel.invokeMethod<String>('readCheckpoint');
      if (encoded == null || encoded.isEmpty) return;
      await recoverJournal(
        encoded,
        scope: scope,
        returningSessionId: returningSessionId,
        apply: (checkpoint, sameProcessReturn) =>
            ProfileRuntime.withCapturedScope(
              scope,
              () => applyCheckpoint(
                checkpoint,
                sameProcessReturn: sameProcessReturn,
              ),
            ),
        acknowledge: _ack,
        discard: (value) async {
          await _channel.invokeMethod<bool>('discardCheckpoint', {
            'encoded': value,
          });
        },
      );
    } catch (error, stackTrace) {
      // Keep an unacknowledged checkpoint for the next launch. A transient DB
      // or channel failure must never turn recovery into data loss.
      DiagnosticLog.instance.recordError(
        source: 'tv_playback_recovery',
        event: 'checkpoint_apply_failed',
        durable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// ACK each successful record separately. A later failure must neither lose
  /// earlier completions nor consume a different profile's pending recovery.
  @visibleForTesting
  static Future<void> recoverJournal(
    String encoded, {
    required ProfileScope scope,
    int? returningSessionId,
    required Future<bool> Function(TvPlaybackCheckpoint, bool) apply,
    required Future<void> Function(TvPlaybackCheckpoint) acknowledge,
    required Future<void> Function(String) discard,
  }) async {
    final journal = TvPlaybackJournal.tryParse(encoded);
    if (journal == null) {
      await discard(encoded);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    bool validAge(TvPlaybackCheckpoint checkpoint) =>
        checkpoint.updatedAtMs > 0 &&
        checkpoint.updatedAtMs <= now &&
        now - checkpoint.updatedAtMs <= _staleAfter.inMilliseconds;
    // Episode/collection watched markers survive a rewatch; their completions
    // and positions have separate lifetimes. Movies deliberately unmark on
    // rewatch, so only their newest observation should be applied.
    String recoveryKey(TvPlaybackCheckpoint checkpoint) =>
        '${checkpoint.itemKey}:${checkpoint.contentType != 'single' && checkpoint.shouldPersistCompletion ? 'completion' : 'position'}';
    final newestByItem = <String, TvPlaybackCheckpoint>{
      for (final checkpoint in journal.records)
        if (validAge(checkpoint)) recoveryKey(checkpoint): checkpoint,
    };
    await WebDavSyncTombstoneRecorder.withPlaybackRecoverySnapshot(() async {
      for (final checkpoint in journal.records) {
        final isValidAge = validAge(checkpoint);
        if (isValidAge && checkpoint.profileId != scope.profileId) continue;
        var changed = false;
        final returning = checkpoint.sessionId == returningSessionId;
        if (isValidAge &&
            checkpoint.belongsTo(scope) &&
            identical(newestByItem[recoveryKey(checkpoint)], checkpoint)) {
          changed = await apply(checkpoint, returning);
        }
        await acknowledge(checkpoint);
        DiagnosticLog.instance.recordEvent(
          source: 'tv_playback_recovery',
          event: changed ? 'checkpoint_applied' : 'checkpoint_consumed',
          durable: true,
          fields: <String, Object?>{
            'session': checkpoint.sessionId,
            'sameProcessReturn': returning,
            'contentType': DiagnosticLabel(checkpoint.contentType),
          },
        );
      }
    });
  }

  @visibleForTesting
  static Future<bool> applyCheckpoint(
    TvPlaybackCheckpoint checkpoint, {
    required bool sameProcessReturn,
  }) async {
    final episodeCompletion =
        checkpoint.contentType != 'single' &&
        checkpoint.shouldPersistCompletion;
    if (await StorageService.hasNewerPlaybackRecoveryIntent(
      seriesTitle: checkpoint.contentType == 'single'
          ? null
          : checkpoint.seriesTitle ?? checkpoint.title,
      season: checkpoint.contentType == 'collection' ? 0 : checkpoint.season,
      episode: checkpoint.contentType == 'collection'
          ? checkpoint.itemIndex + 1
          : checkpoint.episode,
      imdbId: checkpoint.imdbId,
      resumeId: checkpoint.resumeId ?? checkpoint.title,
      checkpointAtMs: checkpoint.updatedAtMs,
      includePositions: !sameProcessReturn && !episodeCompletion,
      includeSyncedPositions: !episodeCompletion,
      isOwnRecoveryWrite: checkpoint.isOwnRecoveryWrite,
      matchesRecoveryPosition: checkpoint.matchesRecoveryPosition,
    )) {
      return false;
    }
    if (checkpoint.shouldPersistCompletion) return _applyCompletion(checkpoint);
    if (checkpoint.isResumable) {
      return _apply(checkpoint, sameProcessReturn: sameProcessReturn);
    }
    return false;
  }

  /// One-shot, exact-scope bypass consumed by ProfileGate's startup load.
  static bool consumeGateBypass(ProfileScope scope) {
    final pending = _gateBypass;
    if (pending == null ||
        pending.profileId != scope.profileId ||
        pending.dataGeneration != scope.dataGeneration) {
      return false;
    }
    _gateBypass = null;
    return true;
  }

  static Future<bool> _apply(
    TvPlaybackCheckpoint checkpoint, {
    required bool sameProcessReturn,
  }) async {
    final position = checkpoint.positionMs;
    final duration = checkpoint.durationMs;
    var changed = false;
    final resumeId = checkpoint.resumeId ?? checkpoint.title;
    final videoState = resumeId == null || resumeId.isEmpty
        ? null
        : await StorageService.getVideoPlaybackState(
            videoTitle: resumeId,
            includeFinished: true,
          );
    final seriesTitle = checkpoint.seriesTitle ?? checkpoint.title;
    final season = checkpoint.contentType == 'collection'
        ? 0
        : checkpoint.season;
    final episode = checkpoint.contentType == 'collection'
        ? checkpoint.itemIndex + 1
        : checkpoint.episode;
    final seriesState =
        checkpoint.contentType == 'single' ||
            seriesTitle == null ||
            season == null ||
            episode == null
        ? null
        : await StorageService.getSeriesPlaybackState(
            seriesTitle: seriesTitle,
            season: season,
            episode: episode,
          );
    // A receipt in either preference record proves this exact checkpoint was
    // admitted before a partial failure. Retry only its missing/older writes;
    // genuine later writes and deletion intent still fence the whole replay.
    final retrying =
        checkpoint.isOwnRecoveryWrite(videoState) ||
        checkpoint.isOwnRecoveryWrite(seriesState);

    if (checkpoint.contentType == 'series') {
      final seriesTitle = checkpoint.seriesTitle ?? checkpoint.title;
      final season = checkpoint.season;
      final episode = checkpoint.episode;
      if (seriesTitle != null && season != null && episode != null) {
        final finished = await StorageService.getMergedFinishedEpisodes(
          seriesTitle: seriesTitle,
          imdbId: checkpoint.imdbId,
        );
        // A watched marker and a rewatch bookmark are independent. A proven
        // return (or an already-admitted retry) can restore the position while
        // saveSeriesPlaybackState leaves the watched marker intact.
        if (!(finished[season.toString()]?.contains(episode) ?? false) ||
            sameProcessReturn ||
            retrying) {
          final existing = await StorageService.getSeriesPlaybackState(
            seriesTitle: seriesTitle,
            season: season,
            episode: episode,
          );
          if (checkpoint.shouldApply(
            existing,
            sameProcessReturn: sameProcessReturn,
            retrying: retrying,
          )) {
            await StorageService.saveSeriesPlaybackState(
              seriesTitle: seriesTitle,
              season: season,
              episode: episode,
              positionMs: position,
              durationMs: duration,
              speed: checkpoint.speed,
              aspect: checkpoint.aspect,
              imdbId: checkpoint.imdbId,
              recoveryCheckpointId: checkpoint.recoveryId,
              recoveryUpdatedAtMs: checkpoint.updatedAtMs,
            );
            changed = true;
          }
        }
      }
    } else if (checkpoint.contentType == 'collection' &&
        checkpoint.seriesTitle != null) {
      final episode = checkpoint.itemIndex + 1;
      final existing = await StorageService.getSeriesPlaybackState(
        seriesTitle: checkpoint.seriesTitle!,
        season: 0,
        episode: episode,
      );
      if (checkpoint.shouldApply(
        existing,
        sameProcessReturn: sameProcessReturn,
        retrying: retrying,
      )) {
        await StorageService.saveSeriesPlaybackState(
          seriesTitle: checkpoint.seriesTitle!,
          season: 0,
          episode: episode,
          positionMs: position,
          durationMs: duration,
          speed: checkpoint.speed,
          aspect: checkpoint.aspect,
          imdbId: checkpoint.imdbId,
          recoveryCheckpointId: checkpoint.recoveryId,
          recoveryUpdatedAtMs: checkpoint.updatedAtMs,
        );
        changed = true;
      }
    }

    if (resumeId != null && resumeId.isNotEmpty) {
      final existing = videoState;
      final existingUrl = existing?['url'];
      final url =
          checkpoint.url ?? (existingUrl is String ? existingUrl : null);
      final movieFinished =
          checkpoint.contentType == 'single' &&
          checkpoint.imdbId != null &&
          await StorageService.isMovieFinished(checkpoint.imdbId!);
      // Mirror the normal native-progress path: a proven return below the
      // configured local threshold is an active rewatch, not stale progress.
      // A cold retry may finish an already-admitted rewatch. Remove the watched
      // marker only after both resume stores succeed, so its own unwatch
      // tombstone cannot discard a retry between those writes.
      final rewatch =
          movieFinished &&
          (sameProcessReturn || retrying) &&
          checkpoint.isLocalMovieRewatch;
      if ((!movieFinished || rewatch) &&
          url != null &&
          url.isNotEmpty &&
          checkpoint.shouldApply(
            existing,
            sameProcessReturn: sameProcessReturn,
            retrying: retrying,
          )) {
        await StorageService.saveVideoPlaybackState(
          videoTitle: resumeId,
          videoUrl: url,
          positionMs: position,
          durationMs: duration,
          speed: checkpoint.speed,
          aspect: checkpoint.aspect,
          imdbId: checkpoint.imdbId,
          recoveryCheckpointId: checkpoint.recoveryId,
          recoveryUpdatedAtMs: checkpoint.updatedAtMs,
        );
        changed = true;
      }

      if (checkpoint.contentType == 'single') {
        final resume = await StorageService.getVideoResume(resumeId);
        if ((!movieFinished || rewatch) &&
            checkpoint.shouldApply(
              resume,
              sameProcessReturn: sameProcessReturn,
              retrying: retrying,
            )) {
          await StorageService.upsertVideoResume(resumeId, {
            'positionMs': position,
            'durationMs': duration,
            'speed': checkpoint.speed,
            'aspect': checkpoint.aspect,
            'updatedAt': checkpoint.updatedAtMs,
          });
          changed = true;
        }
      }
      if (rewatch) {
        await StorageService.unmarkMovieAsFinished(checkpoint.imdbId!);
        changed = true;
      }
    }
    return changed;
  }

  static Future<bool> _applyCompletion(TvPlaybackCheckpoint checkpoint) async {
    if (checkpoint.contentType == 'series') {
      final seriesTitle = checkpoint.seriesTitle ?? checkpoint.title;
      final season = checkpoint.season;
      final episode = checkpoint.episode;
      if (seriesTitle == null || season == null || episode == null) {
        return false;
      }
      final finished = await StorageService.getMergedFinishedEpisodes(
        seriesTitle: seriesTitle,
        imdbId: checkpoint.imdbId,
      );
      if (finished[season.toString()]?.contains(episode) ?? false) return false;
      await StorageService.markEpisodeAsFinished(
        seriesTitle: seriesTitle,
        season: season,
        episode: episode,
        imdbId: checkpoint.imdbId,
        recoveryUpdatedAtMs: checkpoint.updatedAtMs,
      );
      return true;
    }
    if (checkpoint.contentType == 'collection') {
      final seriesTitle = checkpoint.seriesTitle;
      if (seriesTitle == null) return false;
      if (await StorageService.isEpisodeFinished(
        seriesTitle: seriesTitle,
        season: 0,
        episode: checkpoint.itemIndex + 1,
      )) {
        return false;
      }
      await StorageService.markEpisodeAsFinished(
        seriesTitle: seriesTitle,
        season: 0,
        episode: checkpoint.itemIndex + 1,
        imdbId: checkpoint.imdbId,
        recoveryUpdatedAtMs: checkpoint.updatedAtMs,
      );
      return true;
    }
    final imdbId = checkpoint.imdbId;
    if (checkpoint.contentType != 'single' ||
        !checkpoint.localCompletionTracking ||
        imdbId == null ||
        imdbId.isEmpty) {
      return false;
    }
    // Finish the database operation before completion cleanup stamps deletion
    // intent. A failed DB delete must remain retryable against the old state.
    final resumeId = checkpoint.resumeId ?? checkpoint.title;
    if (resumeId != null && resumeId.isNotEmpty) {
      await StorageService.removeVideoResume(resumeId);
    }
    await StorageService.markMovieAsFinished(imdbId);
    return true;
  }

  static Future<void> _ack(TvPlaybackCheckpoint checkpoint) async {
    final acknowledged = await _channel.invokeMethod<bool>('ackCheckpoint', {
      'sessionId': checkpoint.sessionId,
      'sequence': checkpoint.sequence,
    });
    if (acknowledged != true) throw StateError('Checkpoint ACK failed');
  }

  /// A surviving Flutter host received the normal finish callback, so no
  /// recreated gate needs the process-memory continuation token.
  static Future<void> cancelReturn(int? sessionId) async {
    if (sessionId == null || sessionId <= 0 || kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('cancelPlaybackReturn', {
        'sessionId': sessionId,
      });
    } catch (_) {
      // The token expires quickly and remains exact-profile/one-shot.
    }
  }

  @visibleForTesting
  static void debugReset() => _gateBypass = null;

  @visibleForTesting
  static void debugSetGateBypass(ProfileScope scope) => _gateBypass = scope;
}

@immutable
class TvPlaybackCheckpoint {
  const TvPlaybackCheckpoint({
    required this.sessionId,
    required this.sequence,
    required this.profileId,
    required this.dataGeneration,
    required this.updatedAtMs,
    required this.contentType,
    required this.positionMs,
    required this.durationMs,
    required this.speed,
    required this.aspect,
    required this.itemIndex,
    required this.completed,
    required this.completionReached,
    required this.localCompleted,
    required this.localCompletionEligible,
    required this.localCompletionReached,
    required this.localCompletionTracking,
    required this.completionThreshold,
    this.title,
    this.seriesTitle,
    this.imdbId,
    this.resumeId,
    this.url,
    this.season,
    this.episode,
  });

  final int sessionId;
  final int sequence;
  final String profileId;
  final int dataGeneration;
  final int updatedAtMs;
  final String contentType;
  final String? title;
  final String? seriesTitle;
  final String? imdbId;
  final String? resumeId;
  final String? url;
  final int? season;
  final int? episode;
  final int itemIndex;
  final int positionMs;
  final int durationMs;
  final double speed;
  final String aspect;
  final bool completed;
  final bool completionReached;
  final bool localCompleted;
  final bool localCompletionEligible;
  final bool localCompletionReached;
  final bool localCompletionTracking;
  final int completionThreshold;

  String get itemKey => jsonEncode([
    profileId,
    dataGeneration,
    contentType,
    imdbId ??
        (contentType == 'single' ? resumeId ?? title : seriesTitle ?? title),
    if (contentType == 'series') ...[season, episode],
    if (contentType == 'collection') itemIndex,
  ]);

  bool belongsTo(ProfileScope scope) =>
      profileId == scope.profileId && dataGeneration == scope.dataGeneration;

  bool get shouldPersistCompletion => switch (contentType) {
    'series' =>
      completed ||
          completionReached ||
          localCompleted ||
          localCompletionEligible ||
          localCompletionReached,
    'collection' => completed || completionReached,
    'single' =>
      localCompletionTracking &&
          imdbId != null &&
          imdbId!.isNotEmpty &&
          (completed ||
              completionReached ||
              localCompleted ||
              localCompletionEligible ||
              localCompletionReached),
    _ => false,
  };

  bool get isLocalMovieRewatch =>
      contentType == 'single' &&
      localCompletionTracking &&
      !shouldPersistCompletion &&
      positionMs > 0 &&
      durationMs > 0 &&
      positionMs * 100.0 / durationMs < completionThreshold;

  bool get isResumable =>
      sessionId > 0 &&
      sequence > 0 &&
      positionMs > 0 &&
      durationMs > 0 &&
      !shouldPersistCompletion &&
      // The live movie path saves progress even near the end when no local
      // watched marker applies (tracker-managed movies and unidentified files).
      (contentType == 'single' || positionMs * 100.0 / durationMs < 95.0);

  String get recoveryId =>
      jsonEncode([profileId, dataGeneration, sessionId, sequence, updatedAtMs]);

  bool matchesRecoveryPosition(Map<String, dynamic>? state) =>
      state != null &&
      _int(state['updatedAt']) == updatedAtMs &&
      _int(state['positionMs']) == positionMs &&
      _int(state['durationMs']) == durationMs &&
      state['speed'] == speed &&
      state['aspect'] == aspect;

  bool isOwnRecoveryWrite(Map<String, dynamic>? state) =>
      state?['recoveryCheckpointId'] == recoveryId &&
      matchesRecoveryPosition(state);

  bool shouldApply(
    Map<String, dynamic>? existing, {
    required bool sameProcessReturn,
    bool retrying = false,
  }) {
    // The process-memory handoff proves this is the newest position from the
    // same playback, including an intentional rewind. A cold-process journal
    // remains conservative: it may only deepen an existing owned record.
    if (isOwnRecoveryWrite(existing)) return false;
    if (sameProcessReturn && !retrying) return true;
    if (_int(existing?['updatedAt']) >= updatedAtMs) return false;
    if (retrying) return true;
    if (existing == null) return false;
    return _int(existing['positionMs']) < positionMs;
  }

  static TvPlaybackCheckpoint? tryParse(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      final profileId = _string(decoded['profileId']);
      final contentType = _string(decoded['contentType']);
      if (profileId == null ||
          profileId.isEmpty ||
          contentType == null ||
          !const {'single', 'series', 'collection'}.contains(contentType) ||
          decoded['mode'] == 'iptv' ||
          _int(decoded['sessionId']) <= 0 ||
          _int(decoded['sequence']) <= 0 ||
          _int(decoded['dataGeneration']) <= 0) {
        return null;
      }
      return TvPlaybackCheckpoint(
        sessionId: _int(decoded['sessionId']),
        sequence: _int(decoded['sequence']),
        profileId: profileId,
        dataGeneration: _int(decoded['dataGeneration']),
        updatedAtMs: _int(decoded['updatedAtMs']),
        contentType: contentType,
        title: _string(decoded['title']),
        seriesTitle: _identity(decoded['seriesTitle']),
        imdbId: _identity(decoded['imdbId']),
        resumeId: _string(decoded['resumeId']),
        url: _string(decoded['url']),
        season: _nullableInt(decoded['season']),
        episode: _nullableInt(decoded['episode']),
        itemIndex: _int(decoded['itemIndex']),
        positionMs: _int(decoded['positionMs']),
        durationMs: _int(decoded['durationMs']),
        speed: (decoded['speed'] as num?)?.toDouble() ?? 1.0,
        aspect: _string(decoded['aspect']) ?? 'contain',
        completed: decoded['completed'] == true,
        completionReached: decoded['completionReached'] == true,
        localCompleted: decoded['localCompleted'] == true,
        localCompletionEligible: decoded['localCompletionEligible'] == true,
        localCompletionReached: decoded['localCompletionReached'] == true,
        localCompletionTracking: decoded['localCompletionTracking'] == true,
        completionThreshold: _completionThreshold(
          decoded['completionThreshold'],
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;
  static int _completionThreshold(Object? value) {
    final parsed = _int(value);
    return (parsed == 0 ? 80 : parsed).clamp(50, 95);
  }

  static int? _nullableInt(Object? value) =>
      value is num ? value.toInt() : null;
  static String? _string(Object? value) => value is String ? value : null;

  // Older Android checkpoints may already contain an optString-coerced null.
  static String? _identity(Object? value) =>
      value is String && value.trim().isNotEmpty && value.trim() != 'null'
      ? value
      : null;
}

@immutable
class TvPlaybackJournal {
  const TvPlaybackJournal(this.records);
  final List<TvPlaybackCheckpoint> records;

  static TvPlaybackJournal? tryParse(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['version'] == 1) {
        final checkpoint = TvPlaybackCheckpoint.tryParse(encoded);
        return checkpoint == null ? null : TvPlaybackJournal([checkpoint]);
      }
      if (decoded['version'] != 2 ||
          decoded['completions'] is! List ||
          decoded['latest'] is! List) {
        return null;
      }
      final records = <TvPlaybackCheckpoint>[];
      for (final value in [
        ...decoded['completions'] as List,
        ...decoded['latest'] as List,
      ]) {
        final checkpoint = TvPlaybackCheckpoint.tryParse(jsonEncode(value));
        if (checkpoint != null) records.add(checkpoint);
      }
      if (records.isEmpty) return null;
      // Replay chronologically, retaining completion-before-position ordering
      // within a session, including journals retained from a previous launch.
      records.sort(
        (a, b) => a.updatedAtMs.compareTo(b.updatedAtMs) != 0
            ? a.updatedAtMs.compareTo(b.updatedAtMs)
            : a.sessionId != b.sessionId
            ? a.sessionId.compareTo(b.sessionId)
            : a.sequence.compareTo(b.sequence),
      );
      return TvPlaybackJournal(List.unmodifiable(records));
    } catch (_) {
      return null;
    }
  }
}
