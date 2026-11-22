import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/video_player/presentation/legacy_video_player/vp_ledger_scrobbler.dart';
import 'package:debrify/services/ledger/ledger_api.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:debrify/services/ledger/ledger_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
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

class _MovieHost implements VpLedgerScrobblerHost {
  _MovieHost({required this.ledgerScrobble});

  @override
  final bool ledgerScrobble;
  @override
  bool get mounted => true;
  @override
  String? get effectiveContentImdbId => 'tt0133093';
  @override
  String? get contentImdbId => 'tt0133093';
  @override
  String? get contentType => 'movie';
  @override
  String? get effectiveContentType => 'movie';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

TrackingSourcePolicy _policy(WatchProgressSource source) =>
    TrackingSourcePolicy(
      scrobbleTargets: const {},
      progressSource: source,
      homeTickSources: const {},
    );

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

  VpLedgerScrobbler scrobbler(
    Future<http.Response> Function(http.Request) handler, {
    bool ledgerScrobble = true,
  }) {
    final session = _SignedIn();
    return VpLedgerScrobbler(
      _MovieHost(ledgerScrobble: ledgerScrobble),
      service: LedgerService.forTesting(
        session: session,
        api: LedgerApi(
          tokens: session,
          baseUrl: 'https://ledger.test',
          client: MockClient(handler),
        ),
      ),
    );
  }

  test('a movie resumes from its Ledger resume point', () async {
    final s = scrobbler(
      (_) async => http.Response(
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
      ),
    );
    expect(
      await s.resumePercent(policy: _policy(WatchProgressSource.smart)),
      42,
    );
  });

  test('an unanswered resume read never holds playback', () async {
    final never = Completer<http.Response>();
    final s = scrobbler((_) => never.future);
    final watch = Stopwatch()..start();
    expect(
      await s.resumePercent(policy: _policy(WatchProgressSource.smart)),
      isNull,
    );
    expect(
      watch.elapsed,
      lessThan(LedgerService.resumeReadTimeout + const Duration(seconds: 2)),
    );
  });

  test('a launch that does not track Ledger never reads it', () async {
    var reads = 0;
    final s = scrobbler((_) async {
      reads++;
      return http.Response('{}', 200);
    }, ledgerScrobble: false);
    final policy = _policy(WatchProgressSource.smart);
    expect(s.consultsLedger(policy), isFalse);
    expect(await s.resumePercent(policy: policy), isNull);
    expect(reads, 0);
  });
}
