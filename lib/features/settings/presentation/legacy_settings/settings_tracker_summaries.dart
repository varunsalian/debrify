import 'settings_summaries.dart';

/// Connection-card status for the watch trackers (Trakt, Simkl, Ledger,
/// MDBList). Moved unchanged out of the summary loader.
void applyTrackerSummaries(
  SettingsSummaries summaries, {
  required bool traktConnected,
  required int? traktExpiry,
  required String? traktUsername,
  required bool simklConnected,
  required String? simklUsername,
  required bool ledgerConnected,
  required String? ledgerUsername,
  required bool mdblistConnected,
  required String? mdblistUsername,
}) {
  final traktExpired =
      traktExpiry != null &&
      DateTime.now().millisecondsSinceEpoch >= traktExpiry;
  if (traktConnected) {
    if (!traktExpired) {
      summaries.traktConnected = true;
      summaries.traktStatus = 'Active';
      summaries.traktCaption = traktUsername != null
          ? 'Logged in as $traktUsername'
          : 'Logged in';
    } else {
      summaries.traktStatus = 'Expired';
      summaries.traktCaption = 'Tap to reconnect';
    }
  }

  // Simkl's PIN-issued tokens don't expire, so unlike Trakt there's no
  // "Expired" branch here — a stored token means connected.
  if (simklConnected) {
    summaries.simklConnected = true;
    summaries.simklStatus = 'Active';
    summaries.simklCaption = simklUsername != null
        ? 'Logged in as $simklUsername'
        : 'Logged in';
  } else {
    summaries.simklConnected = false;
    summaries.simklStatus = 'Not connected';
    summaries.simklCaption = 'Tap to connect';
  }

  // Ledger access tokens are short-lived but renew themselves from the
  // stored refresh token, so a stored session means connected.
  summaries.ledgerConnected = ledgerConnected;
  summaries.ledgerStatus = ledgerConnected ? 'Active' : 'Not connected';
  summaries.ledgerCaption = !ledgerConnected
      ? 'Tap to connect'
      : ledgerUsername != null
      ? 'Logged in as $ledgerUsername'
      : 'Logged in';

  // MDBList uses a plain API key (no expiry) — a stored key means connected.
  // Reset on the empty branch (like WebDAV above) so the card clears after a
  // logout, since this method re-runs when returning from the settings page.
  if (mdblistConnected) {
    summaries.mdblistConnected = true;
    summaries.mdblistStatus = 'Active';
    summaries.mdblistCaption = mdblistUsername != null
        ? 'Logged in as $mdblistUsername'
        : 'Logged in';
  } else {
    summaries.mdblistConnected = false;
    summaries.mdblistStatus = 'Not connected';
    summaries.mdblistCaption = 'Tap to connect';
  }
}
