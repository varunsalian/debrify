import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsAccountCaptions {
  SettingsAccountCaptions(this._summaries);
  final SettingsSummaries _summaries;

  void applyRdUserInfo(dynamic user) {
    final expiry = tryParseDate(user.expiration);
    final bool isPremium = user.isPremium;
    final bool active =
        isPremium && (expiry == null || expiry.isAfter(DateTime.now()));
    _summaries.realDebridStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _summaries.realDebridCaption = 'Expires ${formatDate(expiry)}';
    } else if (active) {
      _summaries.realDebridCaption = 'Premium account';
    } else if (isPremium && expiry != null) {
      _summaries.realDebridCaption = 'Expired ${formatDate(expiry)}';
    } else {
      _summaries.realDebridCaption = 'Premium not active';
    }
  }

  void applyTorboxUserInfo(dynamic torboxUser) {
    final expiry = torboxUser.premiumExpiresAt;
    final bool active = torboxUser.hasActiveSubscription;
    _summaries.torboxStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _summaries.torboxCaption = 'Expires ${formatDate(expiry)}';
    } else if (active) {
      _summaries.torboxCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _summaries.torboxCaption = 'Expired ${formatDate(expiry)}';
    } else {
      _summaries.torboxCaption = 'Premium not active';
    }
  }

  void applyPremiumizeUserInfo(dynamic premiumizeUser) {
    final expiry = premiumizeUser.premiumUntil;
    final bool active = premiumizeUser.hasActivePremium;
    _summaries.premiumizeStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _summaries.premiumizeCaption = 'Expires ${formatDate(expiry)}';
    } else if (active) {
      _summaries.premiumizeCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _summaries.premiumizeCaption = 'Expired ${formatDate(expiry)}';
    } else {
      _summaries.premiumizeCaption = 'Premium not active';
    }
  }

  void applyAllDebridUserInfo(dynamic allDebridUser) {
    final expiry = allDebridUser.premiumUntil;
    final bool active = allDebridUser.hasActivePremium;
    _summaries.allDebridStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _summaries.allDebridCaption = 'Expires ${formatDate(expiry)}';
    } else if (active) {
      _summaries.allDebridCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _summaries.allDebridCaption = 'Expired ${formatDate(expiry)}';
    } else {
      _summaries.allDebridCaption = 'Premium not active';
    }
  }

  DateTime? tryParseDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  String formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
