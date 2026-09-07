import 'remote_session.dart';

/// Tracks silently-dropped plaintext datagrams per source so a phone app too
/// old to pair can be told to update, instead of appearing to do nothing.
class RemoteStaleSourceNotice {
  RemoteStaleSourceNotice({required this.showNoticeNow});

  /// Raised immediately rather than banked: this is a standalone warning and
  /// must not be swallowed into an unrelated config batch's summary.
  final void Function(String message, {bool isError, Duration duration})
  showNoticeNow;

  // A pre-v2 phone cannot complete the handshake a committed profile install
  // requires, so every packet it sends is dropped — and because `reject` is
  // deliberately absent for plaintext, it is dropped in SILENCE. The phone
  // still discovers this TV and still looks connected, so the only symptom is
  // a remote that does nothing. Count drops per datagram source and name the
  // one thing the user can act on.

  static const int _staleRemoteNoticeThreshold = 3;
  static const Duration _staleRemoteBurstWindow = Duration(seconds: 10);
  static const Duration _staleRemoteNoticeCooldown = Duration(minutes: 10);
  static const int _staleRemoteTrackedSourceCap = 8;

  final Map<String, _StaleRemoteSource> _staleRemoteSources = {};
  int _staleRemoteNoticeCount = 0;

  /// Surface the only actionable cause of a silent drop: a phone app too old
  /// to pair. PLAINTEXT only — an encrypted peer that is merely unauthorized
  /// is a CURRENT app that has not paired yet, and it already gets a real
  /// rejection plus the pairing UI; telling that user to update would send
  /// them the wrong way. One stray datagram is not a stuck remote either, so
  /// the notice waits for a burst from a single source.
  void noteUnauthenticatedDrop(RemoteCommandContext context) {
    if (context.encrypted) return;
    final sourceIp = context.sourceIp;
    if (sourceIp == null) return;
    final now = DateTime.now();

    // A source that has been quiet longer than the cooldown is forgotten
    // outright, so a phone that returns later earns a fresh notice rather
    // than inheriting a spent one.
    _staleRemoteSources.removeWhere(
      (_, source) =>
          now.difference(source.lastDropAt) > _staleRemoteNoticeCooldown,
    );
    if (!_staleRemoteSources.containsKey(sourceIp) &&
        _staleRemoteSources.length >= _staleRemoteTrackedSourceCap) {
      // LAN noise must never grow this map without bound; evict the coldest.
      String? coldestIp;
      DateTime? coldest;
      for (final entry in _staleRemoteSources.entries) {
        if (coldest == null || entry.value.lastDropAt.isBefore(coldest)) {
          coldest = entry.value.lastDropAt;
          coldestIp = entry.key;
        }
      }
      if (coldestIp != null) _staleRemoteSources.remove(coldestIp);
    }

    final source = _staleRemoteSources.putIfAbsent(
      sourceIp,
      () => _StaleRemoteSource(now),
    );
    if (now.difference(source.burstStartedAt) > _staleRemoteBurstWindow) {
      source.drops = 0;
      source.burstStartedAt = now;
    }
    source.drops++;
    source.lastDropAt = now;
    if (source.drops < _staleRemoteNoticeThreshold) return;

    final noticedAt = source.noticedAt;
    if (noticedAt != null &&
        now.difference(noticedAt) < _staleRemoteNoticeCooldown) {
      return;
    }
    source.noticedAt = now;
    source.drops = 0;
    source.burstStartedAt = now;
    _staleRemoteNoticeCount++;
    // Deliberately NOT _showSnackBar: this is a standalone warning and must
    // not be swallowed into an unrelated config batch's summary.
    showNoticeNow(
      'Update your phone app to use the remote',
      isError: true,
      duration: const Duration(seconds: 6),
    );
  }

  /// How many notices this receiver has raised.
  int get noticeCount => _staleRemoteNoticeCount;

  void reset() {
    _staleRemoteSources.clear();
    _staleRemoteNoticeCount = 0;
  }
}

/// Per-source-IP drop tally behind the "update your phone app" notice.
class _StaleRemoteSource {
  _StaleRemoteSource(DateTime now)
    : burstStartedAt = now,
      lastDropAt = now,
      drops = 0;

  int drops;
  DateTime burstStartedAt;
  DateTime lastDropAt;
  DateTime? noticedAt;
}
