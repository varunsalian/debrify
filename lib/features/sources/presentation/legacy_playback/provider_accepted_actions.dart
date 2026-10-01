import 'dart:async';

import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/provider_source_actions.dart';
import 'package:debrify/features/sources/data/source_download.dart';
import 'package:debrify/features/sources/data/source_playlist.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/features/sources/presentation/source_download_action.dart';
import 'package:debrify/features/sources/presentation/source_download_picker.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter/material.dart';

final class ProviderAcceptedActions {
  const ProviderAcceptedActions._();

  /// Native media-server streams need credential-aware background downloads,
  /// including redirect and resource-revocation handling, before enabling this.
  static bool supportsDirectStreamDownload(Torrent torrent) =>
      SourceDownload.supports(torrent);

  /// Download a direct/external addon stream to device (parity with the old
  /// screen's direct-stream "Download to device" action). Follows redirects
  /// first — MediaFusion-style playback URLs 30x-hop to the real file — then
  /// queues the resolved URL.
  static Future<void> downloadDirectStream(
    BuildContext context,
    Torrent torrent,
  ) => downloadSource(context, torrent, const SourceDownload());

  /// User-requested provider actions (download, playlist add, ZIP, transfer,
  /// keep-on-provider) finish once accepted, even if the user leaves the
  /// screen meanwhile — as before the refactor. The operations still reject a
  /// profile switch through their captured owner, and every snackbar checks
  /// `context.mounted` itself.
  static bool acceptedProviderAction() => true;

  static Future<void> download(
    BuildContext context,
    ResolvedSource r,
    Torrent torrent,
    String provider, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    if (r.playlist != null && r.playlist!.length > 1) {
      final chosen = await showSourceDownloadPicker(context, r.playlist!);
      if (chosen == null || chosen.isEmpty || !actions.isCurrent) return;
      final n = await actions.queueEntries(
        chosen,
        provider: provider,
        torrentName: torrent.displayTitle,
      );
      if (context.mounted && actions.isCurrent) {
        SourceLoadingOverlays.snack(
          context,
          n > 0
              ? 'Queued $n file(s) for download.'
              : 'Could not queue downloads.',
        );
      }
      return;
    }
    if (r.playlist?.isNotEmpty == true) {
      final n = await actions.queueEntries(
        r.playlist!,
        provider: provider,
        torrentName: torrent.displayTitle,
      );
      if (context.mounted && actions.isCurrent) {
        SourceLoadingOverlays.snack(
          context,
          n > 0 ? 'Download queued.' : 'Could not queue download.',
        );
      }
      return;
    }
    final url = r.downloadUrls.isNotEmpty ? r.downloadUrls.first : null;
    if (url == null) {
      SourceLoadingOverlays.snack(
        context,
        'Nothing to download for this source.',
      );
      return;
    }
    try {
      await actions.queueUrl(
        url,
        provider: provider,
        fileName: r.fileName ?? torrent.displayTitle,
        torrentName: torrent.displayTitle,
      );
    } catch (_) {}
    // Preserve the legacy single-URL feedback, including its best-effort enqueue.
    if (context.mounted && actions.isCurrent) {
      SourceLoadingOverlays.snack(context, 'Download queued.');
    }
  }

  static Future<void> addToPlaylist(
    BuildContext context,
    ResolvedSource r,
    Torrent torrent,
    String provider, {
    PlaybackMeta? meta,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final playlist = SourcePlaylist(
      owner: sourceBindings.owner,
      canContinue: acceptedProviderAction,
    );
    if (!playlist.isCurrent) return;
    final ok = await playlist.add(r, torrent, provider, meta: meta);
    if (context.mounted && playlist.isCurrent) {
      SourceLoadingOverlays.snack(
        context,
        ok ? 'Added to playlist.' : 'Already in playlist.',
      );
    }
  }

  static Future<String> postAction(String provider) async {
    switch (provider) {
      case 'torbox':
        return TorboxStorage.getTorboxPostTorrentAction();
      case 'premiumize':
        return PremiumizeStorage.getPremiumizePostTorrentAction();
      case 'alldebrid':
        return AllDebridStorage.getAllDebridPostTorrentAction();
      case 'pikpak':
        return PikpakStorage.getPikPakPostTorrentAction();
      default:
        return RealDebridStorage.getPostTorrentAction();
    }
  }
}
