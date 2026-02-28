import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/debrify_tv_cache.dart';
import '../../models/debrify_tv_channel_record.dart';
import '../../services/community/magnet_yaml_service.dart';
import '../../services/debrify_tv_cache_service.dart';
import '../../services/debrify_tv_repository.dart';
import '../../services/remote_control/remote_constants.dart';
import '../../services/remote_control/remote_control_state.dart';
import 'addon_install_dialog.dart';

/// Widget for exporting Debrify TV channels to a TV via remote control
class RemoteChannelExport extends StatefulWidget {
  final VoidCallback onBack;

  const RemoteChannelExport({
    super.key,
    required this.onBack,
  });

  @override
  State<RemoteChannelExport> createState() => _RemoteChannelExportState();
}

class _RemoteChannelExportState extends State<RemoteChannelExport> {
  bool _loading = true;
  bool _sending = false;
  List<DebrifyTvChannelRecord> _channels = [];
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() => _loading = true);
    try {
      final channels = await DebrifyTvRepository.instance.fetchAllChannels();
      setState(() {
        _channels = channels;
        _loading = false;
      });
    } catch (e) {
      debugPrint('RemoteChannelExport: Failed to load channels: $e');
      setState(() => _loading = false);
    }
  }

  bool get _allSelected =>
      _channels.isNotEmpty && _selectedIds.length == _channels.length;

  void _toggleSelectAll() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_channels.map((c) => c.channelId));
      }
    });
  }

  void _toggleChannel(String channelId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(channelId)) {
        _selectedIds.remove(channelId);
      } else {
        _selectedIds.add(channelId);
      }
    });
  }

  Future<void> _sendToTv() async {
    if (_selectedIds.isEmpty) return;

    // Show TV picker dialog
    final choice = await AddonInstallDialog.show(
      context,
      'channels',
      title: 'Select TV',
      subtitle: 'Send channels to',
      showThisDevice: false,
    );
    if (choice == null || choice.target != 'tv' || choice.device == null) return;

    setState(() => _sending = true);
    HapticFeedback.mediumImpact();

    final targetIp = choice.device!.ip;
    final state = RemoteControlState();
    int successCount = 0;
    int failCount = 0;
    final List<String> sentNames = [];

    try {
      final selectedChannels =
          _channels.where((c) => _selectedIds.contains(c.channelId)).toList();

      for (var i = 0; i < selectedChannels.length; i++) {
        final channel = selectedChannels[i];

        try {
          // Generate YAML from channel data + cached torrents
          final yamlContent = await _generateChannelYaml(channel);

          // Encode as debrify:// URI
          final debrifyUri = MagnetYamlService.encode(
            yamlContent: yamlContent,
            channelName: channel.name,
          );

          // Send to TV — use chunked transfer if payload is large
          final success = await _sendChannelToTv(
            state, targetIp, debrifyUri, channel.name,
          );

          if (success) {
            successCount++;
            sentNames.add(channel.name);
          } else {
            failCount++;
          }
        } catch (e) {
          debugPrint('RemoteChannelExport: Failed to send ${channel.name}: $e');
          failCount++;
        }

        // Small delay between channels to avoid UDP packet loss
        if (i < selectedChannels.length - 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      if (mounted) {
        if (failCount == 0 && successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sent $successCount channel${successCount != 1 ? 's' : ''} to TV',
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (successCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send channels'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sent $successCount channel${successCount != 1 ? 's' : ''}, $failCount failed',
              ),
              backgroundColor: const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('RemoteChannelExport: Failed to send channels: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  /// Send a single channel to TV, using chunked transfer if the payload is large.
  Future<bool> _sendChannelToTv(
    RemoteControlState state,
    String targetIp,
    String debrifyUri,
    String channelName,
  ) async {
    final payloadBytes = utf8.encode(debrifyUri).length;

    // Small enough for a single UDP packet — send directly
    if (payloadBytes <= kChunkDataMaxBytes) {
      return state.sendConfigCommandToDevice(
        ConfigCommand.debrifyChannel,
        targetIp,
        configData: debrifyUri,
      );
    }

    // Large payload — split into byte-safe base64 chunks
    final allBytes = utf8.encode(debrifyUri);
    final chunks = <String>[];
    for (var offset = 0; offset < allBytes.length; offset += kChunkRawBytesPerChunk) {
      final end = (offset + kChunkRawBytesPerChunk).clamp(0, allBytes.length);
      // Base64-encode each byte slice so the chunk is safe ASCII in JSON
      chunks.add(base64.encode(
        Uint8List.sublistView(allBytes, offset, end),
      ));
    }

    debugPrint(
      'RemoteChannelExport: Chunking $channelName '
      '($payloadBytes bytes, ${chunks.length} chunks)',
    );

    final transferId =
        '${DateTime.now().microsecondsSinceEpoch}_${channelName.hashCode.abs() % 1000000000}';

    // Send start packet with metadata
    final startData = jsonEncode({
      'transferId': transferId,
      'channelName': channelName,
      'totalChunks': chunks.length,
    });
    final startOk = await state.sendConfigCommandToDevice(
      ConfigCommand.debrifyChannelStart,
      targetIp,
      configData: startData,
    );
    if (!startOk) return false;

    // Send each chunk with a small delay
    for (var i = 0; i < chunks.length; i++) {
      await Future.delayed(const Duration(milliseconds: 50));

      final chunkData = jsonEncode({
        'transferId': transferId,
        'index': i,
        'data': chunks[i],
      });
      final chunkOk = await state.sendConfigCommandToDevice(
        ConfigCommand.debrifyChannelChunk,
        targetIp,
        configData: chunkData,
      );
      if (!chunkOk) return false;
    }

    return true;
  }

  Future<String> _generateChannelYaml(DebrifyTvChannelRecord channel) async {
    final buffer = StringBuffer();
    buffer.writeln('channel_name: "${_escapeYamlString(channel.name)}"');
    buffer.writeln('avoid_nsfw: ${channel.avoidNsfw}');
    buffer.writeln('');
    buffer.writeln('keywords:');

    final cacheEntry = await DebrifyTvCacheService.getEntry(channel.channelId);
    final cachedTorrents = cacheEntry?.torrents ?? <CachedTorrent>[];

    final keywordStats = cacheEntry?.keywordStats ?? <String, KeywordStat>{};

    for (final keyword in channel.keywords) {
      buffer.writeln('  "${_escapeYamlString(keyword)}":');

      final keywordLower = keyword.toLowerCase();

      // Include keyword stats if available
      final stat = keywordStats[keywordLower];
      if (stat != null) {
        buffer.writeln('    total_fetched: ${stat.totalFetched}');
        buffer.writeln('    last_searched_at: ${stat.lastSearchedAt}');
        buffer.writeln('    pages_pulled: ${stat.pagesPulled}');
        buffer.writeln('    pirate_bay_hits: ${stat.pirateBayHits}');
      }

      final seen = <String>{};
      final matchingTorrents = cachedTorrents
          .where((t) => t.keywords.contains(keywordLower))
          .where((t) {
        if (seen.contains(t.infohash)) return false;
        seen.add(t.infohash);
        return true;
      }).toList();

      if (matchingTorrents.isEmpty) {
        buffer.writeln('    torrents: []');
      } else {
        buffer.writeln('    torrents:');
        for (final torrent in matchingTorrents) {
          buffer.writeln('      - infohash: ${torrent.infohash}');
          buffer.writeln(
              '        name: "${_escapeYamlString(torrent.name)}"');
          buffer.writeln('        size_bytes: ${torrent.sizeBytes}');
          buffer.writeln('        created_unix: ${torrent.createdUnix}');
          buffer.writeln('        seeders: ${torrent.seeders}');
          buffer.writeln('        leechers: ${torrent.leechers}');
          buffer.writeln('        completed: ${torrent.completed}');
          buffer.writeln('        scraped_date: ${torrent.scrapedDate}');
          if (torrent.sources.isNotEmpty) {
            buffer.writeln(
                '        sources: [${torrent.sources.map((s) => '"$s"').join(', ')}]');
          }
        }
      }
    }

    return buffer.toString();
  }

  String _escapeYamlString(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back to menu button
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to menu'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.7),
          ),
        ),

        const SizedBox(height: 16),

        // Title
        const Text(
          'Debrify TV Channels',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Select channels to send to your TV',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 24),

        // Content
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
          )
        else if (_channels.isEmpty)
          _buildEmptyState()
        else ...[
          // Select all toggle
          _buildSelectAllTile(),

          const SizedBox(height: 8),

          // Channel list
          ...List.generate(_channels.length, (i) {
            final channel = _channels[i];
            final isSelected = _selectedIds.contains(channel.channelId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildChannelTile(channel, isSelected),
            );
          }),

          const SizedBox(height: 16),

          // Send button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _selectedIds.isNotEmpty && !_sending ? _sendToTv : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor:
                    const Color(0xFF6366F1).withValues(alpha: 0.3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _selectedIds.isEmpty
                              ? 'Send to TV'
                              : 'Send ${_selectedIds.length} channel${_selectedIds.length != 1 ? 's' : ''} to TV',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1E293B),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(
                Icons.live_tv_outlined,
                size: 36,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No channels found',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create channels in Debrify TV first',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectAllTile() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleSelectAll,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Text(
                'Select All',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Checkbox(
                value: _allSelected,
                onChanged: (_) => _toggleSelectAll(),
                activeColor: const Color(0xFF6366F1),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelTile(DebrifyTvChannelRecord channel, bool isSelected) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleChannel(channel.channelId),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              // Channel icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.live_tv,
                  color: Color(0xFF8B5CF6),
                  size: 20,
                ),
              ),

              const SizedBox(width: 12),

              // Channel info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${channel.keywords.length} keyword${channel.keywords.length != 1 ? 's' : ''}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Checkbox
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleChannel(channel.channelId),
                activeColor: const Color(0xFF6366F1),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
