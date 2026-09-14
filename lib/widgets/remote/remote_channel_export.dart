import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/debrify_tv_channel_record.dart';
import '../../services/community/channel_yaml_builder.dart';
import '../../services/community/magnet_yaml_service.dart';
import '../../services/debrify_tv_repository.dart';
import '../../services/remote_control/remote_chunked_send.dart';
import '../../services/remote_control/remote_constants.dart';
import '../../services/remote_control/remote_channel_file.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../models/profiles/profile_policy.dart';
import 'remote_pairing_dialog.dart';

/// Widget for exporting Debrify TV channels to a TV via remote control
class RemoteChannelExport extends StatefulWidget {
  final VoidCallback onBack;
  final bool headless;
  final VoidCallback? onInventoryChanged;

  const RemoteChannelExport({
    super.key,
    required this.onBack,
    this.headless = false,
    this.onInventoryChanged,
  });

  @override
  RemoteChannelExportState createState() => RemoteChannelExportState();
}

class RemoteChannelExportState extends State<RemoteChannelExport> {
  bool get loading => _loading;
  String? inventoryError;
  List<DebrifyTvChannelRecord> get channels => List.unmodifiable(_channels);
  Future<void> reload() => _loadChannels();
  final Set<String> _succeeded = {};
  Future<Set<String>> sendSelection(Set<String> ids) async {
    if (_sending || _loading) return {};
    final old = Set<String>.of(_selectedIds);
    _selectedIds
      ..clear()
      ..addAll(ids);
    _succeeded.clear();
    try {
      await _sendToTvNow();
      return Set.of(_succeeded);
    } finally {
      _selectedIds
        ..clear()
        ..addAll(old);
    }
  }

