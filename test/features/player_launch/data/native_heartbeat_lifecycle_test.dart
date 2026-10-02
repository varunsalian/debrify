import 'package:debrify/features/player_launch/data/android_tv_playback_payload.dart';
import 'package:debrify/features/player_launch/data/native_progress_handler.dart';
import 'package:debrify/features/player_launch/data/native_scrobble_session.dart';
import 'package:debrify/features/player_launch/models/playback_content_type.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AndroidTvPlaybackPayload _payload() => AndroidTvPlaybackPayload(
  contentType: PlaybackContentType.single,
  title: 'Playback session',
  subtitle: null,
  items: const [],
  startIndex: 0,
  seriesTitle: null,
  seasons: const [],
  imdbId: 'tt1234567',
  traktScrobble: true,
  simklScrobble: true,
);

Map<String, dynamic> _progress({bool playing = true, bool completed = false}) =>
    {
      'positionMs': completed ? 900 : 250,
      'durationMs': 1000,
      'isPlaying': playing,
      'completed': completed,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalDebugPrint = debugPrint;
  final logs = <String>[];
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    TraktService.instance.resetProfileScope();
    NativeScrobbleSession.traktLastScrobbleAction = null;
    NativeScrobbleSession.simklLastScrobbleAction = null;
    logs.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });
  tearDown(() {
    NativeScrobbleSession.traktHeartbeatTimer?.cancel();
    NativeScrobbleSession.traktHeartbeatTimer = null;
    NativeScrobbleSession.simklHeartbeatTimer?.cancel();
    NativeScrobbleSession.simklHeartbeatTimer = null;
    TraktService.instance.resetProfileScope();
    ProfileRuntime.debugReset();
    debugPrint = originalDebugPrint;
  });

  test('both heartbeats start once and checkpoint at two-minute intervals', () {
    fakeAsync((clock) {
      final payload = _payload();
      NativeProgressHandler.handleProgressUpdate(payload, _progress());
      clock.flushMicrotasks();
      final trakt = NativeScrobbleSession.traktHeartbeatTimer!;
      final simkl = NativeScrobbleSession.simklHeartbeatTimer!;
      expect(clock.periodicTimerCount, 2);
      NativeProgressHandler.handleProgressUpdate(payload, _progress());
      clock.flushMicrotasks();
      expect(NativeScrobbleSession.traktHeartbeatTimer, same(trakt));
      expect(NativeScrobbleSession.simklHeartbeatTimer, same(simkl));
      clock.elapse(const Duration(seconds: 119));
      expect(logs.where((log) => log.contains('Heartbeat')), isEmpty);
      clock.elapse(const Duration(seconds: 1));
      expect(logs.where((log) => log.contains('Heartbeat')), hasLength(2));
      expect(NativeScrobbleSession.traktLastScrobbleAction, 'start');
      expect(NativeScrobbleSession.simklLastScrobbleAction, 'start');
      clock.elapse(const Duration(minutes: 2));
      expect(logs.where((log) => log.contains('Heartbeat')), hasLength(4));
      NativeProgressHandler.handlePlaybackFinished(payload);
      clock.flushMicrotasks();
      expect(clock.periodicTimerCount, 0);
    });
  });

  for (final completed in [false, true]) {
    test('pause/completion cancels both timers: completed=$completed', () {
      fakeAsync((clock) {
        final payload = _payload();
        NativeProgressHandler.handleProgressUpdate(payload, _progress());
        clock.flushMicrotasks();
        final trakt = NativeScrobbleSession.traktHeartbeatTimer!;
        final simkl = NativeScrobbleSession.simklHeartbeatTimer!;
        NativeProgressHandler.handleProgressUpdate(
          payload,
          _progress(playing: false, completed: completed),
        );
        clock.flushMicrotasks();
        expect(trakt.isActive, isFalse);
        expect(simkl.isActive, isFalse);
        expect(NativeScrobbleSession.traktHeartbeatTimer, isNull);
        expect(NativeScrobbleSession.simklHeartbeatTimer, isNull);
        expect(
          NativeScrobbleSession.traktLastScrobbleAction,
          completed ? 'stop' : 'pause',
        );
        expect(
          NativeScrobbleSession.simklLastScrobbleAction,
          completed ? 'stop' : 'pause',
        );
        clock.elapse(const Duration(minutes: 4));
        expect(logs.where((log) => log.contains('Heartbeat')), isEmpty);
        NativeProgressHandler.handlePlaybackFinished(payload);
        clock.flushMicrotasks();
      });
    });
  }

  test('finish cancels both heartbeats before resetting session state', () {
    fakeAsync((clock) {
      final payload = _payload();
      NativeProgressHandler.handleProgressUpdate(payload, _progress());
      clock.flushMicrotasks();
      final trakt = NativeScrobbleSession.traktHeartbeatTimer!;
      final simkl = NativeScrobbleSession.simklHeartbeatTimer!;
      NativeProgressHandler.handlePlaybackFinished(payload);
      clock.flushMicrotasks();
      expect(trakt.isActive, isFalse);
      expect(simkl.isActive, isFalse);
      expect(clock.periodicTimerCount, 0);
      expect(NativeScrobbleSession.traktLastScrobbleAction, isNull);
      expect(NativeScrobbleSession.simklLastScrobbleAction, isNull);
      expect(NativeScrobbleSession.traktLastKnownProgress, 0);
      expect(NativeScrobbleSession.simklLastKnownProgress, 0);
      clock.elapse(const Duration(minutes: 4));
      expect(logs.where((log) => log.contains('Heartbeat')), isEmpty);
    });
  });
}
