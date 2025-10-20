class TorboxUser {
  final int id;
  final String authId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int plan;
  final bool isSubscribed;
  final DateTime? premiumExpiresAt;
  final DateTime? cooldownUntil;
  final String email;
  final String userReferral;
  final String baseEmail;
  final int totalBytesDownloaded;
  final int totalBytesUploaded;
  final int torrentsDownloaded;
  final int webDownloadsDownloaded;
  final int usenetDownloadsDownloaded;
  final int additionalConcurrentSlots;
  final bool longTermSeeding;
  final bool longTermStorage;
  final bool isVendor;
  final int? vendorId;
  final int purchasesReferred;

  TorboxUser({
    required this.id,
    required this.authId,
    required this.createdAt,
    required this.updatedAt,
    required this.plan,
    required this.isSubscribed,
    required this.premiumExpiresAt,
    required this.cooldownUntil,
    required this.email,
    required this.userReferral,
    required this.baseEmail,
    required this.totalBytesDownloaded,
    required this.totalBytesUploaded,
    required this.torrentsDownloaded,
    required this.webDownloadsDownloaded,
    required this.usenetDownloadsDownloaded,
    required this.additionalConcurrentSlots,
    required this.longTermSeeding,
    required this.longTermStorage,
    required this.isVendor,
    required this.vendorId,
    required this.purchasesReferred,
  });

  factory TorboxUser.fromJson(Map<String, dynamic> json) {
    return TorboxUser(
      id: _asInt(json['id']),
      authId: json['auth_id'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      plan: _asInt(json['plan']),
      isSubscribed: json['is_subscribed'] as bool? ?? false,
      premiumExpiresAt: _tryParseDate(json['premium_expires_at'] as String?),
      cooldownUntil: _tryParseDate(json['cooldown_until'] as String?),
      email: json['email'] as String? ?? '',
      userReferral: json['user_referral'] as String? ?? '',
      baseEmail: json['base_email'] as String? ?? '',
      totalBytesDownloaded: _asInt(json['total_bytes_downloaded']),
      totalBytesUploaded: _asInt(json['total_bytes_uploaded']),
      torrentsDownloaded: _asInt(json['torrents_downloaded']),
      webDownloadsDownloaded: _asInt(json['web_downloads_downloaded']),
      usenetDownloadsDownloaded: _asInt(json['usenet_downloads_downloaded']),
      additionalConcurrentSlots: _asInt(json['additional_concurrent_slots']),
      longTermSeeding: json['long_term_seeding'] as bool? ?? false,
      longTermStorage: json['long_term_storage'] as bool? ?? false,
      isVendor: json['is_vendor'] as bool? ?? false,
      vendorId: json['vendor_id'] == null ? null : _asInt(json['vendor_id']),
      purchasesReferred: _asInt(json['purchases_referred']),
    );
  }

  bool get hasActiveSubscription {
    if (!isSubscribed) return false;
    if (premiumExpiresAt == null) return true;
    return premiumExpiresAt!.isAfter(DateTime.now());
  }

  String get subscriptionStatus => hasActiveSubscription
      ? 'Active'
      : (isSubscribed ? 'Expired' : 'Inactive');

  String get formattedPremiumExpiry => _formatDate(premiumExpiresAt);

  String get formattedCooldown => _formatDate(cooldownUntil);

  String get formattedTotalDownloaded => _formatBytes(totalBytesDownloaded);

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is num) return value.toInt();
    return 0;
  }

  static DateTime? _tryParseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
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
