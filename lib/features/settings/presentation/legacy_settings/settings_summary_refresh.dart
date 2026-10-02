import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/device_storage.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:debrify/services/support_remote_config_service.dart';
import 'package:flutter/material.dart';
import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsSummaryRefresh {
  SettingsSummaryRefresh(this._summaries, this._deps);
  final SettingsSummaries _summaries;
  final ({
    Future<void> Function() loadSummariesForCurrentProfile,
    String Function() defaultDownloadLocationLabel,
    bool Function() downloadLocationSupported,
    bool Function() downloadLocationUsesSaf,
    bool Function() mounted,
    StateSetter setState,
  })
  _deps;

  Future<void> loadSummaries() async {
    final startingScope = ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;
    try {
      await _deps.loadSummariesForCurrentProfile();
    } catch (error) {
      // ProfileGate retires this subtree on a switch or lock. Never publish
      // old-profile summaries into the replacement session.
      if (!_deps.mounted() ||
          ProfileLockController.instance.lockedProfileId.value != null ||
          (startingScope != null &&
              ProfileRuntime.scope.value != startingScope)) {
        return;
      }
      _summaries.summaryLoadFailed = true;
      DiagnosticLog.instance.recordEvent(
        source: 'app',
        event: 'settings_summary_load_failed',
        fields: {'errorType': DiagnosticLabel(error.runtimeType.toString())},
      );
    } finally {
      if (_deps.mounted() &&
          ProfileLockController.instance.lockedProfileId.value == null &&
          (startingScope == null ||
              ProfileRuntime.scope.value == startingScope)) {
        _deps.setState(() => _summaries.loading = false);
      }
    }
  }

  Future<Set<ConnectionResourceType>> pendingCredentialTypes() async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return const <ConnectionResourceType>{};
    }
    final scope = ProfileRuntime.capture();
    final resources = await ProfileBootstrap.registry.listGrantedResources(
      scope.profileId,
    );
    if (ProfileRuntime.scope.value != scope) {
      return const <ConnectionResourceType>{};
    }
    return resources
        .where((resource) => resource.needsReconnect)
        .map((resource) => resource.type)
        .toSet();
  }

  Future<void> loadSupportConfig() async {
    final service = SupportRemoteConfigService.instance;
    final cached = await service.loadCachedOrFallback();
    if (_deps.mounted()) {
      _deps.setState(() {
        applySupportConfig(cached);
      });
    }

    final fresh = await service.loadConfig();
    if (!_deps.mounted()) return;
    _deps.setState(() {
      applySupportConfig(fresh);
    });
  }

  void applySupportConfig(SupportRemoteConfig config) {
    _summaries.supportDonation = config.donation;
    _summaries.supportSettingsLabel = config.donation.settingsLabel;
    _summaries.supportSettingsSubtitle = config.donation.settingsSubtitle;
  }

  Future<void> loadDownloadLocation() async {
    if (!_deps.downloadLocationSupported()) return;
    final String? name = _deps.downloadLocationUsesSaf()
        ? await DeviceStorage.getDownloadTreeDisplayName()
        : await DeviceStorage.getDownloadDirPath();
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _summaries.downloadLocationSubtitle = name == null
          ? _deps.defaultDownloadLocationLabel()
          : 'Custom: $name';
    });
  }

  /// The Appearance rows quote live pref labels, but some of those prefs
  /// also have feature-local editors (the Home Screen page's layout row, the
  /// IPTV page's Appearance/Player guide sections, and Playback). Re-read those after
  /// any route that can reach them, so the captions never go stale. Never
  /// the full [loadSummaries] — these are local pref reads, no network.
  Future<void> reloadAppearanceSummaries() async {
    final tvHomeStyle = await HomeAppearanceStorage.getTvHomeStyle();
    final iptvStyle = await IptvAppearanceStorage.getIptvStyle();
    final playerGuideStyle =
        await IptvAppearanceStorage.getIptvPlayerGuideStyle();
    final playLoaderStyle = await PlayerAppearanceStorage.getPlayLoaderStyle();
    final tvPlayerControlsStyle =
        await PlayerAppearanceStorage.getTvPlayerControlsStyle();
    final debrifyTvStyle = await DebrifyTvStorage.getDebrifyTvStyle();
    final debrifyTvPlayerStyle =
        await DebrifyTvStorage.getDebrifyTvPlayerStyle();
    final playerDockStyle = await PlayerAppearanceStorage.getPlayerDockStyle();
    final playerDockPalette =
        await PlayerAppearanceStorage.getPlayerDockPalette();
    final playerDockSize = await PlayerAppearanceStorage.getPlayerDockSize();
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _summaries.tvHomeStyle = tvHomeStyle;
      _summaries.iptvStyle = iptvStyle;
      _summaries.playerGuideStyle = playerGuideStyle;
      _summaries.playLoaderStyle = playLoaderStyle;
      _summaries.tvPlayerControlsStyle = tvPlayerControlsStyle;
      _summaries.debrifyTvStyle = debrifyTvStyle;
      _summaries.debrifyTvPlayerStyle = debrifyTvPlayerStyle;
      _summaries.playerDockStyle = playerDockStyle;
      _summaries.playerDockPalette = playerDockPalette;
      _summaries.playerDockSize = playerDockSize;
    });
  }
}
