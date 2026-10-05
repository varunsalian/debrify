import 'dart:async';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:flutter/material.dart';

class DebrifyTvChannelSave {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelSave(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> createOrUpdateChannel(
    DebrifyTvChannel channel, {
    required bool isEdit,
  }) async {
    final normalizedKeywords = _sections.library.normalizedKeywords(
      channel.keywords,
    );
    if (normalizedKeywords.isEmpty) {
      _sections.feedback.showSnack(
        'Add at least one keyword before saving.',
        color: Colors.orange,
      );
      return;
    }

    debugPrint(
      'DebrifyTV: ${isEdit ? 'Updating' : 'Creating'} channel "${channel.name}" with ${normalizedKeywords.length} keyword(s): ${normalizedKeywords.join(', ')}',
    );

    final int estimatedSeconds = _sections.engines.estimatedWarmDurationSeconds(
      normalizedKeywords.length,
      totalKeywordUniverse: normalizedKeywords.length,
    );
    bool progressShown = false;
    void ensureProgressDialog({int? countdownSeconds}) {
      if (!progressShown) {
        _sections.feedback.showChannelCreationDialog(
          channel.name,
          countdownSeconds: countdownSeconds ?? estimatedSeconds,
        );
        progressShown = true;
      }
    }

    try {
      final baseline = isEdit
          ? await _sections.library.ensureCacheEntry(channel.id)
          : null;
      if (normalizedKeywords.length > DebrifyTvConstants.maxChannelKeywords) {
        _sections.feedback.showSnack(
          'Channels support up to ${DebrifyTvConstants.maxChannelKeywords} keywords. Remove some and try again.',
          color: Colors.orange,
        );
        debugPrint(
          'DebrifyTV: Aborting save for "${channel.name}" – keyword cap exceeded.',
        );
        return;
      }

      DebrifyTvChannelCacheEntry? workingEntry = baseline;
      final currentKeywordSet = normalizedKeywords.toSet();
      Set<String> addedKeywords = const <String>{};
      Set<String> removedKeywords = const <String>{};

      if (isEdit && baseline != null) {
        final previousKeywords = baseline.normalizedKeywords.toSet();
        removedKeywords = previousKeywords.difference(currentKeywordSet);
        addedKeywords = currentKeywordSet.difference(previousKeywords);

        debugPrint(
          'DebrifyTV: Detected keyword changes for "${channel.name}" – added: ${addedKeywords.join(', ')}, removed: ${removedKeywords.join(', ')}',
        );

        if (removedKeywords.isNotEmpty) {
          ensureProgressDialog();
          final filteredTorrents = baseline.torrents.where((cached) {
            final torrentKeywords = cached.keywords.toSet();
            return torrentKeywords.intersection(removedKeywords).isEmpty;
          }).toList();

          final filteredStats = Map<String, KeywordStat>.from(
            baseline.keywordStats,
          )..removeWhere((key, _) => removedKeywords.contains(key));

          final newStatus = filteredTorrents.isNotEmpty
              ? DebrifyTvCacheStatus.ready
              : DebrifyTvCacheStatus.failed;

          workingEntry = baseline.copyWith(
            normalizedKeywords: normalizedKeywords,
            torrents: filteredTorrents,
            keywordStats: filteredStats,
            status: newStatus,
            clearErrorMessage: filteredTorrents.isNotEmpty,
          );

          debugPrint(
            'DebrifyTV: Pruned ${baseline.torrents.length - filteredTorrents.length} torrent(s) after removing keywords. Remaining: ${filteredTorrents.length}.',
          );
        } else if (baseline.normalizedKeywords.length !=
            normalizedKeywords.length) {
          workingEntry = baseline.copyWith(
            normalizedKeywords: normalizedKeywords,
          );
        }

        if (addedKeywords.isNotEmpty) {
          ensureProgressDialog(
            countdownSeconds: _sections.engines.estimatedWarmDurationSeconds(
              addedKeywords.length,
              totalKeywordUniverse: normalizedKeywords.length,
            ),
          );
          debugPrint(
            'DebrifyTV: Warming new keywords for "${channel.name}": ${addedKeywords.join(', ')}',
          );
          workingEntry = await _sections.warmup.computeChannelCacheEntry(
            channel,
            normalizedKeywords,
            baseline: workingEntry,
            keywordsToSearch: addedKeywords,
          );
          debugPrint(
            'DebrifyTV: After warming new keywords, cache has ${workingEntry.torrents.length} torrent(s).',
          );
        }

        if (addedKeywords.isEmpty && removedKeywords.isEmpty) {
          debugPrint(
            'DebrifyTV: No keyword changes for "${channel.name}" – reusing existing cache.',
          );
          workingEntry = baseline.copyWith(
            normalizedKeywords: normalizedKeywords,
          );
        }
      } else {
        ensureProgressDialog();
        debugPrint('DebrifyTV: Running full warm-up for "${channel.name}"');
        workingEntry = await _sections.warmup.computeChannelCacheEntry(
          channel,
          normalizedKeywords,
        );
        debugPrint(
          'DebrifyTV: Initial warm-up complete for "${channel.name}" with ${workingEntry.torrents.length} torrent(s).',
        );
      }

      final entry = workingEntry;
      if (entry == null) {
        _sections.feedback.showSnack(
          'Failed to build channel cache. Please try again.',
          color: Colors.red,
        );
        return;
      }

      if (!_deps.mounted()) {
        return;
      }

      if (!entry.isReady ||
          entry.torrents.length <
              DebrifyTvConstants.minimumTorrentsForChannel) {
        final message = entry.isReady
            ? 'Need at least ${DebrifyTvConstants.minimumTorrentsForChannel} torrents to save this channel. Try different keywords.'
            : (entry.errorMessage ??
                  'Unable to find torrents for these keywords. Try again later.');

        debugPrint(
          'DebrifyTV: Cache validation failed for "${channel.name}" – ready=${entry.isReady}, torrents=${entry.torrents.length}.',
        );

        if (isEdit && baseline != null) {
          _deps.setState(() {
            _owners.library.channelCache[channel.id] = baseline;
            _owners.stage.spotlightStats.remove(channel.id);
          });
          _sections.stage.refreshSpotlightStatsIfFocused(channel.id);
          await DebrifyTvCacheService.saveEntry(
            baseline,
            origin: WebDavSyncMutationOrigin.rollback,
          );
        } else {
          _deps.setState(() {
            _owners.library.channelCache.remove(channel.id);
            _owners.stage.spotlightStats.remove(channel.id);
          });
          await DebrifyTvCacheService.removeEntry(
            channel.id,
            origin: WebDavSyncMutationOrigin.rollback,
          );
        }

        _sections.feedback.showSnack(message, color: Colors.orange);
        return;
      }

      final updatedChannel = channel.copyWith(updatedAt: DateTime.now());

      final displayChannel = updatedChannel.copyWith(
        keywords: const <String>[],
      );

      _deps.setState(() {
        final index = _owners.library.channels.indexWhere(
          (c) => c.id == displayChannel.id,
        );
        if (index == -1) {
          _owners.library.channels = <DebrifyTvChannel>[
            ..._owners.library.channels,
            displayChannel,
          ];
        } else {
          final next = List<DebrifyTvChannel>.from(_owners.library.channels);
          next[index] = displayChannel;
          _owners.library.channels = next;
        }
        _owners.library.channelCache[displayChannel.id] = entry;
        _owners.stage.spotlightStats.remove(displayChannel.id);
      });

      await DebrifyTvRepository.instance.upsertChannel(
        updatedChannel.toRecord(),
      );
      await DebrifyTvCacheService.saveEntry(entry);
      await _sections.library.loadChannels();
      // Memo removal alone would leave the stage on its placeholder: only a
      // focus MOVE computes, and editing from the stage doesn't move focus.
      _sections.stage.refreshSpotlightStatsIfFocused(displayChannel.id);

      final successMsg = isEdit
          ? 'Channel "${updatedChannel.name}" updated'
          : 'Channel "${updatedChannel.name}" saved';
      _sections.feedback.showSnack(successMsg, color: Colors.green);
      debugPrint(
        'DebrifyTV: $successMsg (torrents cached: ${entry.torrents.length})',
      );
    } catch (e) {
      debugPrint('DebrifyTV: Channel creation failed for ${channel.name}: $e');
      _sections.feedback.showSnack(
        'Failed to build channel cache. Please try again.',
        color: Colors.red,
      );
    } finally {
      if (progressShown) {
        _sections.feedback.closeProgressDialog();
      }
    }
  }
}
