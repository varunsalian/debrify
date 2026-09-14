import 'package:debrify/services/webdav_sync/webdav_sync_clock.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full server offset is accepted and publish stamps clamp to now', () {
    final decision = WebDavSyncClockPolicy.observe(
      prior: const WebDavSyncClockState(),
      localNowMs: 1000,
      serverDate: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
    );

    expect(decision.mayPublish, isTrue);
    expect(decision.state.acceptedOffsetMs, 4000);
    expect(decision.normalizeLocalTimestamp(2000), 5000);
  });

  test('one offset outlier neither publishes nor advances high-water', () {
    final prior = WebDavSyncClockState(
      acceptedOffsetMs: 0,
      serverHighWaterMs: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
    );
    final localNow = DateTime.utc(2026, 1, 2).millisecondsSinceEpoch;
    final lie = DateTime.utc(2099, 1, 1);
    final decision = WebDavSyncClockPolicy.observe(
      prior: prior,
      localNowMs: localNow,
      serverDate: lie,
    );

    expect(decision.mayPublish, isFalse);
    expect(decision.pauseReason, WebDavSyncClockPauseReason.offsetOutlier);
    expect(decision.state.serverHighWaterMs, prior.serverHighWaterMs);
    expect(decision.state.acceptedOffsetMs, 0);
  });

  test('a repeated offset outlier is accepted on the second cycle', () {
    final first = WebDavSyncClockPolicy.observe(
      prior: const WebDavSyncClockState(
        acceptedOffsetMs: 0,
        serverHighWaterMs: 1000,
      ),
      localNowMs: 2000,
      serverDate: DateTime.fromMillisecondsSinceEpoch(
        2000 + const Duration(days: 2).inMilliseconds,
        isUtc: true,
      ),
    );
    final second = WebDavSyncClockPolicy.observe(
      prior: first.state,
      localNowMs: 3000,
      serverDate: DateTime.fromMillisecondsSinceEpoch(
        3000 + const Duration(days: 2).inMilliseconds,
        isUtc: true,
      ),
    );

    expect(second.mayPublish, isTrue);
    expect(
      second.state.acceptedOffsetMs,
      const Duration(days: 2).inMilliseconds,
    );
  });

  test('a confirmed far-future server offset survives manifest decoding', () {
    final localNow = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    final serverDate = DateTime.utc(2099, 1, 1);
    final first = WebDavSyncClockPolicy.observe(
      prior: const WebDavSyncClockState(
        acceptedOffsetMs: 0,
        serverHighWaterMs: 1000,
      ),
      localNowMs: localNow,
      serverDate: serverDate,
    );
    final second = WebDavSyncClockPolicy.observe(
      prior: first.state,
      localNowMs: localNow + 1000,
      serverDate: serverDate.add(const Duration(seconds: 1)),
    );
    final manifest = WebDavSyncManifest(
      circleId: 'circle-one',
      deviceId: 'device-one',
      updatedAtMs: second.serverNowMs!,
      clockOffsetMs: second.state.acceptedOffsetMs!,
      graphSchemaClaim: 1,
      profileMap: const <String, String>{},
      resourceMap: const <String, String>{},
      sections: <WebDavSyncSectionReference>[
        WebDavSyncSectionReference(
          name: 'hot',
          contentHash: '1' * 64,
          semanticDigest: '2' * 64,
          updatedAtMs: second.serverNowMs!,
          schemaVersion: 1,
          size: 1,
        ),
      ],
    );

    expect(second.mayPublish, isTrue);
    expect(
      WebDavSyncManifest.fromJson(manifest.toJson()).clockOffsetMs,
      second.state.acceptedOffsetMs,
    );
  });

  test('persisted clock state rejects corrupt bounds and outlier pairs', () {
    for (final state in <Map<String, Object?>>[
      <String, Object?>{
        'acceptedOffsetMs': WebDavSyncLimits.maxTimestampMs + 1,
        'outlierCount': 0,
      },
      <String, Object?>{'serverHighWaterMs': -1, 'outlierCount': 0},
      <String, Object?>{'outlierCount': 1},
      <String, Object?>{'outlierOffsetMs': 1, 'outlierCount': 0},
      <String, Object?>{'outlierCount': 0, 'unexpected': 1},
    ]) {
      expect(() => WebDavSyncClockState.fromJson(state), throwsFormatException);
    }
  });

  test('an unrepresentable server clock cannot advance clock state', () {
    const prior = WebDavSyncClockState(
      acceptedOffsetMs: 0,
      serverHighWaterMs: 1000,
    );
    final decision = WebDavSyncClockPolicy.observe(
      prior: prior,
      localNowMs: -WebDavSyncLimits.maxTimestampMs,
      serverDate: DateTime.utc(9999, 12, 31),
    );

    expect(decision.mayPublish, isFalse);
    expect(decision.pauseReason, WebDavSyncClockPauseReason.offsetOutlier);
    expect(decision.state, same(prior));
  });

  test('server backward jump pauses publishing', () {
    final decision = WebDavSyncClockPolicy.observe(
      prior: const WebDavSyncClockState(
        acceptedOffsetMs: 0,
        serverHighWaterMs: 10000000,
      ),
      localNowMs: 1000,
      serverDate: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );

    expect(decision.mayPublish, isFalse);
    expect(
      decision.pauseReason,
      WebDavSyncClockPauseReason.serverMovedBackwards,
    );
  });

  test('a small backward server step publishes a monotonic valid stamp', () {
    final decision = WebDavSyncClockPolicy.observe(
      prior: const WebDavSyncClockState(
        acceptedOffsetMs: 0,
        serverHighWaterMs: 10000,
      ),
      localNowMs: 9000,
      serverDate: DateTime.fromMillisecondsSinceEpoch(9000, isUtc: true),
    );

    expect(decision.mayPublish, isTrue);
    expect(decision.serverNowMs, 10001);
    expect(decision.state.serverHighWaterMs, 10001);
    expect(decision.state.acceptedOffsetMs, 1001);
    expect(
      WebDavSyncClockPolicy.acceptsRemoteTimestamp(
        timestampMs: decision.serverNowMs!,
        serverNowMs: 9000,
      ),
      isTrue,
    );
  });
}
