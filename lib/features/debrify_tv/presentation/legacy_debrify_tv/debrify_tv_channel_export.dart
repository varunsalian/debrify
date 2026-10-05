import 'dart:async';

import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/debrify_tv/dialogs/export_channels_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/screens/settings/profile_backup_flows.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_channel_archive_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/debrify_tv_zip_importer.dart';
import 'package:debrify/services/profiles/profile_async_authorization.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DebrifyTvChannelExport {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelExport(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<T> _runChannelExportProgress<T>(
    Future<T> Function(void Function(String) setStage) run,
  ) async {
    if (!_deps.mounted()) {
      throw StateError('Channel export screen is no longer available');
    }
    final stage = ValueNotifier<String>('Reading selected channel pools…');
    final done = ValueNotifier<bool>(false);
    final dialog = showDialog<void>(
      context: _deps.context(),
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (_) => ChannelExportProgressDialog(stage: stage, done: done),
    );
    try {
      return await run((value) => stage.value = value);
    } finally {
      done.value = true;
      await dialog;
      stage.dispose();
      done.dispose();
    }
  }

  Future<void> _showChannelExportUnavailableOnAppleTv() async {
    if (!_deps.mounted()) return;
    await showDialog<void>(
      context: _deps.context(),
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(dialogContext).pop();
        },
        child: DebrifyTvSpotlightDialog(
          eyebrow: 'Channel export · Apple TV',
          title: 'Export from another device',
          subtitle:
              'Apple TV does not expose a location where Debrify can save a '
              'portable ZIP. Export the channels from Debrify on a phone or '
              'computer, or send them through Remote.',
          icon: Icons.tv_rounded,
          maxWidth: 580,
          actions: <Widget>[
            DebrifyTvDialogButton(
              autofocus: true,
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }

  Future<void> handleExportChannels() async {
    if (_owners.session.isBusy || !_deps.mounted()) return;
    if (PlatformUtil.isTvOS) {
      await _sections.channelExport._showChannelExportUnavailableOnAppleTv();
      return;
    }

    _deps.setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Loading channels for export…';
    });

    try {
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.debrifyTv,
      );
      Future<T> runCaptured<T>(Future<T> Function() body) =>
          capability == null ? body() : capability.runIfCurrent(body);

      final channels = await runCaptured(
        DebrifyTvRepository.instance.fetchAllChannels,
      );
      final health = await runCaptured(DebrifyTvCacheService.loadRailHealth);
      if (!_deps.mounted()) return;
      if (channels.isEmpty) {
        _sections.feedback.showSnack(
          'There are no channels to export.',
          color: Colors.orange,
        );
        return;
      }

      final selectedIds = await showDialog<Set<String>>(
        context: _deps.context(),
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .72),
        builder: (_) => ExportChannelsDialog(
          channels: channels,
          savedHashCounts: <String, int>{
            for (final entry in health.entries) entry.key: entry.value.pooled,
          },
        ),
      );
      if (!_deps.mounted() || selectedIds == null || selectedIds.isEmpty)
        return;

      _deps.setState(
        () => _owners.session.status = 'Preparing channel archive…',
      );
      late List<DebrifyTvChannelArchiveSource> sources;
      final bytes = await _sections.channelExport
          ._runChannelExportProgress<Uint8List>((setStage) async {
            sources = await runCaptured(() async {
              // Re-read after the selection dialog: a channel can be edited or
              // removed while an overlay is open, and the archive must reflect
              // the rows that actually exist at export time.
              final current = await DebrifyTvRepository.instance
                  .fetchAllChannels();
              final selected = current
                  .where((channel) => selectedIds.contains(channel.channelId))
                  .toList(growable: false);
              final result = <DebrifyTvChannelArchiveSource>[];
              for (var index = 0; index < selected.length; index++) {
                final channel = selected[index];
                setStage(
                  'Reading channel ${index + 1} of ${selected.length}: '
                  '${channel.name}',
                );
                result.add(
                  DebrifyTvChannelArchiveSource(
                    channel: channel,
                    cacheEntry:
                        await DebrifyTvCacheService.getEntryForPortableExport(
                          channel.channelId,
                        ),
                  ),
                );
              }
              return result;
            });
            if (sources.isEmpty) {
              throw StateError('The selected channels are no longer available');
            }
            setStage('Compressing ${sources.length} channels into one ZIP…');
            return DebrifyTvChannelArchiveService.buildZip(sources);
          });
      if (!_deps.mounted()) return;
      if (bytes.length > DebrifyTvZipImporter.maxPortableFileBytes) {
        _sections.feedback.showSnack(
          'The ZIP is over 100 MB. Export fewer channels at a time.',
          color: Colors.orange,
        );
        return;
      }

      if (capability != null) {
        await capability.runIfCurrent(() async {});
      }
      if (!_deps.mounted()) return;
      final now = DateTime.now();
      final stamp = <int>[
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      ].map((part) => part.toString().padLeft(2, '0')).join();
      final savedPath = await ProfileBackupFlows(_deps.context())
          .saveBackupFile(
            fileName: 'debrify-tv-channels-$stamp.zip',
            bytes: bytes,
            mimeType: 'application/zip',
            artifactLabel: 'channel archive',
          );
      if (!_deps.mounted() || savedPath == null) return;
      final hashes = sources.fold<int>(
        0,
        (sum, source) => sum + source.savedHashCount,
      );
      _sections.feedback.showSnack(
        'Exported ${sources.length} channel${sources.length == 1 ? '' : 's'} '
        'with $hashes saved hash${hashes == 1 ? '' : 'es'}.',
        color: Colors.green,
      );
    } catch (error) {
      debugPrint(
        'DebrifyTV: channel archive export failed (${error.runtimeType})',
      );
      if (_deps.mounted()) {
        _sections.feedback.showSnack(
          'Failed to export channels.',
          color: Colors.red,
        );
      }
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
      }
    }
  }
}
