import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/player_launch/data/android_tv_payload_builder.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/services/ledger/ledger_api.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:debrify/services/ledger/ledger_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends LedgerSession {
  @override
  Future<bool> isAuthenticated({bool Function()? canContinue}) async => true;

  @override
  Future<String?> accessToken() async => 'token';

  @override
  Future<String?> renewAfterRejection(String rejectedToken) async => null;
}

/// Android TV's native player only knows the launch percent, so a movie's
/// Ledger resume point is read while the payload is built: under the same
/// rule as the in-app player, and never long enough to hold the launch.
void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRuntime.debugReset();
    ProfileSessionMemory.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  late int reads;
  LedgerService server(Future<http.Response> Function() respond) {
    reads = 0;
    final session = _SignedIn();
    return LedgerService.forTesting(
      session: session,
      api: LedgerApi(
        tokens: session,
        baseUrl: 'https://ledger.test',
        client: MockClient((_) {
          reads++;
          return respond();
        }),
      ),
    );
  }

  Future<http.Response> resumePoint() async => http.Response(
    jsonEncode({
      'playback': [
        {
          'id': 'p',
          'item': {
            'kind': 'MEDIA_KIND_MOVIE',
            'ids': {'imdb': 'tt0133093'},
          },
          'progress': 42,
        },
      ],
    }),
    200,
  );

  Future<double?> launchPercent(
    LedgerService ledger, {
    bool ledgerScrobble = false,
  }) async {
    final result = await AndroidTvPlaybackPayloadBuilder(
      VideoPlayerLaunchArgs(
        videoUrl: 'https://player.test/movie.mp4',
        title: 'Movie',
        contentImdbId: 'tt0133093',
        contentType: 'movie',
        ledgerScrobble: ledgerScrobble,
      ),
      ledger: ledger,
    ).build();
    return result!.payload.ledgerProgressPercent;
  }

  test('Ledger Progress source resumes a movie without scrobbling', () async {
    // The policy maps a Ledger choice without a session to Smart, so the
    // credential check sees a stored session.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ledger_access_token': 'stored',
    });
    await TrackingSourceStorage.setWatchProgressSource(
      WatchProgressSource.ledger,
    );
    expect(
      (await TrackingSourcePolicy.load()).progressSource,
      WatchProgressSource.ledger,
    );
    expect(await launchPercent(server(resumePoint)), 42);
    expect(reads, 1);
  });

  test('a launch scrobbling to Ledger resumes under Smart too', () async {
    expect(await launchPercent(server(resumePoint), ledgerScrobble: true), 42);
  });

  test('a launch that does not track Ledger never reads it', () async {
    expect(await launchPercent(server(resumePoint)), isNull);
    expect(reads, 0);
  });

  test('an unanswered Ledger read never holds the launch', () async {
    final never = Completer<http.Response>();
    final watch = Stopwatch()..start();
    expect(
      await launchPercent(server(() => never.future), ledgerScrobble: true),
      isNull,
    );
    expect(
      watch.elapsed,
      lessThan(LedgerService.resumeReadTimeout + const Duration(seconds: 2)),
    );
  });
}
