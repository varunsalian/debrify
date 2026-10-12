import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/episode_tracker_snapshot_service.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../support/catalog_detail_http_transport.dart';
import 'video_player_environment.dart';

/// Install before tracker singletons are touched. A client retained by a
/// singleton still dispatches to the current case; there is no network fallback.
class TraktTestTransport extends HttpOverrides {
  static final instance = TraktTestTransport();
  VideoPlayerHttp? recorder;
  int _client = 0;

  static void install() => HttpOverrides.global = instance;

  void attach(VideoPlayerEnvironment environment) {
    recorder = environment.network;
    install();
    TraktService.instance.resetProfileScope();
    SimklService.instance.resetProfileScope();
    MdblistService.instance.resetProfileScope();
    EpisodeTrackerSnapshotService.debugResetRefreshState();
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final id = _client++;
    return http.runWithClient(CatalogFixtureHttpClient.new, () {
      return _DelegatingClient((request) async {
        final current = recorder ?? (throw StateError('No active HTTP case'));
        current.requests.add(request);
        final pending = current.pendingByClient.putIfAbsent(id, () => []);
        final reply = Completer<http.Response>();
        pending.add(reply);
        Future<http.Response>.sync(
          () =>
              current.handler?.call(request) ??
              current.replies[request.url.toString()] ??
              http.Response('{}', 404),
        ).then(reply.complete, onError: reply.completeError);
        try {
          return await reply.future;
        } finally {
          pending.remove(reply);
        }
      }, () => recorder?.closedClients.add(id));
    });
  }
}

class _DelegatingClient extends MockClient {
  _DelegatingClient(super.fn, this.closed);
  final void Function() closed;
  @override
  void close() {
    closed();
    super.close();
  }
}

/// Each open gets its own barrier. The delegate still authenticates ciphertext;
/// only synthetic credential payloads are ever seeded by this harness.
class TraktCipherReads implements DeviceSecretCipher {
  TraktCipherReads(this.delegate);
  final DeviceSecretCipher delegate;
  final held = <Completer<void>>[];
  bool hold = false;
  Object? failure;
  int opens = 0;

  @override
  Future<void> initialize() => delegate.initialize();
  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) => delegate.seal(plaintext, associatedData: associatedData);
  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    opens++;
    final gate = Completer<void>();
    if (hold) {
      held.add(gate);
      await gate.future;
    }
    if (failure != null) throw failure!;
    return delegate.open(envelope, associatedData: associatedData);
  }

  void releaseAll() {
    hold = false;
    for (final gate in held) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

Future<TraktCipherReads> seedTrakt({bool target = true}) async {
  await TraktStorage.setTraktSession(
    accessToken: 'vplayer-synthetic-access',
    refreshToken: 'vplayer-synthetic-refresh',
    expiryMs: 4102444800000,
  );
  await TrackingSourceStorage.setTrackingScrobbleTargets(
    target ? {TrackingSource.trakt} : {},
  );
  await TrackingSourceStorage.setWatchProgressSource(WatchProgressSource.smart);
  final cipher = TraktCipherReads(DeviceKeyProvider.cipher);
  DeviceKeyProvider.debugInstallCipher(cipher);
  return cipher;
}

http.Response traktReply(http.Request request) =>
    request.url.path.startsWith('/scrobble/')
    ? http.Response(
        jsonEncode({'action': request.url.path.split('/').last}),
        201,
        headers: {'content-type': 'application/json'},
      )
    : http.Response('{}', 404, headers: {'content-type': 'application/json'});