  bool _loading = true;
  bool _sending = false;
  String? _transferError;
  List<DebrifyTvChannelRecord> _channels = [];
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    inventoryError = null;
    setState(() => _loading = true);
    try {
      final channels = await DebrifyTvRepository.instance.fetchAllChannels();
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _loading = false;
      });
    } catch (_) {
      inventoryError = 'Could not load channels';
      debugPrint('RemoteChannelExport: channel load failed');
      if (mounted) setState(() => _loading = false);
    } finally {
      if (mounted) widget.onInventoryChanged?.call();
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

  Future<void> _sendToTv() =>
      RemoteControlState().transferActivity.run(() => _sendToTvNow());

  Future<void> _sendToTvNow() async {
    if (_selectedIds.isEmpty) return;

    final connectedDevice = RemoteControlState().connectedDevice;
    if (connectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No TV connected'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Same gate as config transfers: channels can carry cached debrid links.
    final session = await ensureAuthorizedSession(
      context,
      RemoteControlState(),
      connectedDevice,
    );
    if (session == null || !mounted) return;

    _transferError = null;
    setState(() => _sending = true);
    HapticFeedback.mediumImpact();

    final targetIp = connectedDevice.ip;
    final state = RemoteControlState();
    final supportsApplicationResult =
        session.peerProtocolVersion >= kRemoteTransferResultProtocolVersion;
    int successCount = 0;
    int failCount = 0;

    try {
      final selectedChannels = _channels
          .where((c) => _selectedIds.contains(c.channelId))
          .toList();

      for (var i = 0; i < selectedChannels.length; i++) {
        final selectedChannel = selectedChannels[i];

        try {
          final authorization = await ProfileAsyncAuthorization.capture(
            ProfileFeature.remoteTransfer,
          );
          Future<bool> sendCurrentChannel() async {
            // The list on screen is only a selection hint. Re-read from the
            // authorized profile immediately before building cached torrent
            // data so a profile switch cannot send the previous profile's
            // channel under the new profile's transport capability.
            if (session.peerProtocolVersion >=
                kReliableTransferProtocolVersion) {
              final staging = await Directory.systemTemp.createTemp(
                'debrify-channel-send-',
              );
              try {
                final file = File('${staging.path}/channel.gz');
                await RemoteChannelFile.export(selectedChannel.channelId, file);
                return await _sendChannelToTv(
                  state,
                  targetIp,
                  'debrify://file',
                  selectedChannel.name,
                  waitForApplication: true,
                  file: file,
                );
              } finally {
                await staging.delete(recursive: true);
              }
            }
            final currentChannels = await DebrifyTvRepository.instance
                .fetchAllChannels();
            DebrifyTvChannelRecord? currentChannel;
            for (final candidate in currentChannels) {
              if (candidate.channelId == selectedChannel.channelId) {
                currentChannel = candidate;
                break;
              }
            }
            if (currentChannel == null) return false;
            final yamlContent = await ChannelYamlBuilder.build(currentChannel);
            final debrifyUri = MagnetYamlService.encode(
              yamlContent: yamlContent,
              channelName: currentChannel.name,
            );
            return _sendChannelToTv(
              state,
              targetIp,
              debrifyUri,
              currentChannel.name,
              waitForApplication: supportsApplicationResult,
            );
          }

          final success = authorization == null
              ? await sendCurrentChannel()
              : await authorization.runIfCurrentAsOutbound(sendCurrentChannel);

          if (success) {
            _succeeded.add(selectedChannel.channelId);
            successCount++;
          } else {
            failCount++;
          }
        } catch (_) {
          debugPrint('RemoteChannelExport: channel send failed');
          failCount++;
        }

        // Small delay between channels to avoid UDP packet loss
        if (session.peerProtocolVersion < kReliableTransferProtocolVersion &&
            i < selectedChannels.length - 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      if (mounted && !widget.headless) {
        if (failCount == 0 && successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                supportsApplicationResult
                    ? 'Imported $successCount channel${successCount != 1 ? 's' : ''} on TV'
                    : 'Delivered $successCount channel${successCount != 1 ? 's' : ''} — confirm on TV',
              ),
              backgroundColor: supportsApplicationResult
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (successCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_transferError ?? 'Failed to send channels'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${supportsApplicationResult ? 'Imported' : 'Delivered'} '
                '$successCount channel${successCount != 1 ? 's' : ''}, '
                '$failCount failed',
              ),
              backgroundColor: const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {
      debugPrint('RemoteChannelExport: channel batch send failed');
      if (mounted && !widget.headless) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send channels'),
            backgroundColor: Color(0xFFEF4444),
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

  /// Send a single channel to TV. Delegates to the shared chunked-send
  /// protocol (this file used to carry its own duplicate copy) — which also
  /// seals the payload when an encrypted session exists.
  Future<bool> _sendChannelToTv(
    RemoteControlState state,
    String targetIp,
    String debrifyUri,
    String channelName, {
    required bool waitForApplication,
    File? file,
  }) async {
    final requestId = createRemoteTransferRequestId();
    final resultCompleter = Completer<bool>();
    StreamSubscription<({String requestId, bool ok, String message})>?
    resultSubscription;
    if (waitForApplication) {
      resultSubscription = state.remoteTransferResults.stream.listen((result) {
        if (result.requestId == requestId && !resultCompleter.isCompleted) {
          if (!result.ok) _transferError = result.message;
          resultCompleter.complete(result.ok);
        }
      });
    }
    try {
      final delivered = file != null
          ? await state.sendProfileArchive(
              targetIp,
              file,
              requestId,
              channel: true,
            )
          : await sendConfigPayloadToDevice(
              state,
              ConfigCommand.debrifyChannel,
              targetIp,
              waitForApplication
                  ? remoteChannelTransferBody(
                      requestId: requestId,
                      uri: debrifyUri,
                    )
                  : debrifyUri,
              label: channelName,
              resultRequestId: waitForApplication ? requestId : null,
            );
      if (!delivered || !waitForApplication) return delivered;
      return await resultCompleter.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );
    } finally {
      await resultSubscription?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.headless) return const SizedBox.shrink();
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
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
              onPressed: _selectedIds.isNotEmpty && !_sending
                  ? _sendToTv
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor: const Color(
                  0xFF6366F1,
                ).withValues(alpha: 0.3),
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
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
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
