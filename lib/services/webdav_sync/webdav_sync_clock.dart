import 'dart:math';

import 'webdav_sync_hot_models.dart';

enum WebDavSyncClockPauseReason {
  missingServerDate,
  offsetOutlier,
  serverMovedBackwards,
}

final class WebDavSyncClockState {
  const WebDavSyncClockState({
    this.acceptedOffsetMs,
    this.serverHighWaterMs,
    this.outlierOffsetMs,
    this.outlierCount = 0,
  });

  final int? acceptedOffsetMs;
  final int? serverHighWaterMs;
  final int? outlierOffsetMs;
  final int outlierCount;

  Map<String, Object?> toJson() => <String, Object?>{
    if (acceptedOffsetMs != null) 'acceptedOffsetMs': acceptedOffsetMs,
    if (serverHighWaterMs != null) 'serverHighWaterMs': serverHighWaterMs,
    if (outlierOffsetMs != null) 'outlierOffsetMs': outlierOffsetMs,
    'outlierCount': outlierCount,
  };

  factory WebDavSyncClockState.fromJson(Object? source) {
    if (source == null) return const WebDavSyncClockState();
    if (source is! Map) {
      throw const FormatException('Invalid WebDAV sync clock state');
    }
    final json = Map<String, dynamic>.from(source);
    const allowedKeys = <String>{
      'acceptedOffsetMs',
      'serverHighWaterMs',
      'outlierOffsetMs',
      'outlierCount',
    };
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException('Invalid WebDAV sync clock state');
    }
    int? optionalOffset(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! int || value.abs() > WebDavSyncLimits.maxTimestampMs) {
        throw const FormatException('Invalid WebDAV sync clock state');
      }
      return value;
    }

    final highWater = json['serverHighWaterMs'];
    if (highWater != null &&
        (highWater is! int ||
            highWater < 0 ||
            highWater > WebDavSyncLimits.maxTimestampMs)) {
      throw const FormatException('Invalid WebDAV sync clock state');
    }
    final count = json['outlierCount'] ?? 0;
    if (count is! int || count < 0 || count > 2) {
      throw const FormatException('Invalid WebDAV sync clock state');
    }
    final outlierOffset = optionalOffset('outlierOffsetMs');
    if ((count == 0) != (outlierOffset == null)) {
      throw const FormatException('Invalid WebDAV sync clock state');
    }
    return WebDavSyncClockState(
      acceptedOffsetMs: optionalOffset('acceptedOffsetMs'),
      serverHighWaterMs: highWater as int?,
      outlierOffsetMs: outlierOffset,
      outlierCount: count,
    );
  }
}

final class WebDavSyncClockDecision {
  const WebDavSyncClockDecision({
    required this.state,
    required this.measuredOffsetMs,
    required this.serverNowMs,
    required this.mayPublish,
    required this.deviceClockWarning,
    this.pauseReason,
  });

  final WebDavSyncClockState state;
  final int? measuredOffsetMs;
  final int? serverNowMs;
  final bool mayPublish;
  final bool deviceClockWarning;
  final WebDavSyncClockPauseReason? pauseReason;

  int normalizeLocalTimestamp(int rawLocalMs) {
    final offset = state.acceptedOffsetMs;
    final serverNow = serverNowMs;
    if (!mayPublish || offset == null || serverNow == null) {
      throw StateError('WebDAV sync clock is not safe for publication');
    }
    return min(max(0, rawLocalMs + offset), serverNow);
  }
}

abstract final class WebDavSyncClockPolicy {
  static const Duration backwardTolerance = Duration(hours: 1);
  static const Duration remoteFutureTolerance = Duration(hours: 1);
  static const Duration offsetOutlierThreshold = Duration(hours: 24);
  static const Duration repeatedOutlierTolerance = Duration(minutes: 5);

