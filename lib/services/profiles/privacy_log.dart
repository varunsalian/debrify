import 'package:flutter/foundation.dart';

/// Process-wide last line of defence for diagnostics emitted by application
/// code and Flutter callbacks. Call sites should still avoid private data, but
/// values originating in HTTP exceptions and third-party payloads are not
/// trustworthy enough to rely on every caller doing so forever.
abstract final class PrivacyLog {
  static bool _installed = false;

  /// Public because diagnostics no longer only reach [debugPrint]: the
  /// startup-failure screen shows the caught error to a user who has no way
  /// to produce a log, and that text must pass the same filter as the
  /// console does.
  static String redact(String message) {
    var result = message;
    result = result.replaceAll(
      RegExp(
        r'\b(?:https?|magnet|stremio-addon)[:][^\s\x27\x22)]+',
        caseSensitive: false,
      ),
      '[private-url]',
    );
    result = result.replaceAll(
      RegExp(r'\b(?:\d{1,3}[.]){3}\d{1,3}(?::\d+)?\b'),
      '[private-address]',
    );
    result = result.replaceAll(
      RegExp(
        r'\b(?:api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token|'
        r'password|authorization|bearer|secret|payload|headers?|body)\b'
        r'\s*[:=]\s*[^,;\s)]+',
        caseSensitive: false,
      ),
      '[private-value]',
    );
    // Exception text is attacker/server controlled and routinely embeds the
    // request URL or a response excerpt. Keep only the stable event label.
    result = result.replaceAll(
      RegExp(
        r'\b(?:error|exception|failed)\s*[:=-]\s*.*$',
        caseSensitive: false,
      ),
      'diagnostic failure',
    );
    // JSON/map previews are payloads even when their current schema appears
    // harmless; future fields may contain credentials.
    result = result.replaceAll(RegExp(r'\{[^\r\n]*\}'), '[private-payload]');
    if (result.length > 512) result = '${result.substring(0, 512)}…';
    return result;
  }

  static void install() {
    if (_installed) return;
    final sink = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      sink(message == null ? null : redact(message), wrapWidth: wrapWidth);
    };
    _installed = true;
  }
}
