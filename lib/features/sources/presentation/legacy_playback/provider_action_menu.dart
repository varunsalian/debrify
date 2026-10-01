import 'dart:async';

import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/provider_accepted_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/provider_zip_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_play_action.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_provider_choice.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/widgets/debrid_action_sheet.dart';
import 'package:debrify/widgets/debrify_tv_channel_add_bridge.dart';
import 'package:flutter/material.dart';

final class ProviderActionMenu {
  const ProviderActionMenu._();

  /// The app's real post-add chooser (glass card + styled tiles), with the full
  /// option set — Play / Download / Add to playlist / Add to channel / Open in
  /// provider tab — matching Home's per-provider sheets.
  static Future<void> showChooser(
    BuildContext context,
    ResolvedSource r,
    Torrent torrent,
    String provider, {
    String? magnet,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    String searchKeyword = '',
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final hasVideo = r.playUrl != null && r.playUrl!.isNotEmpty;
    final name = torrent.displayTitle;
    await showDebridActionSheet(
      context,
      providerLabel: SourceProviderChoice.label(provider),
      torrentName: name,
      gradient: SourceProviderChoice.providerGradient(provider),
      providerIcon: SourceProviderChoice.providerIcon(provider),
      subtitle: hasVideo
          ? 'Ready on ${SourceProviderChoice.label(provider)}. Choose your next step.'
          : 'Added to ${SourceProviderChoice.label(provider)}.',
      actions: [
        DebridActionItem(
          icon: Icons.play_circle_fill_rounded,
          color: const Color(0xFF10B981),
          title: 'Play now',
          subtitle: 'Stream it right away.',
          pillLabel: 'Play',
          enabled: hasVideo,
          onTap: () => unawaited(
            SourcePlayAction.play(
              context,
              r,
              torrent,
              provider: provider,
              meta: meta,
              sources: sources,
              sourceIndex: sourceIndex,

              sourceBindings: sourceBindings,
            ),
          ),
        ),
        // The service refuses anyway, but a profile that can't download
        // shouldn't be offered a button that only fails.
        if (ProfilePolicyGuard.allowsSync(ProfileFeature.downloads))
          DebridActionItem(
            icon: Icons.download_rounded,
            color: const Color(0xFF3B82F6),
            title: 'Download to device',
            subtitle:
                'Grab the file(s) via ${SourceProviderChoice.label(provider)}.',
            pillLabel: 'Download',
            onTap: () => unawaited(
              ProviderAcceptedActions.download(
                context,
                r,
                torrent,
                provider,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
        DebridActionItem(
          icon: Icons.playlist_add_rounded,
          color: const Color(0xFF8B5CF6),
          title: 'Add to playlist',
          subtitle: 'Save it to your playlist for later.',
          pillLabel: 'Playlist',
          enabled: hasVideo,
          onTap: () => unawaited(
            ProviderAcceptedActions.addToPlaylist(
              context,
              r,
              torrent,
              provider,
              meta: meta,
              sourceBindings: sourceBindings,
            ),
          ),
        ),
        DebridActionItem(
          icon: Icons.connected_tv,
          color: const Color(0xFF14B8A6),
          title: 'Add to channel',
          subtitle: 'Cache this torrent in a Debrify TV channel.',
          onTap: () => unawaited(
            DebrifyTvChannelAddBridge.addTorrentsToChannel(
              context,
              torrents: [torrent],
              searchKeyword: searchKeyword,
              owner: sourceBindings.owner,
              canContinue: () => sourceBindings.isCurrent,
            ),
          ),
        ),
        // TorBox power actions: download the whole-torrent ZIP to device, or
        // copy its permalink (parity with the old screen's TorBox download menu).
        if (provider == 'torbox' && r.torboxTorrentId != null) ...[
          DebridActionItem(
            icon: Icons.folder_zip_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Download as ZIP',
            subtitle: 'Download all files as a ZIP to this device.',
            onTap: () => unawaited(
              ProviderZipActions.downloadTorboxZip(
                context,
                r.torboxTorrentId!,
                name,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
          DebridActionItem(
            icon: Icons.link_rounded,
            color: const Color(0xFFEC4899),
            title: 'Copy Download Link (Zip)',
            subtitle: 'Copy ZIP download link to clipboard.',
            onTap: () => unawaited(
              ProviderZipActions.copyTorboxZipLink(
                context,
                r.torboxTorrentId!,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
        ],
        // Premiumize power actions (need the magnet — cloud transfer + ZIP).
        if (provider == 'premiumize' && magnet != null) ...[
          DebridActionItem(
            icon: Icons.cloud_upload_rounded,
            color: const Color(0xFFF59E0B),
            title: 'Transfer to Premiumize',
            subtitle: 'Add this torrent to your Premiumize cloud.',
            onTap: () => unawaited(
              ProviderZipActions.premiumizeTransfer(
                context,
                magnet,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
          DebridActionItem(
            icon: Icons.folder_zip_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Download as ZIP',
            subtitle: 'Transfer to cloud and download all files as a ZIP.',
            onTap: () => unawaited(
              ProviderZipActions.premiumizeZip(
                context,
                magnet,
                name,
                copyOnly: false,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
          DebridActionItem(
            icon: Icons.link_rounded,
            color: const Color(0xFFEC4899),
            title: 'Copy ZIP Link',
            subtitle: 'Copy ZIP download link to clipboard.',
            onTap: () => unawaited(
              ProviderZipActions.premiumizeZip(
                context,
                magnet,
                name,
                copyOnly: true,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
        ],
        if (r.openInTab != null)
          DebridActionItem(
            icon: Icons.open_in_new_rounded,
            color: const Color(0xFF6366F1),
            title: 'Open in provider tab',
            subtitle: r.isRarArchive
                ? 'Not available for RAR archives'
                : 'View it in ${SourceProviderChoice.label(provider)}.',
            enabled: !r.isRarArchive,
            onTap: () {
              if (context.mounted && sourceBindings.isCurrent) {
                r.openInTab!.call();
              }
            },
          ),
      ],
    );
  }
}
