import 'dart:async';
import 'package:debrify/features/settings/presentation/legacy_settings/search_index/settings_search_index.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_account_captions.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_backup.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_connection_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_connections.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_diagnostics.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_download_location.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_maintenance.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_page_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_platform_gates.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_profile_actions.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_release_details.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_restore.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_search_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_snacks.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summaries.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summary_loader.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summary_refresh.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_updates.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/update_service.dart';
import 'package:flutter/material.dart';
import 'settings_index_composition.dart';
import 'settings_layout_composition.dart';

/// One State owns these lazy sections; construction only wires borrowed dependencies.
class SettingsSections {
  SettingsSections(this._summaries, this._firstCardFocusNode, this._deps);
  final SettingsSummaries _summaries;
  final FocusNode _firstCardFocusNode;
  final ({
    BuildContext Function() context,
    bool Function() mounted,
    StateSetter setState,
    Map<String, Future<Object?> Function()> Function() summaryReadOverrides,
    VoidCallback focusFirstCard,
  })
  _deps;

  late final SettingsPlatformGates _platformGates = SettingsPlatformGates(
    _summaries,
  );

  late final SettingsSearchNavigation _searchNavigation =
      SettingsSearchNavigation((
        buildSearchIndex: () => _searchIndex.buildSearchIndex(),
        context: _deps.context,
        mounted: _deps.mounted,
        setState: _deps.setState,
      ));

  late final SettingsSummaryRefresh _summaryRefresh =
      SettingsSummaryRefresh(_summaries, (
        loadSummariesForCurrentProfile: () =>
            _summaryLoader.loadSummariesForCurrentProfile(),
        defaultDownloadLocationLabel: () =>
            _downloadLocation.defaultDownloadLocationLabel,
        downloadLocationSupported: () =>
            _downloadLocation.downloadLocationSupported,
        downloadLocationUsesSaf: () =>
            _downloadLocation.downloadLocationUsesSaf,
        mounted: _deps.mounted,
        setState: _deps.setState,
      ));

  late final SettingsSummaryLoader _summaryLoader =
      SettingsSummaryLoader(_summaries, (
        applyAllDebridUserInfo: (dynamic allDebridUser) =>
            _accountCaptions.applyAllDebridUserInfo(allDebridUser),
        applyPremiumizeUserInfo: (dynamic premiumizeUser) =>
            _accountCaptions.applyPremiumizeUserInfo(premiumizeUser),
        applyRdUserInfo: (dynamic user) =>
            _accountCaptions.applyRdUserInfo(user),
        applyTorboxUserInfo: (dynamic torboxUser) =>
            _accountCaptions.applyTorboxUserInfo(torboxUser),
        pendingCredentialTypes: () => _summaryRefresh.pendingCredentialTypes(),
        activeProfileMayExportDiagnostics: () =>
            _diagnostics.activeProfileMayExportDiagnostics(),
        mounted: _deps.mounted,
        setState: _deps.setState,
        summaryReadOverrides: _deps.summaryReadOverrides,
      ));

  late final SettingsAccountCaptions _accountCaptions = SettingsAccountCaptions(
    _summaries,
  );

  late final SettingsUpdates _updates = SettingsUpdates(_summaries, (
    ensureProfileFeature: (ProfileFeature feature) =>
        _profileActions.ensureProfileFeature(feature),
    showReleaseDetails: (UpdateSummary summary) =>
        _releaseDetails.showReleaseDetails(summary),
    showSnack: (String message) => _snacks.showSnack(message),
    mounted: _deps.mounted,
    setState: _deps.setState,
  ));

  late final SettingsDiagnostics _diagnostics = SettingsDiagnostics(
    _summaries,
    (context: _deps.context, mounted: _deps.mounted, setState: _deps.setState),
  );

  late final SettingsPageNavigation _pageNavigation =
      SettingsPageNavigation(_summaries, (
        ensureProfileFeature: (ProfileFeature feature) =>
            _profileActions.ensureProfileFeature(feature),
        reloadAppearanceSummaries: () =>
            _summaryRefresh.reloadAppearanceSummaries(),
        context: _deps.context,
        mounted: _deps.mounted,
        setState: _deps.setState,
      ));

  late final SettingsConnectionNavigation _connectionNavigation =
      SettingsConnectionNavigation(_summaries, (
        ensureProfileFeature: (ProfileFeature feature) =>
            _profileActions.ensureProfileFeature(feature),
        focusFirstCard: () => _deps.focusFirstCard(),
        loadSummaries: () => _summaryRefresh.loadSummaries(),
        reloadAppearanceSummaries: () =>
            _summaryRefresh.reloadAppearanceSummaries(),
        context: _deps.context,
        mounted: _deps.mounted,
        setState: _deps.setState,
      ));

