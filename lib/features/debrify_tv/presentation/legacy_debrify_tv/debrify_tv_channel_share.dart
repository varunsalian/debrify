import 'dart:async';

import 'package:debrify/features/debrify_tv/application/debrify_tv_byte_format.dart';
import 'package:debrify/features/debrify_tv/presentation/debrify_tv_meta_pill.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/services/community/magnet_yaml_service.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebrifyTvChannelShare {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelShare(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> handleShareChannelAsMagnet(DebrifyTvChannel channel) async {
    if (!_deps.mounted()) {
      return;
    }

    _deps.setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Generating channel link…';
    });

    try {
      // Generate YAML for sharing (with cached torrents from DB)
      final yamlContent = await _sections.share._generateChannelYaml(channel);

      // Encode as magnet link
      final magnetLink = MagnetYamlService.encode(
        yamlContent: yamlContent,
        channelName: channel.name,
      );

      // Estimate sizes for display
      final estimatedSize = MagnetYamlService.estimateMagnetLinkSize(
        yamlContent,
      );
      final compressionRatio = MagnetYamlService.getCompressionRatio(
        yamlContent,
      );

      if (!_deps.mounted()) {
        return;
      }

      // Show magnet link dialog
      await showDialog(
        context: _deps.context(),
        builder: (dialogContext) {
          final app = AppThemeScope.of(dialogContext);
          final tv = app.debrifyTv;
          return DebrifyTvSpotlightDialog(
            eyebrow:
                'Share channel · ${channel.channelNumber.toString().padLeft(2, '0')}',
            title: channel.name,
            subtitle:
                'Anyone on Debrify can paste this link to import the channel and its saved pool.',
            icon: Icons.share_rounded,
            maxWidth: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: tv.dialogDeep.withValues(alpha: .72),
                    borderRadius: app.shape.br(16),
                    border: Border.all(color: tv.hairline),
                  ),
                  child: SelectableText(
                    magnetLink,
                    style: TextStyle(
                      color: tv.textDim,
                      fontSize: 10,
                      height: 1.5,
                      fontFamily: 'JetBrainsMono',
                    ),
                    maxLines: 6,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DebrifyTvMetaPill(
                      label: 'Link size',
                      value: formatDebrifyTvBytes(estimatedSize),
                    ),
                    DebrifyTvMetaPill(
                      label: 'Compression',
                      value: '${compressionRatio.toStringAsFixed(1)}×',
                    ),
                    DebrifyTvMetaPill(
                      label: 'Keywords',
                      value: '${channel.keywords.length}',
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              DebrifyTvDialogButton(
                label: 'Close',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              DebrifyTvDialogButton(
                autofocus: true,
                label: 'Copy link',
                icon: Icons.copy_rounded,
                tone: DebrifyTvDialogButtonTone.primary,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: magnetLink));
                  _sections.feedback.showSnack(
                    'Channel link copied!',
                    color: Colors.green,
                  );
                  Navigator.of(dialogContext).pop();
                },
              ),
            ],
          );
        },
      );
    } catch (error) {
      _sections.feedback.showSnack(
        'Failed to generate channel link: ${_sections.formats.formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
      }
    }
  }

  Future<String> _generateChannelYaml(DebrifyTvChannel channel) async {
    // Generate YAML with channel config and torrent data from cache
    final buffer = StringBuffer();
    buffer.writeln('channel_name: "${channel.name}"');
    buffer.writeln('avoid_nsfw: ${channel.avoidNsfw}');
    buffer.writeln('');
    buffer.writeln('keywords:');

    // Get cached torrents from database (not in-memory cache)
    final cacheEntry = await DebrifyTvCacheService.getEntry(channel.id);
    final cachedTorrents = cacheEntry?.torrents ?? <CachedTorrent>[];
    for (final keyword in channel.keywords) {
      buffer.writeln('  $keyword:');

      // Find all torrents that match this keyword (case-insensitive)
      final keywordLower = keyword.toLowerCase();
      final matchingTorrents = cachedTorrents
          .where((t) => t.keywords.contains(keywordLower))
          .toList();

      // Dedupe by infohash
      final seen = <String>{};
      final uniqueTorrents = matchingTorrents.where((t) {
        if (seen.contains(t.infohash)) return false;
        seen.add(t.infohash);
        return true;
      }).toList();

      if (uniqueTorrents.isEmpty) {
        buffer.writeln('    torrents: []');
      } else {
        buffer.writeln('    torrents:');
        for (final torrent in uniqueTorrents) {
          // Output full torrent object for proper import
          buffer.writeln('      - infohash: ${torrent.infohash}');
          buffer.writeln(
            '        name: "${_sections.share._escapeYamlString(torrent.name)}"',
          );
          buffer.writeln('        size_bytes: ${torrent.sizeBytes}');
          buffer.writeln('        created_unix: ${torrent.createdUnix}');
          buffer.writeln('        seeders: ${torrent.seeders}');
          buffer.writeln('        leechers: ${torrent.leechers}');
          buffer.writeln('        completed: ${torrent.completed}');
          buffer.writeln('        scraped_date: ${torrent.scrapedDate}');
          if (torrent.sources.isNotEmpty) {
            buffer.writeln(
              '        sources: [${torrent.sources.map((s) => '"$s"').join(', ')}]',
            );
          }
        }
      }
    }

    return buffer.toString();
  }

  String _escapeYamlString(String value) {
    // Escape special characters for YAML string
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
