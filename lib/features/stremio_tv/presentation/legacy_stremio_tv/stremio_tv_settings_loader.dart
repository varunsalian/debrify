import 'dart:async';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/screens/settings/stremio_tv_settings_page.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter/material.dart';

class StremioTvSettingsLoader {
  StremioTvSettingsLoader(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;

  Future<void> loadSettings() async {
    _owners.settings.rotationMinutes =
        await StremioTvStorage.getStremioTvRotationMinutes();
    _owners.settings.seriesRotationMinutes =
        await StremioTvStorage.getStremioTvSeriesRotationMinutes();
    _owners.settings.randomEpisodes =
        await StremioTvStorage.getStremioTvRandomEpisodes();
    _owners.settings.autoRefresh =
        await StremioTvStorage.getStremioTvAutoRefresh();
    _owners.settings.preferredQuality =
        await StremioTvStorage.getStremioTvPreferredQuality();
    final debridProvider = await StremioTvStorage.getStremioTvDebridProvider();
    _owners.settings.availableProviders = await _sections.settings
        ._loadAvailableProviders();
    if (debridProvider != 'auto' &&
        !_owners.settings.availableProviders.any(
          (provider) => provider.key == debridProvider,
        )) {
      _owners.settings.debridProvider = 'auto';
      await StremioTvStorage.setStremioTvDebridProvider('auto');
    } else {
      _owners.settings.debridProvider = debridProvider;
    }
    _owners.settings.rdSkipBlockedTorrents =
        await RealDebridStorage.getRdSkipBlockedTorrents();
    _owners.settings.torrentsFirst =
        await StremioTvStorage.getStremioTvTorrentsFirst();
    _owners.settings.maxStartPercent =
        await StremioTvStorage.getStremioTvMaxStartPercent();
    _owners.settings.hideNowPlaying =
        await StremioTvStorage.getStremioTvHideNowPlaying();
  }

  Future<List<MapEntry<String, String>>> _loadAvailableProviders() async {
    final providers = <MapEntry<String, String>>[];
    final rdKey = await RealDebridStorage.getApiKey();
    if (rdKey != null && rdKey.isNotEmpty) {
      providers.add(const MapEntry('realdebrid', 'Real-Debrid'));
    }
    final tbKey = await TorboxStorage.getTorboxApiKey();
    if (tbKey != null && tbKey.isNotEmpty) {
      providers.add(const MapEntry('torbox', 'TorBox'));
    }
    final pikpakEnabled = await PikpakStorage.getPikPakEnabled();
    if (pikpakEnabled) {
      providers.add(const MapEntry('pikpak', 'PikPak'));
    }
    final pmEnabled = await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    final pmKey = await PremiumizeStorage.getPremiumizeApiKey();
    if (pmEnabled && pmKey != null && pmKey.isNotEmpty) {
      providers.add(const MapEntry('premiumize', 'Premiumize'));
    }
    final adEnabled = await AllDebridStorage.getAllDebridIntegrationEnabled();
    final adKey = await AllDebridStorage.getAllDebridApiKey();
    if (adEnabled && adKey != null && adKey.isNotEmpty) {
      providers.add(const MapEntry('alldebrid', 'AllDebrid'));
    }
    return providers;
  }

  Future<void> openStremioTvSettings() async {
    await Navigator.of(
      _deps.context(),
    ).push(MaterialPageRoute(builder: (_) => const StremioTvSettingsPage()));
    if (!_deps.mounted()) return;
    await _sections.settings.loadSettings();
    if (_deps.mounted()) _deps.setState(() {});
  }

  Future<void> setDebridProvider(String value) async {
    await StremioTvStorage.setStremioTvDebridProvider(value);
    if (!_deps.mounted()) return;
    _deps.setState(() => _owners.settings.debridProvider = value);
  }

  String providerShortLabel(String provider) {
    switch (provider) {
      case 'realdebrid':
        return 'RD';
      case 'torbox':
        return 'TB';
      case 'pikpak':
        return 'PP';
      case 'premiumize':
        return 'PM';
      case 'alldebrid':
        return 'AD';
      default:
        return 'AUTO';
    }
  }

  String providerFullLabel(String provider) {
    switch (provider) {
      case 'realdebrid':
        return 'Real-Debrid';
      case 'torbox':
        return 'TorBox';
      case 'pikpak':
        return 'PikPak';
      case 'premiumize':
        return 'Premiumize';
      case 'alldebrid':
        return 'AllDebrid';
      default:
        if (_owners.settings.availableProviders.isEmpty) return 'Auto';
        return 'Auto (${_owners.settings.availableProviders.first.value})';
    }
  }
}
