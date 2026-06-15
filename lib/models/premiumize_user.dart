class PremiumizeUser {
  final String customerId;
  final DateTime? premiumUntil;

  /// Fair-use limit consumed, expressed as a fraction between 0 and 1.
  final double limitUsed;

  /// Bytes currently stored in the Premiumize cloud.
  final int spaceUsed;

  PremiumizeUser({
    required this.customerId,
    required this.premiumUntil,
    required this.limitUsed,
    required this.spaceUsed,
  });

  factory PremiumizeUser.fromJson(Map<String, dynamic> json) {
    return PremiumizeUser(
      customerId: json['customer_id']?.toString() ?? '',
      premiumUntil: _tryParseEpoch(json['premium_until']),
      limitUsed: _asDouble(json['limit_used']),
      spaceUsed: _asInt(json['space_used']),
    );
  }

  bool get hasActivePremium {
    if (premiumUntil == null) return false;
    return premiumUntil!.isAfter(DateTime.now());
  }

  String get subscriptionStatus => hasActivePremium ? 'Active' : 'Inactive';

  String get formattedPremiumExpiry => _formatDate(premiumUntil);

  /// Fair-use limit consumed as a whole-number percentage (e.g. "13%").
  String get formattedLimitUsed =>
      '${(limitUsed * 100).clamp(0, 100).toStringAsFixed(0)}%';

  String get formattedSpaceUsed => _formatBytes(spaceUsed);

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is num) return value.toInt();
    return 0;
  }

  static DateTime? _tryParseEpoch(dynamic value) {
    final seconds = _asInt(value);
    if (seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    if (unit <= 1) {
      return '${size.toStringAsFixed(0)} ${units[unit]}';
    }
    return '${size.toStringAsFixed(2)} ${units[unit]}';
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
