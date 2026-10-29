import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/collections_settings_page.dart';
import 'package:debrify/screens/settings/discover_settings_page.dart';
import 'package:debrify/screens/settings/external_player_settings_page.dart';
import 'package:debrify/screens/settings/filter_settings_page.dart';
import 'package:debrify/screens/settings/home_page_settings_page.dart';
import 'package:debrify/screens/settings/metadata_settings_page.dart';
import 'package:debrify/screens/settings/playback_settings_page.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/provider_settings_page.dart';
import 'package:debrify/screens/settings/quick_play_settings_page.dart';
import 'package:debrify/screens/settings/recordings_page.dart';
import 'package:debrify/screens/settings/storage_usage_route.dart';
import 'package:debrify/screens/settings/stream_badges_settings_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/widgets/remote/remote_role_picker_screen.dart';
import 'package:debrify/widgets/support_donation_chooser_dialog.dart';
import 'package:flutter/material.dart';
import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsPageNavigation {
  SettingsPageNavigation(this._summaries, this._deps);
  final ({
    Future<bool> Function(ProfileFeature feature) ensureProfileFeature,
    Future<void> Function() reloadAppearanceSummaries,
    BuildContext Function() context,
    bool Function() mounted,
    StateSetter setState,
  })
  _deps;
  final SettingsSummaries _summaries;

  Future<void> openSupportDonation() async {
    final context = _deps.context();
    await showSupportDonationChooserDialog(
      context,
      donation: _summaries.supportDonation,
      title: _summaries.supportSettingsLabel,
      // Match the settings palette (the dialog is shown from the State's
      // context, which sits above the scoped theme in build()).
      theme: settingsPageTheme(context),
    );
  }

  /// Live TV & DVR › Recordings — the same page IPTV settings and the
  /// recording dialogs open, promoted to a first-class settings row.
  Future<void> openRecordings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.recordings)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const RecordingsPage());
  }

  /// Data & Backup › Storage Usage: device-wide, open to every profile.
  Future<void> openStorageUsage() async {
    await openStorageUsagePage(_deps.context());
  }

  Future<void> openMetadataSettings() async {
    final context = _deps.context();
    await pushSettingsPage(context, const MetadataSettingsPage());
  }

  Future<void> openBadgesSettings() async {
    final context = _deps.context();
    await pushSettingsPage(context, const StreamBadgesSettingsPage());
  }

  Future<void> openCollectionsSettings() async {
    final context = _deps.context();
    await pushSettingsPage(context, const CollectionsSettingsPage());
  }

  Future<void> openHomePageSettings() async {
    final context = _deps.context();
    await pushSettingsPage(context, const HomePageSettingsPage());
    if (!context.mounted) return;
    // The Home Screen page hosts its own TV home layout row — keep the
    // Appearance row caption honest.
    await _deps.reloadAppearanceSummaries();
  }

  Future<void> openPlaybackSection(PlaybackSettingsSection section) async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.externalPlayers)) {
      return;
    }
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(
      context,
      ExternalPlayerSettingsPage(section: section),
    );
    if (!context.mounted) return;
    await _deps.reloadAppearanceSummaries();
  }

  Future<void> openExternalPlayerSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.externalPlayers)) {
      return;
    }
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const PlaybackSettingsPage());
    if (!context.mounted) return;
    await _deps.reloadAppearanceSummaries();
  }

  Future<void> openRemoteControl() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.remoteControl)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteRolePickerScreen()));
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  Future<void> openFilterSettings() async {
    final context = _deps.context();
    await pushSettingsPage(context, const FilterSettingsPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  Future<void> openProviderSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const ProviderSettingsPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  Future<void> openQuickPlaySettings() async {
    final context = _deps.context();
    await pushSettingsPage(context, const QuickPlaySettingsPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  Future<void> openDiscoverSettings() async {
    final context = _deps.context();
    await pushSettingsPage(context, const DiscoverSettingsPage());
  }
}
