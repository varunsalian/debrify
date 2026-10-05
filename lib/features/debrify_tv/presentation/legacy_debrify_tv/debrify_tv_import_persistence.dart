import 'dart:async';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv/import_results.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/debrify_tv_zip_importer.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

class DebrifyTvImportPersistence {
  final DebrifyTvDependencies _deps;
  DebrifyTvImportPersistence(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<ZipImportPersistenceResult> persistImportedZipChannels(
    List<DebrifyTvZipImportedChannel> channels,
  ) async {
    if (channels.isEmpty) {
      return const ZipImportPersistenceResult(successes: [], failures: []);
    }

    final successes = <ZipImportSuccess>[];
    final failures = <ZipImportSaveFailure>[];

    final List<DebrifyTvChannel> appendedChannels = [];
    final Map<String, DebrifyTvChannelCacheEntry> appendedCache = {};

    final Set<String> usedNames = _owners.library.channels
        .map((channel) => channel.name.toLowerCase())
        .toSet();

    for (final channel in channels) {
      if (channel.normalizedKeywords.length >
          DebrifyTvConstants.maxChannelKeywords) {
        failures.add(
          ZipImportSaveFailure(
            sourceName: channel.sourceName,
            channelName: channel.channelName,
            reason:
                'Channel has ${channel.normalizedKeywords.length} keywords; maximum supported is ${DebrifyTvConstants.maxChannelKeywords}.',
          ),
        );
        continue;
      }

      final uniqueName = _sections.library.resolveUniqueChannelName(
        channel.channelName,
        usedNames,
      );
      final channelId = DateTime.now().microsecondsSinceEpoch.toString();
      final now = DateTime.now();

      final record = DebrifyTvChannelRecord(
        channelId: channelId,
        name: uniqueName,
        keywords: channel.displayKeywords,
        avoidNsfw: channel.avoidNsfw,
        channelNumber: 0,
        createdAt: now,
        updatedAt: now,
      );

      final entry = DebrifyTvChannelCacheEntry(
        version: 1,
        channelId: channelId,
        normalizedKeywords: channel.normalizedKeywords,
        fetchedAt: now.millisecondsSinceEpoch,
        status: DebrifyTvCacheStatus.ready,
        errorMessage: null,
        torrents: channel.torrents,
        keywordStats: channel.keywordStats,
      );

      try {
        await DebrifyTvRepository.instance.upsertChannel(record);
        await DebrifyTvCacheService.saveEntry(entry);

        appendedChannels.add(
          DebrifyTvChannel(
            id: channelId,
            name: uniqueName,
            keywords: const <String>[],
            avoidNsfw: channel.avoidNsfw,
            channelNumber: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
        appendedCache[channelId] = entry;

        successes.add(
          ZipImportSuccess(
            sourceName: channel.sourceName,
            channelName: uniqueName,
            keywordCount: channel.normalizedKeywords.length,
            torrentCount: channel.torrentCount,
          ),
        );

        usedNames.add(uniqueName.toLowerCase());
      } catch (error) {
        failures.add(
          ZipImportSaveFailure(
            sourceName: channel.sourceName,
            channelName: uniqueName,
            reason: _sections.formats.formatImportError(error),
          ),
        );
      }
    }

    if (appendedChannels.isNotEmpty && _deps.mounted()) {
      _deps.setState(() {
        _owners.library.channels = [
          ..._owners.library.channels,
          ...appendedChannels,
        ];
        _owners.library.channelCache.addAll(appendedCache);
      });
      await _sections.library.loadChannels();
    }

    return ZipImportPersistenceResult(successes: successes, failures: failures);
  }

  Future<void> showZipImportSummary(
    DebrifyTvZipImportResult parsed,
    ZipImportPersistenceResult persisted,
  ) async {
    if (!_deps.mounted()) {
      return;
    }

    final bool hasSuccess = persisted.successes.isNotEmpty;
    final List<ZipImportFailureDisplay> failureRows = [
      ...parsed.failures.map(
        (failure) => ZipImportFailureDisplay(
          sourceName: failure.entryName,
          reason: failure.reason,
        ),
      ),
      ...persisted.failures.map(
        (failure) => ZipImportFailureDisplay(
          sourceName: failure.sourceName.isEmpty
              ? failure.channelName
              : failure.sourceName,
          reason: failure.reason,
        ),
      ),
    ];

    if (!hasSuccess && failureRows.isEmpty) {
      _sections.feedback.showSnack(
        'No channels found in the selected zip.',
        color: Colors.orange,
      );
      return;
    }

    final String dialogTitle = hasSuccess
        ? 'Zip import complete'
        : 'Zip import failed';

    await showDialog<void>(
      context: _deps.context(),
      builder: (dialogContext) {
        final tv = AppThemeScope.of(dialogContext).debrifyTv;
        return DebrifyTvSpotlightDialog(
          eyebrow: 'Import · summary',
          title: dialogTitle,
          subtitle: hasSuccess
              ? 'Your imported channels are ready to tune.'
              : 'Nothing was changed. Review the issues below and try again.',
          icon: hasSuccess
              ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded,
          maxWidth: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasSuccess) ...[
                Text(
                  'Imported ${persisted.successes.length} channel${persisted.successes.length == 1 ? '' : 's'}.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...persisted.successes.map(
                  (success) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.check_circle, size: 20),
                    title: Text(success.channelName),
                    subtitle: Text(
                      '${success.keywordCount} keyword${success.keywordCount == 1 ? '' : 's'} • ${success.torrentCount} torrent${success.torrentCount == 1 ? '' : 's'}',
                      style: TextStyle(color: tv.textDim),
                    ),
                  ),
                ),
              ] else ...[
                const Text('No channels were imported.'),
              ],
              if (failureRows.isNotEmpty) ...[
                if (hasSuccess) const SizedBox(height: 12),
                Text(
                  'Issues detected:',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...failureRows.map(
                  (failure) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(
                      Icons.error_outline,
                      color: Colors.orange,
                      size: 20,
                    ),
                    title: Text(failure.sourceName),
                    subtitle: Text(failure.reason),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            DebrifyTvDialogButton(
              autofocus: true,
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );

    if (hasSuccess) {
      final String names = persisted.successes
          .map((success) => '"${success.channelName}"')
          .join(', ');
      _sections.feedback.showSnack(
        'Imported ${persisted.successes.length} channel${persisted.successes.length == 1 ? '' : 's'}: $names',
        color: Colors.green,
      );
    } else if (failureRows.isNotEmpty) {
      _sections.feedback.showSnack(
        'Zip import failed: ${failureRows.first.reason}',
        color: Colors.red,
      );
    }
  }
}