  static WebDavSyncClockDecision observe({
    required WebDavSyncClockState prior,
    required int localNowMs,
    required DateTime? serverDate,
  }) {
    if (serverDate == null) {
      return WebDavSyncClockDecision(
        state: prior,
        measuredOffsetMs: null,
        serverNowMs: null,
        mayPublish: false,
        deviceClockWarning: false,
        pauseReason: WebDavSyncClockPauseReason.missingServerDate,
      );
    }
    final serverNowMs = serverDate.toUtc().millisecondsSinceEpoch;
    final measuredOffset = serverNowMs - localNowMs;
    if (serverNowMs < 0 ||
        serverNowMs > WebDavSyncLimits.maxTimestampMs ||
        measuredOffset.abs() > WebDavSyncLimits.maxTimestampMs) {
      return WebDavSyncClockDecision(
        state: prior,
        measuredOffsetMs: measuredOffset,
        serverNowMs: serverNowMs,
        mayPublish: false,
        deviceClockWarning: true,
        pauseReason: WebDavSyncClockPauseReason.offsetOutlier,
      );
    }
    var acceptedOffset = prior.acceptedOffsetMs;
    var outlierOffset = prior.outlierOffsetMs;
    var outlierCount = prior.outlierCount;

    if (acceptedOffset != null &&
        (measuredOffset - acceptedOffset).abs() >
            offsetOutlierThreshold.inMilliseconds) {
      final repeated =
          outlierOffset != null &&
          (measuredOffset - outlierOffset).abs() <=
              repeatedOutlierTolerance.inMilliseconds;
      if (!repeated || outlierCount == 0) {
        final state = WebDavSyncClockState(
          acceptedOffsetMs: acceptedOffset,
          serverHighWaterMs: prior.serverHighWaterMs,
          outlierOffsetMs: measuredOffset,
          outlierCount: 1,
        );
        return WebDavSyncClockDecision(
          state: state,
          measuredOffsetMs: measuredOffset,
          serverNowMs: serverNowMs,
          mayPublish: false,
          deviceClockWarning:
              measuredOffset.abs() > offsetOutlierThreshold.inMilliseconds,
          pauseReason: WebDavSyncClockPauseReason.offsetOutlier,
        );
      }
      acceptedOffset = measuredOffset;
      outlierOffset = null;
      outlierCount = 0;
    } else {
      acceptedOffset = measuredOffset;
      outlierOffset = null;
      outlierCount = 0;
    }

    final highWater = prior.serverHighWaterMs;
    if (highWater != null &&
        serverNowMs < highWater - backwardTolerance.inMilliseconds) {
      return WebDavSyncClockDecision(
        state: WebDavSyncClockState(
          acceptedOffsetMs: acceptedOffset,
          serverHighWaterMs: highWater,
          outlierOffsetMs: outlierOffset,
          outlierCount: outlierCount,
        ),
        measuredOffsetMs: measuredOffset,
        serverNowMs: serverNowMs,
        mayPublish: false,
        deviceClockWarning:
            measuredOffset.abs() > offsetOutlierThreshold.inMilliseconds,
        pauseReason: WebDavSyncClockPauseReason.serverMovedBackwards,
      );
    }

    var publicationNowMs = serverNowMs;
    if (highWater != null && publicationNowMs < highWater) {
      final next = highWater + 1;
      if (next > WebDavSyncLimits.maxTimestampMs ||
          next > serverNowMs + remoteFutureTolerance.inMilliseconds) {
        return WebDavSyncClockDecision(
          state: WebDavSyncClockState(
            acceptedOffsetMs: acceptedOffset,
            serverHighWaterMs: highWater,
          ),
          measuredOffsetMs: measuredOffset,
          serverNowMs: serverNowMs,
          mayPublish: false,
          deviceClockWarning:
              measuredOffset.abs() > offsetOutlierThreshold.inMilliseconds,
          pauseReason: WebDavSyncClockPauseReason.serverMovedBackwards,
        );
      }
      publicationNowMs = next;
      acceptedOffset = publicationNowMs - localNowMs;
    }

    return WebDavSyncClockDecision(
      state: WebDavSyncClockState(
        acceptedOffsetMs: acceptedOffset,
        serverHighWaterMs: publicationNowMs,
      ),
      measuredOffsetMs: measuredOffset,
      serverNowMs: publicationNowMs,
      mayPublish: true,
      deviceClockWarning:
          measuredOffset.abs() > offsetOutlierThreshold.inMilliseconds,
    );
  }

  /// Allows ordinary request skew while preventing one authenticated peer
  /// from pinning manifest ordering and rollback high-water state far ahead
  /// of the server clock used for this cycle.
  static bool acceptsRemoteTimestamp({
    required int timestampMs,
    required int serverNowMs,
  }) => timestampMs <= serverNowMs + remoteFutureTolerance.inMilliseconds;
}
