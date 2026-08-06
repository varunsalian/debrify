import 'package:flutter/material.dart';

import '../models/torrent.dart';
import '../utils/dialog_tap_guard.dart';
import '../widgets/bulk_add_progress_dialog.dart';
import '../widgets/channel_created_share_dialog.dart';
import 'alldebrid_service.dart';
import 'debrid_service.dart';
import 'debrify_tv_channel_add_service.dart';
import 'pikpak_api_service.dart';
import 'premiumize_service.dart';
import 'storage_service.dart';
import 'torbox_service.dart';
import 'torrent_file_service.dart';

/// Isolated bulk-add engine for the Search tab.
///
/// Ports Home's "select multiple results → add them all to a provider (or save
/// them as a Debrify TV channel)" feature, composed only from service-layer
/// primitives so Home's ~26k-line play engine stays untouched. Each provider
/// keeps its exact semantics: TorBox cache-checks up front and honours the
/// 60/hr limit, Premiumize adds only cached torrents, Real-Debrid / AllDebrid
/// auto-remove anything uncached, and PikPak batches into a subfolder.
class TorrentBulkAddService {
  /// Only real (non-direct/external) torrents can be bulk-added.
  static List<Torrent> selectable(List<Torrent> torrents) => torrents
      .where((t) => !t.isDirectStream && !t.isExternalStream)
      .toList();

