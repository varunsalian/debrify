/// Read provider availability in the playback service's established order.
/// A null result means the action retired; an empty list means none configured.
/// Readers stay sequential and own their credential/profile access.
Future<(List<String>, String?)?> loadSourceProviderConfiguration({
  required Future<bool> Function(String provider) isConfigured,
  required Future<String> Function() readDefault,
  bool Function()? canContinue,
}) async {
  bool active() => canContinue?.call() ?? true;
  if (!active()) return null;
  try {
    final configured = <String>[];
    for (final provider in [
      'debrid',
      'torbox',
      'premiumize',
      'alldebrid',
      'pikpak',
    ]) {
      final available = await isConfigured(provider);
      if (!active()) return null;
      if (available) configured.add(provider);
    }
    if (configured.isEmpty) return (const <String>[], null);
    final preferred = await readDefault();
    if (!active()) return null;
    return (
      List<String>.unmodifiable(configured),
      preferred != 'none' && configured.contains(preferred) ? preferred : null,
    );
  } catch (_) {
    if (!active()) return null;
    rethrow;
  }
}
