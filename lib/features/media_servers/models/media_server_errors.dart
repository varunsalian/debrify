import '../../../models/media_server.dart';

/// Request failures with a type, so a fallback can react to one kind of
/// failure without swallowing profile switches, disabled servers or
/// deadlines, which `authorize` callbacks report as plain
/// [MediaServerException]s. Messages are shown to the user unchanged.
///
/// Network failures, request timeouts and an exhausted lookup budget are
/// separate types: library lookups turn only the last two into an
/// incomplete search, exactly as before the split; a network failure still
/// fails the search.

/// The server refused the credentials (HTTP 401) or the content (403).
class MediaServerAuthError extends MediaServerException {
  const MediaServerAuthError(super.message, {required this.status});
  final int status;
}

/// Any other non-success HTTP status, including refused redirects.
class MediaServerHttpError extends MediaServerException {
  const MediaServerHttpError(super.message, {required this.status});
  final int status;
}

/// The connection failed before a response arrived.
class MediaServerUnreachable extends MediaServerException {
  const MediaServerUnreachable(super.message);
}

/// One request took longer than its timeout.
class MediaServerTimeout extends MediaServerException {
  const MediaServerTimeout(super.message);
}

/// A multi-page lookup used up its time budget. Not a server fault: a large
/// library on a working connection can do this.
class MediaServerLookupBudgetExhausted extends MediaServerTimeout {
  const MediaServerLookupBudgetExhausted(super.message);
}
