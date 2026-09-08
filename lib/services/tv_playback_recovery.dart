import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diagnostic_log.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';
import 'storage_service.dart';

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

  /// Runs after profile bootstrap but before the first app frame.
  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid || !ProfileRuntime.isProfileCommitted) {
      return;
    }
    final scope = ProfileRuntime.capture();
    var returning = false;
    try {
      returning =
          await _channel.invokeMethod<bool>('claimPlaybackReturn', {
            'profileId': scope.profileId,
            'dataGeneration': scope.dataGeneration,
          }) ??
          false;
    } catch (_) {
      // A missing/failed native proof must fail closed at the profile gate.
    }
    if (returning) _gateBypass = scope;

    try {
      final encoded = await _channel.invokeMethod<String>('readCheckpoint');
      if (encoded == null || encoded.isEmpty) return;
      final checkpoint = TvPlaybackCheckpoint.tryParse(encoded);
      if (checkpoint == null || !checkpoint.belongsTo(scope)) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final validAge =
          checkpoint.updatedAtMs > 0 &&
          checkpoint.updatedAtMs <= now &&
          now - checkpoint.updatedAtMs <= _staleAfter.inMilliseconds;
      var changed = false;
      if (validAge) {
        changed = await ProfileRuntime.withCapturedScope(scope, () async {
          if (checkpoint.shouldPersistCompletion) {
            return _applyCompletion(checkpoint);
          }
          if (checkpoint.isResumable) {
            return _apply(checkpoint, sameProcessReturn: returning);
          }
          return false;
        });
      }
      await _ack(checkpoint);
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

    if (checkpoint.contentType == 'series') {
      final seriesTitle = checkpoint.seriesTitle ?? checkpoint.title;
      final season = checkpoint.season;
      final episode = checkpoint.episode;
      if (seriesTitle != null && season != null && episode != null) {
        final finished = await StorageService.getMergedFinishedEpisodes(
          seriesTitle: seriesTitle,
          imdbId: checkpoint.imdbId,
        );
        if (!(finished[season.toString()]?.contains(episode) ?? false)) {
          final existing = await StorageService.getSeriesPlaybackState(
            seriesTitle: seriesTitle,
            season: season,
            episode: episode,
          );
          if (checkpoint.shouldApply(
            existing,
            sameProcessReturn: sameProcessReturn,
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
        );
        changed = true;
      }
    }

    final resumeId = checkpoint.resumeId ?? checkpoint.title;
    if (resumeId != null && resumeId.isNotEmpty) {
      var existing = await StorageService.getVideoPlaybackState(
        videoTitle: resumeId,
      );
      final existingUrl = existing?['url'];
      final url =
          checkpoint.url ?? (existingUrl is String ? existingUrl : null);
      var movieFinished =
          checkpoint.contentType == 'single' &&
          checkpoint.imdbId != null &&
          await StorageService.isMovieFinished(checkpoint.imdbId!);
      // Mirror the normal native-progress path: a proven return below the
      // configured local threshold is an active rewatch, not stale progress.
      // Cold journals never clear a watched marker.
      if (movieFinished &&
          sameProcessReturn &&
          checkpoint.isLocalMovieRewatch) {
        await StorageService.unmarkMovieAsFinished(checkpoint.imdbId!);
        movieFinished = false;
        existing = await StorageService.getVideoPlaybackState(
          videoTitle: resumeId,
        );
      }
      if (!movieFinished &&
          url != null &&
          url.isNotEmpty &&
          checkpoint.shouldApply(
            existing,
            sameProcessReturn: sameProcessReturn,
          )) {
        await StorageService.saveVideoPlaybackState(
          videoTitle: resumeId,
          videoUrl: url,
          positionMs: position,
          durationMs: duration,
          speed: checkpoint.speed,
          aspect: checkpoint.aspect,
          imdbId: checkpoint.imdbId,
        );
        changed = true;
      }

      if (checkpoint.contentType == 'single') {
        final resume = await StorageService.getVideoResume(resumeId);
        if (!movieFinished &&
            checkpoint.shouldApply(
              resume,
              sameProcessReturn: sameProcessReturn,
            )) {
          await StorageService.upsertVideoResume(resumeId, {
            'positionMs': position,
            'durationMs': duration,
            'speed': checkpoint.speed,
            'aspect': checkpoint.aspect,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
          changed = true;
        }
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
      await StorageService.markEpisodeAsFinished(
        seriesTitle: seriesTitle,
        season: season,
        episode: episode,
        imdbId: checkpoint.imdbId,
      );
      return true;
    }
    if (checkpoint.contentType == 'collection') {
      final seriesTitle = checkpoint.seriesTitle;
      if (seriesTitle == null) return false;
      await StorageService.markEpisodeAsFinished(
        seriesTitle: seriesTitle,
        season: 0,
        episode: checkpoint.itemIndex + 1,
        imdbId: checkpoint.imdbId,
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
    await Future.wait([
      StorageService.markMovieAsFinished(imdbId),
      if (checkpoint.resumeId case final resumeId? when resumeId.isNotEmpty)
        StorageService.removeVideoResume(resumeId),
    ]);
    return true;
  }

  static Future<void> _ack(TvPlaybackCheckpoint checkpoint) async {
    await _channel.invokeMethod<bool>('ackCheckpoint', {
      'sessionId': checkpoint.sessionId,
      'sequence': checkpoint.sequence,
    });
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
      positionMs * 100.0 / durationMs < 95.0;

  bool shouldApply(
    Map<String, dynamic>? existing, {
    required bool sameProcessReturn,
  }) {
    // The process-memory handoff proves this is the newest position from the
    // same playback, including an intentional rewind. A cold-process journal
    // remains conservative: it may only deepen an existing owned record.
    if (sameProcessReturn) return true;
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
          !const {'single', 'series', 'collection'}.contains(contentType)) {
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
        seriesTitle: _string(decoded['seriesTitle']),
        imdbId: _string(decoded['imdbId']),
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
}