  /// Provider chooser + dispatch. [torrents] is the already-filtered selection;
  /// [keyword] seeds the channel name when creating a Debrify TV channel.
  /// Returns true if the user chose a provider/channel (so the caller can exit
  /// selection mode); false if they dismissed the chooser without picking.
  static Future<bool> showBulkAddDialog(
    BuildContext context, {
    required List<Torrent> torrents,
    required String keyword,
  }) async {
    final items = selectable(torrents);
    if (items.isEmpty) {
      _snack(context, 'No supported torrents selected.', isError: true);
      return false;
    }

    final torboxKey = await StorageService.getTorboxApiKey();
    final rdKey = await StorageService.getApiKey();
    final premiumizeKey = await StorageService.getPremiumizeApiKey();
    final allDebridKey = await StorageService.getAllDebridApiKey();
    final pikpakEnabled = await StorageService.getPikPakEnabled();
    // A provider is offered only when its integration toggle is on AND a key is
    // saved — matching Home. A saved key with the integration disabled must not
    // be bulk-addable.
    final rdIntegration = await StorageService.getRealDebridIntegrationEnabled();
    final torboxIntegration =
        await StorageService.getTorboxIntegrationEnabled();
    final premiumizeIntegration =
        await StorageService.getPremiumizeIntegrationEnabled();
    final allDebridIntegration =
        await StorageService.getAllDebridIntegrationEnabled();
    if (!context.mounted) return false;

    final torboxEnabled =
        torboxIntegration && torboxKey != null && torboxKey.isNotEmpty;
    final rdEnabled = rdIntegration && rdKey != null && rdKey.isNotEmpty;
    final premiumizeEnabled =
        premiumizeIntegration && premiumizeKey != null && premiumizeKey.isNotEmpty;
    final allDebridEnabled = allDebridIntegration &&
        allDebridKey != null &&
        allDebridKey.isNotEmpty;

    // First reachable option gets D-pad focus when the dialog opens on TV
    // (Create Channel is always enabled, so there is always a focus target).
    final autoFocused = torboxEnabled
        ? 'torbox'
        : rdEnabled
            ? 'realdebrid'
            : pikpakEnabled
                ? 'pikpak'
                : premiumizeEnabled
                    ? 'premiumize'
                    : allDebridEnabled
                        ? 'alldebrid'
                        : 'create_channel';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.25),
                    const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.playlist_add_rounded,
                color: Color(0xFF818CF8),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${items.length} torrents',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'selected',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('ADD TO CLOUD'),
              _optionTile(
                icon: Icons.flash_on_rounded,
                color: const Color(0xFF7C3AED),
                title: 'TorBox',
                subtitle: torboxEnabled
                    ? 'Limit: 60 adds per hour'
                    : 'Not configured',
                enabled: torboxEnabled,
                autofocus: autoFocused == 'torbox',
                onTap: () => Navigator.of(context).pop('torbox'),
              ),
              const SizedBox(height: 8),
              _optionTile(
                icon: Icons.cloud_rounded,
                color: const Color(0xFFE50914),
                title: 'Real-Debrid',
                subtitle: rdEnabled
                    ? 'Uncached torrents auto-removed'
                    : 'Not configured',
                enabled: rdEnabled,
                autofocus: autoFocused == 'realdebrid',
                onTap: () => Navigator.of(context).pop('realdebrid'),
              ),
              const SizedBox(height: 8),
              _optionTile(
                icon: Icons.folder_rounded,
                color: const Color(0xFF0088CC),
                title: 'PikPak',
                subtitle: pikpakEnabled ? null : 'Not configured',
                enabled: pikpakEnabled,
                autofocus: autoFocused == 'pikpak',
                onTap: () => Navigator.of(context).pop('pikpak'),
              ),
              const SizedBox(height: 8),
              _optionTile(
                icon: Icons.workspace_premium_rounded,
                color: const Color(0xFFFB923C),
                title: 'Premiumize',
                subtitle: premiumizeEnabled
                    ? 'Only cached torrents are added'
                    : 'Not configured',
                enabled: premiumizeEnabled,
                autofocus: autoFocused == 'premiumize',
                onTap: () => Navigator.of(context).pop('premiumize'),
              ),
              const SizedBox(height: 8),
              _optionTile(
                icon: Icons.all_inclusive_rounded,
                color: const Color(0xFF26A69A),
                title: 'AllDebrid',
                subtitle: allDebridEnabled
                    ? 'Only cached torrents are added'
                    : 'Not configured',
                enabled: allDebridEnabled,
                autofocus: autoFocused == 'alldebrid',
                onTap: () => Navigator.of(context).pop('alldebrid'),
              ),
              const SizedBox(height: 16),
              _sectionHeader('CREATE CHANNEL'),
              _optionTile(
                icon: Icons.live_tv_rounded,
                color: const Color(0xFF14B8A6),
                title: 'Debrify TV Channel',
                subtitle: 'Save as a local channel',
                autofocus: autoFocused == 'create_channel',
                onTap: () => Navigator.of(context).pop('create_channel'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return false;
    if (!context.mounted) return true;

    switch (result) {
      case 'pikpak':
        await _bulkAddToPikPak(context, items);
        break;
      case 'torbox':
        await _bulkAddToTorbox(context, items, torboxKey!);
        break;
      case 'realdebrid':
        await _bulkAddToRealDebrid(context, items, rdKey!);
        break;
      case 'premiumize':
        final proceed = await _showPremiumizeFairUseDialog(context);
        if (proceed && context.mounted) {
          await _bulkAddToPremiumize(context, items, premiumizeKey!);
        }
        break;
      case 'alldebrid':
        await _bulkAddToAllDebrid(context, items, allDebridKey!);
        break;
      case 'create_channel':
        await _createChannel(context, items, keyword);
        break;
    }
    return true;
  }

  // ── PikPak ────────────────────────────────────────────────────────────────
  static Future<void> _bulkAddToPikPak(
    BuildContext context,
    List<Torrent> torrentsToAdd,
  ) async {
    if (torrentsToAdd.isEmpty) return;

    final pikpak = PikPakApiService.instance;
    final controller = BulkAddProgressController.show(
      context,
      accent: const Color(0xFFFFAA00),
      titleIcon: Icons.cloud_upload,
      title: 'Adding to PikPak',
      torrents: torrentsToAdd,
      total: torrentsToAdd.length,
    );

    try {
      final parentFolderId = await StorageService.getPikPakRestrictedFolderId();
      String? subFolderId;
      try {
        subFolderId = await pikpak.findOrCreateSubfolder(
          folderName: 'debrify-torrents',
          parentFolderId: parentFolderId,
          getCachedId: StorageService.getPikPakTorrentsFolderId,
          setCachedId: StorageService.setPikPakTorrentsFolderId,
        );
      } catch (e) {
        if (e.toString().contains('RESTRICTED_FOLDER_DELETED')) {
          controller.close();
          if (context.mounted) await _handleRestrictedFolderDeleted(context);
          return;
        }
        subFolderId = parentFolderId;
      }

      // Process torrents in batches of 3 concurrent requests.
      const batchSize = 3;
      for (int i = 0;
          i < torrentsToAdd.length && !controller.cancelled;
          i += batchSize) {
        final batchEnd = (i + batchSize).clamp(0, torrentsToAdd.length);
        final batch = torrentsToAdd.sublist(i, batchEnd);

        await Future.wait(
          batch.map((torrent) async {
            if (controller.cancelled) return;
            try {
              controller.update(() {
                controller.status[torrent.infohash] = 'processing';
                controller.current++;
              });
              final magnet = await _pikpakMagnet(torrent);
              await pikpak.addOfflineDownload(magnet,
                  parentFolderId: subFolderId);
              controller.update(() {
                controller.status[torrent.infohash] = 'success';
                controller.success++;
              });
            } catch (_) {
              controller.update(() {
                controller.status[torrent.infohash] = 'error';
                controller.failure++;
              });
            }
          }),
        );

        if (i + batchSize < torrentsToAdd.length && !controller.cancelled) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      controller.close();

      if (!controller.cancelled && context.mounted) {
        final total = torrentsToAdd.length;
        final s = controller.success;
        final f = controller.failure;
        if (s > 0 && f == 0) {
          _snack(context, 'Successfully added $s/$total torrents to PikPak');
        } else if (s > 0 && f > 0) {
          _snack(context, 'Added $s/$total torrents. $f failed.',
              isError: true);
        } else {
          _snack(context, 'Failed to add torrents to PikPak', isError: true);
        }
      }
    } catch (e) {
      controller.close();
      if (!context.mounted) return;
      final folderExists =
          await PikPakApiService.instance.verifyRestrictedFolderExists();
      if (!folderExists) {
        if (context.mounted) await _handleRestrictedFolderDeleted(context);
        return;
      }
      if (context.mounted) {
        _snack(context, 'Bulk add failed: ${_cleanError(e)}', isError: true);
      }
    }
  }

  // ── TorBox ──────────────────────────────────────────────────────────────
  static Future<void> _bulkAddToTorbox(
    BuildContext context,
    List<Torrent> torrentsToAdd,
    String apiKey,
  ) async {
    if (torrentsToAdd.isEmpty) return;

    // Cache-check up front (before the dialog) so any failure here surfaces a
    // plain snackbar rather than leaving a dialog open.
    final List<Torrent> cachedTorrents;
    final List<Torrent> uncachedTorrents;
    try {
      final allHashes = torrentsToAdd.map((t) => t.infohash).toList();
      final cachedHashes = await TorboxService.checkCachedTorrents(
        apiKey: apiKey,
        infoHashes: allHashes,
      );
      cachedTorrents = torrentsToAdd
          .where((t) => cachedHashes.contains(t.infohash.toLowerCase()))
          .toList();
      uncachedTorrents = torrentsToAdd
          .where((t) => !cachedHashes.contains(t.infohash.toLowerCase()))
          .toList();
    } catch (e) {
      if (context.mounted) _snack(context, 'Bulk add failed: ${_cleanError(e)}', isError: true);
      return;
    }
    if (!context.mounted) return;

    final controller = BulkAddProgressController.show(
      context,
      accent: const Color(0xFF7C3AED),
      notCachedColor: const Color(0xFFEF4444),
      titleIcon: Icons.cloud_upload,
      title: 'Adding to TorBox',
      torrents: torrentsToAdd,
      total: cachedTorrents.length,
      showSkipped: true,
      skippedChipLabel: 'Skipped',
      notCachedSubtitle: 'Not cached',
      initialStatus: {
        for (final t in uncachedTorrents) t.infohash: 'not_cached',
      },
      initialSkipped: uncachedTorrents.length,
    );

    try {
      bool rateLimited = false;
      for (final torrent in cachedTorrents) {
        if (controller.cancelled || rateLimited) break;
        try {
          controller.update(() {
            controller.status[torrent.infohash] = 'processing';
            controller.current++;
          });
          final magnet = _acquisitionUrl(torrent);
          await TorboxService.createTorrent(
            apiKey: apiKey,
            magnet: magnet,
            addOnlyIfCached: true,
          );
          controller.update(() {
            controller.status[torrent.infohash] = 'success';
            controller.success++;
          });
        } catch (e) {
          final errLower = e.toString().toLowerCase();
          final isRateLimit = errLower.contains('rate limit') ||
              errLower.contains('too many requests');
          controller.update(() {
            controller.status[torrent.infohash] = 'error';
            controller.failure++;
          });
          if (isRateLimit) {
            rateLimited = true;
            controller.update(() {
              for (final t in cachedTorrents) {
                if (controller.status[t.infohash] == 'pending') {
                  controller.status[t.infohash] = 'error';
                  controller.failure++;
                  controller.current++;
                }
              }
            });
          }
        }
        if (!controller.cancelled && !rateLimited) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      controller.close();

      if (!controller.cancelled && context.mounted) {
        final parts = <String>[];
        if (controller.success > 0) parts.add('Added ${controller.success}');
        if (controller.skipped > 0) {
          parts.add('${controller.skipped} not cached');
        }
        if (controller.failure > 0) parts.add('${controller.failure} failed');
        if (rateLimited) parts.add('Rate limited (60/hr)');
        final message = parts.join(', ');
        final isError = controller.failure > 0 ||
            (controller.success == 0 && controller.skipped > 0);
        _snack(context, message.isEmpty ? 'No torrents to add' : message,
            isError: isError);
      }
    } catch (e) {
      controller.close();
      if (context.mounted) {
        _snack(context, 'Bulk add failed: ${_cleanError(e)}', isError: true);
      }
    }
  }

  // ── Real-Debrid ───────────────────────────────────────────────────────────
  static Future<void> _bulkAddToRealDebrid(
    BuildContext context,
    List<Torrent> torrentsToAdd,
    String apiKey,
  ) async {
    if (torrentsToAdd.isEmpty) return;

    final controller = BulkAddProgressController.show(
      context,
      accent: const Color(0xFFE50914),
      titleIcon: Icons.cloud_upload,
      title: 'Adding to Real-Debrid',
      torrents: torrentsToAdd,
      total: torrentsToAdd.length,
      showSkipped: true,
      skippedChipLabel: 'Not cached',
      notCachedSubtitle: 'Not cached — removed',
    );

    try {
      for (final torrent in torrentsToAdd) {
        if (controller.cancelled) break;
        try {
          controller.update(() {
            controller.status[torrent.infohash] = 'processing';
            controller.current++;
          });
          final magnetLink = _acquisitionUrl(torrent);
          await DebridService.addTorrentToDebrid(apiKey, magnetLink);
          controller.update(() {
            controller.status[torrent.infohash] = 'success';
            controller.success++;
          });
        } on TorrentNotCachedException catch (e) {
          try {
            await DebridService.deleteTorrent(e.apiKey, e.torrentId);
          } catch (_) {}
          controller.update(() {
            controller.status[torrent.infohash] = 'not_cached';
            controller.skipped++;
          });
        } catch (_) {
          controller.update(() {
            controller.status[torrent.infohash] = 'error';
            controller.failure++;
          });
        }
        if (!controller.cancelled) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      controller.close();

      if (!controller.cancelled && context.mounted) {
        _snack(context, _summary(controller),
            isError: _summaryIsError(controller));
      }
    } catch (e) {
      controller.close();
      if (context.mounted) {
        _snack(context, 'Bulk add failed: ${_cleanError(e)}', isError: true);
      }
    }
  }

  // ── Premiumize ──────────────────────────────────────────────────────────
  static Future<void> _bulkAddToPremiumize(
    BuildContext context,
    List<Torrent> torrentsToAdd,
    String apiKey,
  ) async {
    if (torrentsToAdd.isEmpty) return;

    // Cache-check up front (free) so only cached torrents are added.
    Set<String> cachedHashes = {};
    try {
      final hashes = torrentsToAdd
          .map((t) => t.infohash.trim().toLowerCase())
          .where((h) => h.isNotEmpty)
          .toList();
      final results = await PremiumizeService.checkCache(apiKey, hashes);
      cachedHashes = {
        for (var i = 0; i < hashes.length; i++)
          if (i < results.length && results[i]) hashes[i],
      };
    } catch (_) {}
    if (!context.mounted) return;

    bool isCached(Torrent t) =>
        cachedHashes.contains(t.infohash.trim().toLowerCase());

    final controller = BulkAddProgressController.show(
      context,
      accent: const Color(0xFFFB923C),
      titleIcon: Icons.workspace_premium_rounded,
      title: 'Adding to Premiumize',
      torrents: torrentsToAdd,
      total: torrentsToAdd.length,
      showSkipped: true,
      successChipLabel: 'Added',
      skippedChipLabel: 'Not cached',
      notCachedSubtitle: 'Not cached — skipped',
    );

    try {
      for (final torrent in torrentsToAdd) {
        if (controller.cancelled) break;

        if (!isCached(torrent)) {
          controller.update(() {
            controller.status[torrent.infohash] = 'not_cached';
            controller.skipped++;
            controller.current++;
          });
          continue;
        }

        try {
          controller.update(() {
            controller.status[torrent.infohash] = 'processing';
            controller.current++;
          });
          final magnetLink = _acquisitionUrl(torrent);
          await PremiumizeService.createTransfer(apiKey, magnetLink);
          controller.update(() {
            controller.status[torrent.infohash] = 'success';
            controller.success++;
          });
        } catch (_) {
          controller.update(() {
            controller.status[torrent.infohash] = 'error';
            controller.failure++;
          });
        }
        if (!controller.cancelled) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      controller.close();

      if (!controller.cancelled && context.mounted) {
        _snack(context, _summary(controller),
            isError: _summaryIsError(controller));
      }
    } catch (e) {
      controller.close();
      if (context.mounted) {
        _snack(context, 'Bulk add failed: ${_cleanError(e)}', isError: true);
      }
    }
  }

  // ── AllDebrid ─────────────────────────────────────────────────────────────
  static Future<void> _bulkAddToAllDebrid(
    BuildContext context,
    List<Torrent> torrentsToAdd,
    String apiKey,
  ) async {
    if (torrentsToAdd.isEmpty) return;

    final controller = BulkAddProgressController.show(
      context,
      accent: const Color(0xFF26A69A),
      titleIcon: Icons.all_inclusive_rounded,
      title: 'Adding to AllDebrid',
      torrents: torrentsToAdd,
      total: torrentsToAdd.length,
      showSkipped: true,
      skippedChipLabel: 'Not cached',
      notCachedSubtitle: 'Not cached — removed',
    );

    try {
      for (final torrent in torrentsToAdd) {
        if (controller.cancelled) break;
        try {
          controller.update(() {
            controller.status[torrent.infohash] = 'processing';
            controller.current++;
          });
          final magnetLink = _acquisitionUrl(torrent);
          await AllDebridService.addMagnetAndResolveFiles(apiKey, magnetLink);
          controller.update(() {
            controller.status[torrent.infohash] = 'success';
            controller.success++;
          });
        } on AllDebridTorrentNotReadyException catch (e) {
          try {
            await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
          } catch (_) {}
          controller.update(() {
            controller.status[torrent.infohash] = 'not_cached';
            controller.skipped++;
          });
        } catch (_) {
          controller.update(() {
            controller.status[torrent.infohash] = 'error';
            controller.failure++;
          });
        }
        if (!controller.cancelled) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      controller.close();

      if (!controller.cancelled && context.mounted) {
        _snack(context, _summary(controller),
            isError: _summaryIsError(controller));
      }
    } catch (e) {
      controller.close();
      if (context.mounted) {
        _snack(context, 'Bulk add failed: ${_cleanError(e)}', isError: true);
      }
    }
  }

  // ── Create channel ──────────────────────────────────────────────────────
  static Future<void> _createChannel(
    BuildContext context,
    List<Torrent> torrentsToAdd,
    String keyword,
  ) async {
    if (torrentsToAdd.isEmpty) return;
    try {
      final result = await DebrifyTvChannelAddService.addTorrentsToChannel(
        context,
        torrents: torrentsToAdd,
        searchKeyword: keyword,
      );
      if (result == null || !context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.successMessage),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );

      // Offer the shareable Debrify link when a brand-new channel was created
      // (matches Home's bulk create, which passes showShareDialogOnCreate).
      if (result.isNewChannel) {
        try {
          await showChannelCreatedShareDialog(context, result.channelId);
        } catch (e) {
          debugPrint('[BulkAdd] Share dialog error (non-fatal): $e');
        }
      }
    } on DebrifyTvChannelAddException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Failed to add torrents to channel: ${_cleanError(e)}',
            isError: true);
      }
    }
  }

  // ── Premiumize fair-use awareness ──────────────────────────────────────────
  static Future<bool> _showPremiumizeFairUseDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFB923C).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bolt_rounded,
                      color: Color(0xFFFB923C), size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Premiumize Fair Use',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Premiumize works on a fair-use points system — about '
                      '1000 points max, topping up ~30/day. Adding a cached '
                      'torrent and later streaming it both spend points '
                      '(roughly 1 point per GB).',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFB923C).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFFB923C).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color:
                                const Color(0xFFFB923C).withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Only cached torrents are added, but each one '
                              'still uses points. Select carefully to avoid '
                              'running out of your daily quota.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            actions: [
              TextButton(
                onPressed: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                autofocus: true,
                onPressed: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(dialogContext).pop(true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFB923C),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );
    return result ?? false;
  }

  // ── shared helpers ──────────────────────────────────────────────────────
  static String _summary(BulkAddProgressController c) {
    final parts = <String>[];
    if (c.success > 0) parts.add('Added ${c.success}');
    if (c.skipped > 0) parts.add('${c.skipped} not cached');
    if (c.failure > 0) parts.add('${c.failure} failed');
    final message = parts.join(', ');
    return message.isEmpty ? 'No torrents added' : message;
  }

  static bool _summaryIsError(BulkAddProgressController c) =>
      c.failure > 0 || (c.success == 0 && c.skipped > 0);

  /// Strip the noisy `Exception: ` prefix from a caught error for display,
  /// mirroring Home's per-provider `_formatXError` helpers.
  static String _cleanError(Object e) {
    var s = e.toString();
    if (s.startsWith('Exception: ')) s = s.substring('Exception: '.length);
    return s.trim();
  }

  /// Magnet/URL to hand a magnet-consuming provider (TorBox / RD / Premiumize /
  /// AllDebrid): prefer an existing magnet, then a `.torrent` URL, else
  /// synthesize a magnet from the infohash.
  static String _acquisitionUrl(Torrent torrent) {
    final magnetUrl = torrent.magnetUrl?.trim();
    if (magnetUrl != null && magnetUrl.toLowerCase().startsWith('magnet:')) {
      return magnetUrl;
    }
    final torrentUrl = torrent.torrentUrl?.trim();
    if (torrentUrl != null && torrentUrl.isNotEmpty) {
      return torrentUrl;
    }
    final nameParam = torrent.name.isNotEmpty
        ? '&dn=${Uri.encodeComponent(torrent.name)}'
        : '';
    return 'magnet:?xt=urn:btih:${torrent.infohash}$nameParam';
  }

  /// PikPak can't consume a raw `.torrent` URL, so convert it to a magnet first.
  static Future<String> _pikpakMagnet(Torrent torrent) async {
    final magnetUrl = torrent.magnetUrl?.trim();
    if (magnetUrl != null && magnetUrl.toLowerCase().startsWith('magnet:')) {
      return magnetUrl;
    }
    final torrentUrl = torrent.torrentUrl?.trim();
    if (torrentUrl != null && torrentUrl.isNotEmpty) {
      return TorrentFileService.magnetFromTorrentUrl(
        torrentUrl,
        fallbackName: torrent.name,
      );
    }
    final nameParam = torrent.name.isNotEmpty
        ? '&dn=${Uri.encodeComponent(torrent.name)}'
        : '';
    return 'magnet:?xt=urn:btih:${torrent.infohash}$nameParam';
  }

  static Future<void> _handleRestrictedFolderDeleted(
      BuildContext context) async {
    await PikPakApiService.instance.logout();
    if (!context.mounted) return;
    _snack(context, 'Restricted folder was deleted. You have been logged out.',
        isError: true);
  }

  static void _snack(BuildContext context, String message,
      {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFEF4444) : const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      );

  static Widget _optionTile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    bool enabled = true,
    bool autofocus = false,
    VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          autofocus: enabled && autofocus,
          borderRadius: BorderRadius.circular(12),
          splashColor: color.withValues(alpha: 0.1),
          highlightColor: color.withValues(alpha: 0.05),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: enabled
                    ? color.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.06),
              ),
              color: enabled
                  ? color.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.02),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: enabled ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (enabled)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.25),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