  late final SettingsProfileActions _profileActions =
      SettingsProfileActions(_summaries, (
        activeProfileMayExportDiagnostics: () =>
            _diagnostics.activeProfileMayExportDiagnostics(),
        loadSummaries: () => _summaryRefresh.loadSummaries(),
        context: _deps.context,
        mounted: _deps.mounted,
        setState: _deps.setState,
      ));

  late final SettingsBackup _backup = SettingsBackup((
    createProfileBackup: () => _profileActions.createProfileBackup(),
    context: _deps.context,
    mounted: _deps.mounted,
  ));

  late final SettingsRestore _restore = SettingsRestore((
    loadSummaries: () => _summaryRefresh.loadSummaries(),
    restoreProfileBackup: () => _profileActions.restoreProfileBackup(),
    context: _deps.context,
    mounted: _deps.mounted,
  ));

  late final SettingsDownloadLocation _downloadLocation =
      SettingsDownloadLocation(_summaries, (
        loadDownloadLocation: () => _summaryRefresh.loadDownloadLocation(),
        context: _deps.context,
        mounted: _deps.mounted,
      ));

  late final SettingsMaintenance _maintenance = SettingsMaintenance((
    loadSummaries: () => _summaryRefresh.loadSummaries(),
    context: _deps.context,
    mounted: _deps.mounted,
  ));

  late final SettingsReleaseDetails _releaseDetails =
      SettingsReleaseDetails(_summaries, (
        openReleasesPage: (Uri url) => _updates.openReleasesPage(url),
        startAndroidUpdateDownload: (AppRelease release) =>
            _updates.startAndroidUpdateDownload(release),
        context: _deps.context,
        mounted: _deps.mounted,
      ));

  late final SettingsAppearanceNavigation _appearanceNavigation =
      SettingsAppearanceNavigation(_summaries, (
        context: _deps.context,
        mounted: _deps.mounted,
        setState: _deps.setState,
      ));

  late final SettingsSnacks _snacks = SettingsSnacks((
    context: _deps.context,
    mounted: _deps.mounted,
  ));

  late final SettingsConnections _connections =
      SettingsConnections(_summaries, (
        openAllDebridSettings: _connectionNavigation.openAllDebridSettings,
        openIndexerManagersSettings:
            _connectionNavigation.openIndexerManagersSettings,
        openIptvSettings: _connectionNavigation.openIptvSettings,
        openMdblistSettings: _connectionNavigation.openMdblistSettings,
        openMediaServerSettings: _connectionNavigation.openMediaServerSettings,
        openPikPakSettings: _connectionNavigation.openPikPakSettings,
        openPremiumizeSettings: _connectionNavigation.openPremiumizeSettings,
        openRealDebridSettings: _connectionNavigation.openRealDebridSettings,
        openSimklSettings: _connectionNavigation.openSimklSettings,
        openTorboxSettings: _connectionNavigation.openTorboxSettings,
        openTrackingSettings: _connectionNavigation.openTrackingSettings,
        openTraktSettings: _connectionNavigation.openTraktSettings,
        openWebDavSettings: _connectionNavigation.openWebDavSettings,
      ));

  late final SettingsIndexComposition _indexComposition =
      SettingsIndexComposition(
        _summaries,
        (context: _deps.context, mounted: _deps.mounted),
        (
          appearanceNavigation: () => _appearanceNavigation,
          backup: () => _backup,
          connectionNavigation: () => _connectionNavigation,
          connections: () => _connections,
          diagnostics: () => _diagnostics,
          downloadLocation: () => _downloadLocation,
          maintenance: () => _maintenance,
          pageNavigation: () => _pageNavigation,
          platformGates: () => _platformGates,
          profileActions: () => _profileActions,
          restore: () => _restore,
          updates: () => _updates,
        ),
      );
  SettingsSearchIndex get _searchIndex => _indexComposition.searchIndex;

  late final SettingsLayoutComposition layoutComposition =
      SettingsLayoutComposition(_summaries, _firstCardFocusNode, (
        appearanceNavigation: () => _appearanceNavigation,
        backup: () => _backup,
        connectionNavigation: () => _connectionNavigation,
        connections: () => _connections,
        diagnostics: () => _diagnostics,
        downloadLocation: () => _downloadLocation,
        maintenance: () => _maintenance,
        pageNavigation: () => _pageNavigation,
        platformGates: () => _platformGates,
        profileActions: () => _profileActions,
        restore: () => _restore,
        searchNavigation: () => _searchNavigation,
        updates: () => _updates,
      ));
  SettingsSummaryRefresh get summaryRefresh => _summaryRefresh;
  SettingsUpdates get updates => _updates;
  SettingsSnacks get snacks => _snacks;
  SettingsSearchIndex get searchIndex => _searchIndex;
}
