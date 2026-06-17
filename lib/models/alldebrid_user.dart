/// AllDebrid account info, parsed from the `data.user` object returned by
/// the `/v4/user` endpoint.
class AllDebridUser {
  final String username;
  final String email;
  final bool isPremium;
  final bool isTrial;

  /// When the premium subscription expires. Null when not premium or when the
  /// account has no expiry (e.g. lifetime).
  final DateTime? premiumUntil;

  /// Fidelity (loyalty) points balance.
  final int fidelityPoints;

  AllDebridUser({
    required this.username,
    required this.email,
    required this.isPremium,
    required this.isTrial,
    required this.premiumUntil,
    required this.fidelityPoints,
  });

  /// [json] is the `user` object (i.e. `payload['data']['user']`).
  factory AllDebridUser.fromJson(Map<String, dynamic> json) {
    return AllDebridUser(
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      isPremium: json['isPremium'] == true,
      isTrial: json['isTrial'] == true,
      premiumUntil: _tryParseEpoch(json['premiumUntil']),
      fidelityPoints: _asInt(json['fidelityPoints']),
    );
  }

  /// True while the account has active premium access.
  bool get hasActivePremium {
    if (!isPremium) return false;
    // A premium flag with no expiry (lifetime) is still active.
    if (premiumUntil == null) return true;
    return premiumUntil!.isAfter(DateTime.now());
  }

  String get subscriptionStatus {
    if (isTrial) return 'Trial';
    return hasActivePremium ? 'Premium' : 'Free';
  }

  String get formattedPremiumExpiry => _formatDate(premiumUntil);

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _tryParseEpoch(dynamic value) {
    final seconds = _asInt(value);
    if (seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
