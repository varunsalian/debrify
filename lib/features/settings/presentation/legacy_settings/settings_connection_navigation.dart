import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/alldebrid_settings_page.dart';
import 'package:debrify/screens/settings/debrify_tv_settings_page.dart';
import 'package:debrify/screens/settings/indexer_managers_settings_page.dart';
import 'package:debrify/screens/settings/iptv_channel_order_page.dart';
import 'package:debrify/screens/settings/iptv_settings_page.dart';
import 'package:debrify/screens/settings/mdblist_settings_page.dart';
import 'package:debrify/screens/settings/media_server_settings_page.dart';
import 'package:debrify/screens/settings/pikpak_settings_page.dart';
import 'package:debrify/screens/settings/premiumize_settings_page.dart';
import 'package:debrify/screens/settings/real_debrid_settings_page.dart';
import 'package:debrify/screens/settings/simkl_settings_page.dart';
import 'package:debrify/screens/settings/stremio_tv_settings_page.dart';
import 'package:debrify/screens/settings/torbox_settings_page.dart';
import 'package:debrify/screens/settings/torrent_settings_page.dart';
import 'package:debrify/screens/settings/tracking_settings_page.dart';
import 'package:debrify/screens/settings/trakt_settings_page.dart';
import 'package:debrify/screens/settings/webdav_settings_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/sidebar_storage.dart';
import 'package:debrify/services/storage/torrent_provider_storage.dart';
import 'package:flutter/material.dart';
import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsConnectionNavigation {
  SettingsConnectionNavigation(this._summaries, this._deps);
  final ({
    Future<bool> Function(ProfileFeature feature) ensureProfileFeature,
    void Function() focusFirstCard,
    Future<void> Function() loadSummaries,
    Future<void> Function() reloadAppearanceSummaries,
    BuildContext Function() context,
    bool Function() mounted,
    StateSetter setState,
  })
  _deps;
  final SettingsSummaries _summaries;

  Future<void> openTorrentSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.torrentSearch)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const TorrentSettingsPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  Future<void> openIndexerManagersSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.torrentSearch)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const IndexerManagersSettingsPage());
    if (!context.mounted) return;

    final configs = await TorrentProviderStorage.getIndexerManagerConfigs(
      forSettings: true,
    );
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.indexerManagersConfigured = configs.isNotEmpty;
      _summaries.indexerManagersStatus = configs.isNotEmpty
          ? 'Active'
          : 'Not configured';
      _summaries.indexerManagersCaption = configs.isNotEmpty
          ? '${configs.length} engine${configs.length == 1 ? '' : 's'} configured'
          : 'Connect Jackett or Prowlarr';
    });
  }

  Future<void> openDebrifyTvSettings() async {
    final context = _deps.context();
    await pushSettingsPage(context, const DebrifyTvSettingsPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  /// Stremio TV's channel settings. The row lives on the Stremio TV screen
  /// (not in Settings), but the page is self-contained — search deep-links
  /// into it so "random episodes"/"rotation" are findable from Settings.
  Future<void> openStremioTvSettings() async {
    final context = _deps.context();
    await pushSettingsPage(context, const StremioTvSettingsPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  Future<void> openPikPakSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const PikPakSettingsPage(),
    );
    if (!context.mounted) return;
    await _deps.loadSummaries();
    if (loggedOut == true) {
      _deps.focusFirstCard();
    }
  }

  Future<void> openMediaServerSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const MediaServerSettingsPage());
    if (context.mounted) await _deps.loadSummaries();
  }

  Future<void> openWebDavSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const WebDavSettingsPage());
    if (!context.mounted) return;
    await _deps.loadSummaries();
  }

  Future<void> openTraktSettings() async {
    if (!await _deps.ensureProfileFeature(
      ProfileFeature.trackersAndDiscovery,
    )) {
      return;
    }
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const TraktSettingsPage());
    if (!context.mounted) return;
    await _deps.loadSummaries();
  }

  Future<void> openTrackingSettings() async {
    if (!await _deps.ensureProfileFeature(
      ProfileFeature.trackersAndDiscovery,
    )) {
      return;
    }
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const TrackingSettingsPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  Future<void> openSimklSettings() async {
    if (!await _deps.ensureProfileFeature(
      ProfileFeature.trackersAndDiscovery,
    )) {
      return;
    }
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const SimklSettingsPage());
    if (!context.mounted) return;
    await _deps.loadSummaries();
  }

  Future<void> openMdblistSettings() async {
    if (!await _deps.ensureProfileFeature(
      ProfileFeature.trackersAndDiscovery,
    )) {
      return;
    }
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const MdblistSettingsPage());
    if (!context.mounted) return;
    await _deps.loadSummaries();
  }

  /// Phone/small-window chrome choice: classic bottom bar (default) vs the
  /// floating glass button. Applies live — MainPageBridge tells the shell.
  Future<void> openNavigationSettings() async {
    final current = await SidebarStorage.getPhoneNavStyle();
    if (!_deps.mounted()) return;

    // The dialog RETURNS the choice; the write is awaited here before the
    // bridge fires. Popping first and writing unawaited (the old shape)
    // let an immediate pref re-read race the write.
    final context = _deps.context();
    if (!context.mounted) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        Widget option({
          required IconData icon,
          required String title,
          required String subtitle,
          required String value,
        }) {
          final selected = current == value;
          return ListTile(
            leading: Icon(
              icon,
              color: selected ? const Color(0xFFC7BFFF) : null,
            ),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
            trailing: selected
                ? const Icon(Icons.check_rounded, color: Color(0xFFC7BFFF))
                : null,
            onTap: () => Navigator.of(dialogContext).pop(value),
          );
        }

        return AlertDialog(
          title: const Text('Navigation'),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                icon: Icons.call_to_action_rounded,
                title: 'Classic bar',
                subtitle:
                    'Bottom tabs \u2014 Home, three slots you pick, More '
                    'holds the rest',
                value: 'classic',
              ),
              option(
                icon: Icons.blur_on_rounded,
                title: 'Floating button',
                subtitle: 'The glass button with the expanding menu',
                value: 'floating',
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null || chosen == current || !context.mounted) return;
    await SidebarStorage.setPhoneNavStyle(chosen);
    if (!context.mounted) return;
    _deps.setState(() => _summaries.phoneNavStyle = chosen);
    MainPageBridge.navPrefsChanged?.call();
  }

  Future<void> openIptvSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.iptv)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const IptvSettingsPage());
    if (!context.mounted) return;
    // IPTV settings hosts its own Appearance/Player guide sections — keep
    // the Appearance row captions honest.
    await _deps.reloadAppearanceSummaries();
  }

  Future<void> openIptvChannelOrder() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.iptv)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(context, const IptvChannelOrderPage());
  }

  /// IPTV settings landing on the add-source form — what a search for "add
  /// playlist" is actually after. Without the flag the wide (TV/desktop)
  /// layout opens its source rail instead, and the form is another hop away.
  Future<void> openIptvAddSource() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.iptv)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    await pushSettingsPage(
      context,
      const IptvSettingsPage(openAddSource: true),
    );
    if (!context.mounted) return;
    // The two-pane reached from here still exposes the Appearance/Player
    // guide sections — keep the Appearance row captions honest.
    await _deps.reloadAppearanceSummaries();
  }

  Future<void> openRealDebridSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const RealDebridSettingsPage(),
    );
    if (!context.mounted) return;
    await _deps.loadSummaries();
    if (loggedOut == true) {
      _deps.focusFirstCard();
    }
  }

  Future<void> openTorboxSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const TorboxSettingsPage(),
    );
    if (!context.mounted) return;
    await _deps.loadSummaries();
    if (loggedOut == true) {
      _deps.focusFirstCard();
    }
  }

  Future<void> openPremiumizeSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const PremiumizeSettingsPage(),
    );
    if (!context.mounted) return;
    await _deps.loadSummaries();
    if (loggedOut == true) {
      _deps.focusFirstCard();
    }
  }

  Future<void> openAllDebridSettings() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!_deps.mounted()) return;
    final context = _deps.context();
    if (!context.mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const AllDebridSettingsPage(),
    );
    if (!context.mounted) return;
    await _deps.loadSummaries();
    if (loggedOut == true) {
      _deps.focusFirstCard();
    }
  }
}
