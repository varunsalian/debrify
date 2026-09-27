typedef HomeCredentialReader =
    Future<String?> Function(bool Function() isCurrent);

/// Returns only eligibility; credential values never leave this data operation.
class HomePikpakOnlyRepository {
  const HomePikpakOnlyRepository({
    required this.readPikpakEnabled,
    required this.readRealDebrid,
    required this.readTorbox,
    required this.readPremiumize,
    required this.readAllDebrid,
  });
  final Future<bool> Function(bool Function()) readPikpakEnabled;
  final HomeCredentialReader readRealDebrid;
  final HomeCredentialReader readTorbox;
  final HomeCredentialReader readPremiumize;
  final HomeCredentialReader readAllDebrid;

  Future<bool?> read({required bool Function() isCurrent}) async {
    if (!isCurrent()) return null;
    try {
      final pikpak = await readPikpakEnabled(isCurrent);
      if (!isCurrent()) return null;
      var anyOther = false;
      // Keep every read, in order, even when the result is already determined.
      for (final read in [
        readRealDebrid,
        readTorbox,
        readPremiumize,
        readAllDebrid,
      ]) {
        final key = await read(isCurrent);
        if (!isCurrent()) return null;
        anyOther = anyOther || (key != null && key.isNotEmpty);
      }
      return pikpak && !anyOther;
    } catch (_) {
      if (!isCurrent()) return null;
      rethrow;
    }
  }
}
