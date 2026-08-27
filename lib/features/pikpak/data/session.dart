/// Where PikPak announces that its authenticated state changed — signed in,
/// signed out, or dropped on a profile switch.
///
/// A sink rather than a `ValueNotifier` on the service, because a notifier is a
/// presentation primitive: whoever rebuilds on the change should own one, and a
/// service should only report the fact. Written on transitions, never as a side
/// effect of being asked `isAuthenticated`.
typedef PikPakAuthSink = void Function(bool authenticated);

/// The credentials and recovery actions a PikPak request needs, without
/// naming where any of it is stored.
///
/// PikPak rejects a request in three different ways for the same underlying
/// reason — a 401, an `error_code` of 16, or an `unauthenticated` error string
/// on some other status — so the client asks for a [refresh] rather than
/// deciding for itself what a stale token looks like.
abstract interface class PikPakSession {
  Future<String?> accessToken();

  /// Sent as `X-Device-ID`. Absent on a session that has never logged in.
  Future<String?> deviceId();

  /// Sent as `X-Captcha-Token`. Short-lived and re-fetched by the caller.
  Future<String?> captchaToken();

  /// Exchange the refresh token for a new access token. True when a usable
  /// access token is available afterwards.
  Future<bool> refresh();

  /// PikPak rejected the captcha (`error_code` 4002). Drop the stored one so
  /// the next call fetches a fresh token.
  Future<void> invalidateCaptcha();
}

/// Everything a PikPak call can fail with once the transport has succeeded.
sealed class PikPakApiFailure implements Exception {
  final String message;
  const PikPakApiFailure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// The access token could not be renewed. The session has been cleared and the
/// user must log in again.
final class PikPakSessionExpired extends PikPakApiFailure {
  const PikPakSessionExpired([
    super.message = 'Session expired. Please login again.',
  ]);
}

/// PikPak is throttling this account.
final class PikPakRateLimited extends PikPakApiFailure {
  const PikPakRateLimited([
    super.message = 'Rate limit exceeded. Please try again later.',
  ]);
}

/// PikPak answered with its own error payload. [code] is `error_code` when it
/// sent one — a number in some responses and a string in others.
final class PikPakRequestFailed extends PikPakApiFailure {
  final Object? code;
  final int statusCode;

  const PikPakRequestFailed(
    super.message, {
    this.code,
    required this.statusCode,
  });
}

/// The body was not the JSON object every PikPak endpoint is documented to
/// return — usually a captive portal or an edge error page behind a 200.
final class PikPakUnexpectedResponse extends PikPakApiFailure {
  final int statusCode;

  const PikPakUnexpectedResponse(super.message, {required this.statusCode});
}
