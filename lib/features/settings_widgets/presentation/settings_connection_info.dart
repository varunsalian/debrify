class ConnectionInfo {
  final String title;
  final bool connected;
  final String status;
  final String caption;
  final Future<void> Function() onTap;

  const ConnectionInfo({
    required this.title,
    required this.connected,
    required this.status,
    required this.caption,
    required this.onTap,
  });
}

/// Whether a configured connection is explicitly reporting a degraded state.
///
/// Providers use a few healthy labels (for example `Active` and `Configured`),
/// so treating every non-`Active` value as an error incorrectly marks Jackett
/// and Prowlarr as unhealthy. Only known negative states need intervention.
bool settingsConnectionNeedsAttention(ConnectionInfo info) {
  if (!info.connected) return false;
  final status = info.status.toLowerCase();
  return status.contains('inactive') ||
      status.contains('expired') ||
      status.contains('error') ||
      status.contains('failed') ||
      status.contains('attention');
}

bool settingsConnectionIsReady(ConnectionInfo info) =>
    info.connected && !settingsConnectionNeedsAttention(info);
