import 'package:flutter/material.dart';

enum OnboardStep { mode, services, key, engines, trackers, importing, done }

enum OnboardLayout { phone, tablet, stage }

OnboardLayout resolveOnboardLayout({
  required bool isTelevision,
  required Size size,
}) {
  if (isTelevision) return OnboardLayout.stage;
  if (size.width < 600) return OnboardLayout.phone;
  if (size.width <= 1000) return OnboardLayout.tablet;
  return OnboardLayout.stage;
}

enum IntegrationType { realDebrid, torbox, pikpak, premiumize, allDebrid }

class IntegrationMeta {
  const IntegrationMeta({
    required this.type,
    required this.title,
    required this.url,
    required this.linkLabel,
    required this.inputLabel,
    required this.hint,
    required this.description,
    required this.color,
    required this.icon,
    this.keyLength,
  });

  final IntegrationType type;
  final String title;
  final String url;
  final String linkLabel;
  final String inputLabel;
  final String hint;
  final String description;
  final Color color;
  final IconData icon;
  final int? keyLength;
}

const Map<IntegrationType, IntegrationMeta> integrationMeta = {
  IntegrationType.realDebrid: IntegrationMeta(
    type: IntegrationType.realDebrid,
    title: 'Real-Debrid',
    url: 'https://real-debrid.com/apitoken',
    linkLabel: 'Open token page',
    inputLabel: 'API token',
    hint: 'Paste or type your token',
    description: 'Turns cached torrents into direct, high-speed streams.',
    color: Color(0xFF3569E8),
    icon: Icons.cloud_download_rounded,
    keyLength: 40,
  ),
  IntegrationType.torbox: IntegrationMeta(
    type: IntegrationType.torbox,
    title: 'TorBox',
    url: 'https://torbox.app/settings?section=account',
    linkLabel: 'Open account settings',
    inputLabel: 'API key',
    hint: 'Paste or type your API key',
    description: 'Cloud downloads, cached torrents, and Usenet in one place.',
    color: Color(0xFF8B5CF6),
    icon: Icons.flash_on_rounded,
  ),
  IntegrationType.pikpak: IntegrationMeta(
    type: IntegrationType.pikpak,
    title: 'PikPak',
    url: 'https://mypikpak.com/drive/login',
    linkLabel: 'Open PikPak',
    inputLabel: 'Email',
    hint: 'you@example.com',
    description: 'Play files and magnet downloads from your PikPak drive.',
    color: Color(0xFF10B981),
    icon: Icons.cloud_queue_rounded,
  ),
  IntegrationType.premiumize: IntegrationMeta(
    type: IntegrationType.premiumize,
    title: 'Premiumize',
    url: 'https://www.premiumize.me/account',
    linkLabel: 'Open account page',
    inputLabel: 'API key',
    hint: 'Paste or type your API key',
    description: 'Premium cloud storage, cached torrents, and direct links.',
    color: Color(0xFFFB923C),
    icon: Icons.workspace_premium_rounded,
  ),
  IntegrationType.allDebrid: IntegrationMeta(
    type: IntegrationType.allDebrid,
    title: 'AllDebrid',
    url: 'https://alldebrid.com/apikeys',
    linkLabel: 'Open API keys page',
    inputLabel: 'API key',
    hint: 'Paste or type your API key',
    description: 'Unlock cached torrents and supported file hosts.',
    color: Color(0xFF26A69A),
    icon: Icons.all_inclusive_rounded,
  ),
};

@immutable
class OnboardSummary {
  const OnboardSummary({
    this.services = const <String>[],
    this.engines = const <String>[],
    this.trackers = const <String>[],
  });

  final List<String> services;
  final List<String> engines;
  final List<String> trackers;
}
