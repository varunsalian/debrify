import 'package:flutter/foundation.dart';

/// Phase 0 of the IPTV playback-resilience plan (dev/design/plans/
/// IPTV_FLAWLESS_PLAYBACK_PLAN.md): the Dart player's per-tune diagnostics
/// recorder — the mirror of the native TV player's `IptvTuneDiagnostics.kt`,
/// same log grammar so one grep reads both players.
///
/// Every IPTV tune (launch, zap, Stremio ladder candidate) gets a
/// monotonically increasing generation and single-line `IptvDiag:` entries:
/// tune start, first frame, rebuffers, stall suspicion, errors, end of
/// stream, and — from Phase 2 on — recovery narration.
///
/// Deliberately inert unless a tune is active: non-IPTV playback never calls
/// [onTuneStart], so every other hook no-ops and torrent/debrid/YouTube
/// playback logs nothing.
class IptvTuneDiagnostics {
  /// No position advance for this long while playing = one stall-suspect
  /// line. Groundwork for the Phase-2 post-open stall detector: Phase 0 only
  /// OBSERVES, so the threshold errs generous.
  static const Duration stallSuspect = Duration(seconds: 5);

  int _generation = 0;
  bool _active = false;
  String? _channelName;
  String _protocol = 'unknown';
  bool _live = false;

  late DateTime _tuneStart;
  bool _firstFrameLogged = false;
  bool _readyLogged = false;

  int _rebufferCount = 0;
  DateTime? _rebufferStart;

  Duration _lastPosition = const Duration(milliseconds: -1);
  late DateTime _lastAdvance;
  bool _stallSuspectLogged = false;

  /// A new stream is being handed to mpv.
  void onTuneStart(String? name, String url, {required bool isLive}) {
    _generation++;
    _active = true;
    _channelName = name;
    _live = isLive;
    final bare = url.split('?').first.toLowerCase();
    _protocol = url.startsWith('stremio-tv://')
        ? 'stremio'
        : bare.endsWith('.m3u8')
            ? 'hls'
            : 'progressive';
    _tuneStart = DateTime.now();
    _firstFrameLogged = false;
    _readyLogged = false;
    _rebufferCount = 0;
    _rebufferStart = null;
    _lastPosition = const Duration(milliseconds: -1);
    _lastAdvance = _tuneStart;
    _stallSuspectLogged = false;
    _line('tune-start', 'url=${_sanitizeUrl(url)}');
  }

  /// These lines get pasted into Discord. Xtream URLs carry credentials in
  /// the PATH (`/live/<user>/<pass>/123.ts`) and signed links carry tokens
  /// in the query — log scheme + host + last path segment only.
  static String _sanitizeUrl(String url) {
    final noQuery = url.split('?').first;
    final schemeSplit = noQuery.split('://');
    if (schemeSplit.length < 2) {
      return noQuery.length > 40 ? noQuery.substring(0, 40) : noQuery;
    }
    final rest = schemeSplit[1];
    final host = rest.split('/').first;
    final lastSegment = rest.contains('/') ? rest.split('/').last : '';
    final tail =
        lastSegment.length > 40 ? lastSegment.substring(0, 40) : lastSegment;
    return '${schemeSplit[0]}://$host/…/$tail';
  }

  /// First sized frame (the width stream firing) — zap speed is judged here.
  void onFirstFrame() {
    if (!_active || _firstFrameLogged) return;
    _firstFrameLogged = true;
    _readyLogged = true;
    _line('first-frame', 'ttff=${_sinceTune()}ms');
  }

  /// mpv's buffering flag flipped. Pre-first-frame buffering is the tune
  /// itself, not a rebuffer.
  void onBuffering(bool buffering, Duration position) {
    if (!_active || !_readyLogged) return;
    if (buffering) {
      if (_rebufferStart != null) return;
      _rebufferStart = DateTime.now();
      _rebufferCount++;
      _line(
        'rebuffer-start',
        'pos=${position.inMilliseconds}ms count=$_rebufferCount ${_advanceAge()}',
      );
    } else {
      final start = _rebufferStart;
      if (start == null) return;
      _rebufferStart = null;
      final held = DateTime.now().difference(start).inMilliseconds;
      _line('rebuffer-end', 'held=${held}ms count=$_rebufferCount');
    }
  }

  void onPlaybackEnded(Duration position) {
    if (!_active) return;
    _line(
      'ended',
      'pos=${position.inMilliseconds}ms rebuffers=$_rebufferCount ${_advanceAge()}',
    );
  }

  void onError(String error) {
    if (!_active) return;
    _line('error', 'rebuffers=$_rebufferCount ${_advanceAge()} msg="$error"');
  }

  /// Fed by the existing position stream. Cheap: arithmetic + at most one log
  /// line per stall episode. [playing] excludes user pause.
  void onProgress(Duration position, {required bool playing}) {
    if (!_active) return;
    final now = DateTime.now();
    if (position != _lastPosition) {
      _lastPosition = position;
      _lastAdvance = now;
      if (_stallSuspectLogged) {
        _stallSuspectLogged = false;
        _line('stall-cleared', 'pos=${position.inMilliseconds}ms');
      }
      return;
    }
    if (!playing || _rebufferStart != null) return;
    if (!_stallSuspectLogged && now.difference(_lastAdvance) >= stallSuspect) {
      _stallSuspectLogged = true;
      _line('stall-suspect', 'pos=${position.inMilliseconds}ms ${_advanceAge()}');
    }
  }

  /// Phase 2+: the recovery state machine narrates itself through here.
  /// Ships unused in Phase 0 so the log grammar is settled first.
  void onRecovery(String source, String action, [String detail = '']) {
    if (!_active) return;
    _line('recovery', 'source=$source action=$action${detail.isEmpty ? '' : ' $detail'}');
  }

  /// Freeform breadcrumb (Stremio candidate hops etc.).
  void note(String message) {
    if (!_active) return;
    _line('note', message);
  }

  /// Playback left IPTV entirely (screen teardown).
  void onSessionEnd() {
    if (!_active) return;
    _active = false;
    _line('session-end', 'rebuffers=$_rebufferCount');
  }

  int _sinceTune() => DateTime.now().difference(_tuneStart).inMilliseconds;

  String _advanceAge() =>
      'advanceAge=${DateTime.now().difference(_lastAdvance).inMilliseconds}ms';

  void _line(String event, String detail) {
    debugPrint(
      'IptvDiag: gen=$_generation event=$event proto=$_protocol live=$_live '
      'ch="${_channelName ?? '?'}" $detail',
    );
  }
}
