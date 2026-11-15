/// Reads what a source row's "Play in …" offer depends on: the profile's
/// default player mode and whether the profile may use external players.
/// Injected so the menu never reads storage or profile policy itself.
class SourcePlayerPreference {
  const SourcePlayerPreference({
    required Future<String> Function() defaultMode,
    required bool Function() externalAllowed,
  }) : _defaultMode = defaultMode,
       _externalAllowed = externalAllowed;

  final Future<String> Function() _defaultMode;
  final bool Function() _externalAllowed;

  Future<String> defaultMode() => _defaultMode();
  bool externalAllowed() => _externalAllowed();
}
