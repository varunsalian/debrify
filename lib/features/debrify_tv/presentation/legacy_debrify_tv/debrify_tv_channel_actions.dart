import 'dart:async';

import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:flutter/material.dart';

class DebrifyTvChannelActions {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelActions(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> handleAddChannel() async {
    await _sections.settings.syncProviderAvailability();
    final channel = await _sections.editor.openChannelDialog();
    if (channel != null) {
      await _sections.save.createOrUpdateChannel(channel, isEdit: false);
    }
  }

  Future<void> handleEditChannel(DebrifyTvChannel channel) async {
    await _sections.settings.syncProviderAvailability();

    // Store current channel's NSFW setting before dialog
    final nsfwBeforeEdit = channel.avoidNsfw;

    final keywords = await _sections.library.getChannelKeywords(channel.id);
    final hydrated = channel.copyWith(keywords: keywords);
    final updated = await _sections.editor.openChannelDialog(
      existing: hydrated,
    );
    if (updated != null) {
      // Check if channel's NSFW setting changed
      final nsfwAfterEdit = updated.avoidNsfw;
      final nsfwChanged = nsfwBeforeEdit != nsfwAfterEdit;

      if (nsfwChanged) {
        // NSFW setting changed for this channel - rebuild cache with new filter
        debugPrint(
          'DebrifyTV: Channel NSFW filter changed. Forcing full cache rebuild...',
        );

        // Clear existing cache to force full rebuild
        _owners.library.channelCache.remove(updated.id);

        // Rebuild cache with new NSFW filter setting (isEdit: false forces full rebuild)
        await _sections.save.createOrUpdateChannel(updated, isEdit: false);

        _sections.feedback.showSnack(
          'Channel cache rebuilt with updated NSFW filter.',
          color: Colors.green,
        );
      } else {
        // No NSFW change, just normal update
        await _sections.save.createOrUpdateChannel(updated, isEdit: true);
      }
    }
  }

  Future<bool> _showDebrifyTvConfirmation({
    required String eyebrow,
    required String title,
    required String message,
    required String confirmLabel,
    IconData icon = Icons.warning_amber_rounded,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: _deps.context(),
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) Navigator.of(dialogContext).pop(false);
        },
        child: DebrifyTvSpotlightDialog(
          eyebrow: eyebrow,
          title: title,
          subtitle: message,
          icon: icon,
          maxWidth: 580,
          child: const SizedBox.shrink(),
          actions: [
            DebrifyTvDialogButton(
              autofocus: true,
              label: 'Cancel',
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            DebrifyTvDialogButton(
              label: confirmLabel,
              icon: danger ? Icons.delete_outline_rounded : Icons.check_rounded,
              tone: danger
                  ? DebrifyTvDialogButtonTone.danger
                  : DebrifyTvDialogButtonTone.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> handleDeleteChannel(DebrifyTvChannel channel) async {
    // Set busy immediately to block any other interactions
    _deps.setState(() {
      _owners.session.isBusy = true;
    });

    final confirmed = await _sections.actions._showDebrifyTvConfirmation(
      eyebrow: 'Channel library · destructive action',
      title: 'Delete ${channel.name}?',
      message:
          'This removes the channel, its saved keywords, and its cached title pool. This cannot be undone.',
      confirmLabel: 'Delete channel',
      icon: Icons.delete_outline_rounded,
      danger: true,
    );

    // Wait for TWO frames to ensure UI has fully updated and touch events are processed
    if (_deps.mounted()) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (confirmed == true && _deps.mounted()) {
      await _sections.library.deleteChannel(channel.id);
      _sections.feedback.showSnack('Channel deleted', color: Colors.orange);
    }

    // Release busy state
    if (_deps.mounted()) {
      _deps.setState(() {
        _owners.session.isBusy = false;
      });
    }
  }

  Future<void> handleDeleteAllChannels() async {
    if (_owners.library.channels.isEmpty) {
      _sections.feedback.showSnack(
        'No channels to delete.',
        color: Colors.orange,
      );
      return;
    }

    if (!_deps.mounted()) {
      return;
    }

    // Set busy immediately to block any other interactions
    _deps.setState(() {
      _owners.session.isBusy = true;
    });

    final confirmed = await _sections.actions._showDebrifyTvConfirmation(
      eyebrow: 'Channel library · ${_owners.library.channels.length} channels',
      title: 'Delete every channel?',
      message:
          'This removes all ${_owners.library.channels.length} channels and every cached title pool. This cannot be undone.',
      confirmLabel: 'Delete all',
      icon: Icons.delete_sweep_outlined,
      danger: true,
    );

    // Wait for TWO frames to ensure UI has fully updated and touch events are processed
    if (_deps.mounted()) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (confirmed != true || !_deps.mounted()) {
      // Release busy state if cancelled
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    _deps.setState(() {
      _owners.session.isBusy = true;
    });

    try {
      await DebrifyTvRepository.instance.clearAll();
      await DebrifyTvCacheService.clearAll(
        origin: WebDavSyncMutationOrigin.maintenance,
      );
      _deps.setState(() {
        _owners.library.channels = const <DebrifyTvChannel>[];
        _owners.library.channelCache.clear();
      });
      _sections.feedback.showSnack(
        'All channels deleted.',
        color: Colors.orange,
      );
    } catch (error) {
      _sections.feedback.showSnack(
        'Failed to delete channels: ${_sections.formats.formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
        });
      }
    }
  }
}
