import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'storage_service.dart';

class SupportRemoteConfig {
  final SupportDonationConfig donation;
  final SupportCampaignConfig campaign;

  const SupportRemoteConfig({required this.donation, required this.campaign});

  factory SupportRemoteConfig.fromJson(Map<String, dynamic> json) {
    return SupportRemoteConfig(
      donation: SupportDonationConfig.fromJson(
        (json['support'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      ),
      campaign: SupportCampaignConfig.fromJson(
        (json['campaign'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'support': donation.toJson(),
      'campaign': campaign.toJson(),
    };
  }

  static const fallback = SupportRemoteConfig(
    donation: SupportDonationConfig.empty,
    campaign: SupportCampaignConfig.empty,
  );
}

class SupportDonationConfig {
  final List<SupportDonationProvider> providers;
  final String settingsLabel;
  final String settingsSubtitle;

  const SupportDonationConfig({
    required this.providers,
    required this.settingsLabel,
    required this.settingsSubtitle,
  });

  static const empty = SupportDonationConfig(
    providers: <SupportDonationProvider>[],
    settingsLabel: 'Support Debrify',
    settingsSubtitle: 'Help fund development with a donation',
  );

  factory SupportDonationConfig.fromJson(Map<String, dynamic> json) {
    final providerItems =
        (json['providers'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => SupportDonationProvider.fromJson(
                item.cast<String, dynamic>(),
              ),
            )
            .where((item) => item.isValid)
            .toList() ??
        <SupportDonationProvider>[];

    return SupportDonationConfig(
      providers: providerItems,
      settingsLabel: (json['settings_label'] as String? ?? '').trim().isEmpty
          ? empty.settingsLabel
          : (json['settings_label'] as String).trim(),
      settingsSubtitle:
          (json['settings_subtitle'] as String? ?? '').trim().isEmpty
          ? empty.settingsSubtitle
          : (json['settings_subtitle'] as String).trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'providers': providers.map((item) => item.toJson()).toList(),
      'settings_label': settingsLabel,
      'settings_subtitle': settingsSubtitle,
    };
  }

  bool get hasProviders => providers.isNotEmpty;
}

class SupportDonationProvider {
  final String id;
  final String name;
  final String url;
  final String subtitle;

  const SupportDonationProvider({
    required this.id,
    required this.name,
    required this.url,
    required this.subtitle,
  });

  factory SupportDonationProvider.fromJson(Map<String, dynamic> json) {
    return SupportDonationProvider(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      url: (json['url'] as String? ?? '').trim(),
      subtitle: (json['subtitle'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'url': url,
      'subtitle': subtitle,
    };
  }

  bool get isValid => id.isNotEmpty && name.isNotEmpty && _isLikelyWebUrl(url);
}

class SupportCampaignConfig {
  final bool enabled;
  final String id;
  final String title;
  final String message;
  final String buttonLabel;
  final String startUtc;
  final String endUtc;

  const SupportCampaignConfig({
    required this.enabled,
    required this.id,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.startUtc,
    required this.endUtc,
  });

  static const empty = SupportCampaignConfig(
    enabled: false,
    id: '',
    title: '',
    message: '',
    buttonLabel: 'Donate on Ko-fi',
    startUtc: '',
    endUtc: '',
  );

  factory SupportCampaignConfig.fromJson(Map<String, dynamic> json) {
    return SupportCampaignConfig(
      enabled: json['enabled'] == true,
      id: (json['id'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? '').trim(),
      message: (json['message'] as String? ?? '').trim(),
      buttonLabel: (json['button_label'] as String? ?? '').trim().isEmpty
          ? empty.buttonLabel
          : (json['button_label'] as String).trim(),
      startUtc: (json['start_utc'] as String? ?? '').trim(),
      endUtc: (json['end_utc'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'id': id,
      'title': title,
      'message': message,
      'button_label': buttonLabel,
      'start_utc': startUtc,
      'end_utc': endUtc,
    };
  }

  bool get hasContent =>
      id.isNotEmpty && title.isNotEmpty && message.isNotEmpty;

  bool isActiveAt(
    DateTime nowUtc, {
    required List<SupportDonationProvider> providers,
  }) {
    if (!enabled || !hasContent || providers.isEmpty) return false;

    final start = DateTime.tryParse(startUtc)?.toUtc();
    final end = DateTime.tryParse(endUtc)?.toUtc();
    if (start == null || end == null) return false;

    return !nowUtc.isBefore(start) && !nowUtc.isAfter(end);
  }
}

class SupportRemoteConfigService {
  SupportRemoteConfigService._();

  static final SupportRemoteConfigService instance =
      SupportRemoteConfigService._();

  static const String _remoteConfigUrl =
      'https://gitlab.com/varunbsalian/debrify-remote-config/-/raw/main/remote_config.json';
  static const String _fallbackAssetPath =
      'assets/config/app_remote_config.json';

  Future<SupportRemoteConfig> loadCachedOrFallback() async {
    final cached = await _loadCached();
    if (cached != null) return cached;
    return _loadFallback();
  }

  Future<SupportRemoteConfig> loadConfig() async {
    final baseline = await loadCachedOrFallback();
    try {
      final response = await http.get(Uri.parse(_remoteConfigUrl));
      if (response.statusCode != 200) {
        debugPrint(
          'SupportRemoteConfigService: remote fetch failed with ${response.statusCode}',
        );
        return baseline;
      }

      final config = _decode(response.body);
      await StorageService.setSupportRemoteConfigCache(
        jsonEncode(config.toJson()),
      );
      return config;
    } catch (e) {
      debugPrint('SupportRemoteConfigService: remote fetch failed: $e');
      return baseline;
    }
  }

  Future<SupportRemoteConfig?> _loadCached() async {
    final raw = await StorageService.getSupportRemoteConfigCache();
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return _decode(raw);
    } catch (e) {
      debugPrint('SupportRemoteConfigService: invalid cached config: $e');
      return null;
    }
  }

  Future<SupportRemoteConfig> _loadFallback() async {
    try {
      final raw = await rootBundle.loadString(_fallbackAssetPath);
      return _decode(raw);
    } catch (e) {
      debugPrint('SupportRemoteConfigService: fallback asset load failed: $e');
      return SupportRemoteConfig.fallback;
    }
  }

  SupportRemoteConfig _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Support config is not a JSON object');
    }
    return SupportRemoteConfig.fromJson(decoded);
  }
}

bool _isLikelyWebUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}
