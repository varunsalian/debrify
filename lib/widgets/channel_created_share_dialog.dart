import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/debrify_tv_channel_record.dart';
import '../services/community/channel_yaml_builder.dart';
import '../services/community/magnet_yaml_service.dart';
import '../services/debrify_tv_repository.dart';

/// After a new Debrify TV channel is created, build a shareable Debrify link,
/// copy it to the clipboard, and show it in a dialog. Ported verbatim from
/// Home's `_showChannelCreatedDialog` so the Search tab's bulk "Create Channel"
/// offers the same share flow.
Future<void> showChannelCreatedShareDialog(
  BuildContext context,
  String channelId,
) async {
  final repo = DebrifyTvRepository.instance;
  final channels = await repo.fetchAllChannels();
  if (!context.mounted) return;

  DebrifyTvChannelRecord? found;
  for (final ch in channels) {
    if (ch.channelId == channelId) {
      found = ch;
      break;
    }
  }
  if (found == null) return;
  final channel = found;

  String? debrifyLink;
  String? encodeError;
  try {
    final yamlContent = await ChannelYamlBuilder.build(channel);
    debrifyLink = MagnetYamlService.encode(
      yamlContent: yamlContent,
      channelName: channel.name,
    );
    try {
      await Clipboard.setData(ClipboardData(text: debrifyLink));
    } catch (_) {
      // Clipboard write is best-effort.
    }
  } catch (e) {
    encodeError = e.toString();
  }

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF14B8A6).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF14B8A6),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Channel "${channel.name}" created',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              debrifyLink != null
                  ? 'A shareable Debrify link was copied to your clipboard.'
                  : 'Failed to generate shareable link${encodeError != null ? ': $encodeError' : ''}.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            if (debrifyLink != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                debrifyLink,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
