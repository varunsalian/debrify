import 'dart:io' show Platform, exit;
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/settings/profile_backup_flows.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/account_service.dart';
import 'package:debrify/services/alldebrid_account_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_app_lifecycle_participant.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_device_reset_service.dart';
import 'package:debrify/services/profiles/profile_lifecycle.dart';
import 'package:debrify/services/profiles/profile_reset_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/home_page_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/storage/playback_cleanup_storage.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/startup_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/torrent_history_storage.dart';
import 'package:debrify/services/storage/torrent_provider_storage.dart';
import 'package:debrify/services/storage/torrent_search_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import 'package:debrify/services/storage/webdav_storage.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torbox_account_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsMaintenance {
  SettingsMaintenance(this._deps);
  final ({
    Future<void> Function() loadSummaries,
    BuildContext Function() context,
    bool Function() mounted,
  })
  _deps;

  Future<void> clearDownloadData() async {
    final context = _deps.context();
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear download data?'),
        content: const Text(
          'This removes queued entries and download history. Files already saved to disk stay untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DownloadService.instance.clearDownloadDatabase();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download data cleared')));
    }
  }

  Future<void> clearPlaybackData() async {
    final context = _deps.context();
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear playback data?'),
        content: const Text(
          'This resets resume positions and cached playback preferences.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PlaybackCleanupStorage.clearAllPlaybackData();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Playback data cleared')));
    }
  }

  Future<void> resetAppData() async {
    final profileMode =
        ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted;
    ProfileAuthorizationContext? authorization;
    UserProfile? actor;
    if (profileMode) {
      authorization = await ProfileAuthorizationContext.capture(
        ProfileBootstrap.registry,
      );
      actor = await authorization.validate(ProfileBootstrap.registry);
    }
    final mayResetDevice =
        actor?.role == UserProfileRole.admin &&
        actor!.allows(ProfileFeature.manageProfiles) &&
        actor.allows(ProfileFeature.backupRestore);
    final context = _deps.context();
    final action = await showSettingsDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(profileMode ? 'Reset this profile?' : 'Reset Debrify?'),
        content: Text(
          profileMode
              ? 'This clears this profile\'s settings, history, playlists, and private app data. The profile, PIN, shared connections, active jobs, downloads, and recordings remain untouched.'
              : 'This removes saved connections, playback history, download queue, and onboarding completion. Files already saved to disk remain untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (mayResetDevice)
            TextButton(
              onPressed: () => Navigator.of(context).pop('device'),
              child: const Text('Reset device…'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('profile'),
            child: Text(profileMode ? 'Reset profile' : 'Reset app'),
          ),
        ],
      ),
    );

    if (action == null) return;

    if (profileMode && action == 'device') {
      if (!await ProfileBackupFlows(
        context,
      ).reauthenticateSensitiveProfile(actor!)) {
        return;
      }
      final typed = TextEditingController();
      final confirmed = await showSettingsDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Reset this Debrify installation?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All profiles, connections, jobs, schedules, private data, remote pairings, and device keys will be removed. Downloaded and recorded files remain on disk. The app will close and start fresh next launch.',
                ),
                const SizedBox(height: 16),
                TvTextField(
                  controller: typed,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  keyboardSubmitLabel: 'Reset device',
                  decoration: const InputDecoration(
                    labelText: 'Type RESET to continue',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) {
                    if (typed.text == 'RESET') {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: typed.text == 'RESET'
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Reset device'),
              ),
            ],
          ),
        ),
      );
      typed
        ..clear()
        ..dispose();
      if (confirmed != true) return;
      await ProfileDeviceResetService.reset(
        registry: ProfileBootstrap.registry,
        authorization: authorization!,
      );
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        exit(0);
      }
      await SystemNavigator.pop();
      return;
    }

    if (profileMode && action == 'profile') {
      await ProfileResetService(
        registry: ProfileBootstrap.registry,
        lifecycleParticipants: <ProfileLifecycleParticipant>[
          ProfileAppLifecycleParticipant(),
        ],
      ).resetActiveProfile();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile data reset. Connections and files were kept.'),
        ),
      );
      await _deps.loadSummaries();
      return;
    }

    await RealDebridStorage.deleteApiKey();
    AccountService.clearUserInfo();
    await TorboxStorage.deleteTorboxApiKey();
    TorboxAccountService.clearUserInfo();
    await PremiumizeStorage.deletePremiumizeApiKey();
    await AllDebridStorage.deleteAllDebridApiKey();
    AllDebridAccountService.clearUserInfo();
    await PikpakStorage.clearPikPakAuth();
    await WebdavStorage.clearWebDav();
    await TraktStorage.clearTraktAuth();
    // Clears the token + username AND the in-memory library cache.
    await SimklService.instance.logout();
    // Clears the key + username AND the in-memory list/items cache.
    await MdblistService.instance.logout();
    await DownloadService.instance.clearDownloadDatabase();
    // Reset is a device-local wipe: none of these clears may record synced
    // deletions, or reconnecting sync later replays them circle-wide.
    await PlaybackCleanupStorage.clearAllPlaybackData(
      recordSyncDeletions: false,
    );
    await ContinueWatchingStorage.clearContinueWatching(
      recordSyncDeletions: false,
    );
    await PlaylistStorage.clearPlaylist(recordSyncDeletions: false);
    await PlaylistStorage.clearAllPlaylistMetadata(recordSyncDeletions: false);
    await WatchlistStorage.clearMyWatchlist();
    await TorrentHistoryStorage.clearTorrentSearchHistory();
    await StartupStorage.clearAllStartupSettings();
    await HomePageStorage.clearAllHomePageSettings();
    await ProviderCredentialStorage.clearAllIntegrationStates();
    await DebrifyTvStorage.clearDebrifyTvProviderAndLegacy();
    await TorrentSearchStorage.clearAllFilterSettings();
    await TorrentProviderStorage.clearAllTorrentEngineSettings();
    await ProviderCredentialStorage.clearAllPostTorrentActions();
    await DebrifyTvStorage.clearAllDebrifyTvSettings();
    // A device-local reset must never mint circle-wide channel deletions:
    // rejoining a sync circle later means adopting its data, not erasing it.
    await DebrifyTvRepository.instance.clearAll(
      origin: WebDavSyncMutationOrigin.maintenance,
    );
    await StremioService.instance.clearAllAddons();
    await ProviderCredentialStorage.setInitialSetupComplete(false);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('App data reset. You can reconnect services anytime.'),
      ),
    );

    await _deps.loadSummaries();
  }
}
