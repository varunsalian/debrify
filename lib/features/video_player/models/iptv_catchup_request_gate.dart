/// Monotonic ownership gate for asynchronous IPTV replay lookups.
///
/// Starting or cancelling a request makes every older ticket stale, preventing
/// a slow catch-up probe from taking playback back after a newer user action.
class IptvCatchupRequestGate {
  int _generation = 0;
  int? _activeTicket;

  int begin() {
    final ticket = ++_generation;
    _activeTicket = ticket;
    return ticket;
  }

  bool isCurrent(int ticket) =>
      _activeTicket == ticket && _generation == ticket;

  bool complete(int ticket) {
    if (!isCurrent(ticket)) return false;
    _activeTicket = null;
    return true;
  }

  bool cancel() {
    if (_activeTicket == null) return false;
    _generation++;
    _activeTicket = null;
    return true;
  }
}
