import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Exercise real controller/profile preferences with delayed transport completion.
// Durable values, write order and live selection are asserted independently.
const _key = 'tv_motion_profile';

class _DelayedBackend extends InMemorySharedPreferencesStore {
  _DelayedBackend() : super.withData({});
  final attempts = <(String, Object)>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  String firstOutcome = 'ok';

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final first = attempts.isEmpty;
    attempts.add((key, value));
    if (first) {
      entered.complete();
      await release.future.timeout(const Duration(seconds: 5));
      if (firstOutcome == 'false') return false;
      if (firstOutcome == 'throw') {
        throw StateError('injected transport failure');
      }
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _DelayedBackend backend;
  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    backend = _DelayedBackend();
    SharedPreferencesStorePlatform.instance = backend;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    TvMotionController.resetProfileScope();
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    TvMotionController.resetProfileScope();
    ProfileRuntime.debugReset();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  for (final outcome in ['ok', 'false', 'throw']) {
    test(
      'delayed first $outcome write cannot overtake the latest choice',
      () async {
        backend.firstOutcome = outcome;
        final first = TvMotionController.select(TvMotionProfile.smooth);
        await backend.entered.future.timeout(const Duration(seconds: 5));
        final last = TvMotionController.select(TvMotionProfile.snappy);
        try {
          expect(TvMotionController.current, TvMotionProfile.snappy);
          // Allow a wrongly concurrent second write to reach the transport.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(backend.attempts, [('flutter.$_key', 'smooth')]);
        } finally {
          backend.release.complete();
          await Future.wait([first, last]);
        }
        expect(backend.attempts, [
          ('flutter.$_key', 'smooth'),
          ('flutter.$_key', 'snappy'),
        ]);
        expect((await backend.getAll())['flutter.$_key'], 'snappy');
        expect(TvMotionController.current, TvMotionProfile.snappy);
      },
    );
  }

  test(
    'warm queued between selections cannot publish an older choice',
    () async {
      final first = TvMotionController.select(TvMotionProfile.smooth);
      await backend.entered.future.timeout(const Duration(seconds: 5));
      final warm = TvMotionController.warm();
      final last = TvMotionController.select(TvMotionProfile.snappy);
      backend.release.complete();
      await Future.wait([first, warm, last]);
      expect(TvMotionController.current, TvMotionProfile.snappy);
      expect((await backend.getAll())['flutter.$_key'], 'snappy');
    },
  );

  test(
    'queued writes retain profile and generation while incoming warm wins',
    () async {
      final a = ProfileScope(
        profileId: 'a',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final nextGeneration = ProfileScope(
        profileId: 'a',
        dataGeneration: 2,
        sessionEpoch: 2,
      );
      final b = ProfileScope(
        profileId: 'b',
        dataGeneration: 1,
        sessionEpoch: 3,
      );
      ProfileRuntime.initializeCommitted(a);
      final first = TvMotionController.select(TvMotionProfile.smooth);
      await backend.entered.future.timeout(const Duration(seconds: 5));
      TvMotionController.resetProfileScope();
      ProfileRuntime.publish(nextGeneration);
      final second = TvMotionController.select(TvMotionProfile.smooth);
      TvMotionController.resetProfileScope();
      ProfileRuntime.publish(b);
      final incomingWarm = TvMotionController.warm();
      backend.release.complete();
      await Future.wait([first, second, incomingWarm]);
      expect(TvMotionController.current, TvMotionProfile.snappy);
      expect(await backend.getAll(), {
        'flutter.${a.preferenceKey(_key)}': 'smooth',
        'flutter.${nextGeneration.preferenceKey(_key)}': 'smooth',
      });
    },
  );
}
