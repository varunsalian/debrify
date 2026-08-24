import 'package:flutter/material.dart';
import 'spotlight_dialog.dart';

/// Import mode selection for channels
enum ImportChannelsMode { device, url, community }

/// Dialog for selecting import mode with DPAD support and awesome TV-optimized UI
class ImportChannelsDialog extends StatefulWidget {
  final bool isAndroidTv;

  const ImportChannelsDialog({super.key, required this.isAndroidTv});

  @override
  State<ImportChannelsDialog> createState() => ImportChannelsDialogState();
}

class ImportChannelsDialogState extends State<ImportChannelsDialog> {
  // Focus nodes for DPAD navigation
  final FocusNode _deviceFocusNode = FocusNode();
  final FocusNode _linkFocusNode = FocusNode();
  final FocusNode _communityFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.isAndroidTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _deviceFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _deviceFocusNode.dispose();
    _linkFocusNode.dispose();
    _communityFocusNode.dispose();
    _cancelFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DebrifyTvSpotlightDialog(
      eyebrow: 'Import · three ways in',
      title: 'Where is it coming from?',
      subtitle:
          'Bring in a saved channel file, paste a share link, or browse the community collection.',
      icon: Icons.cloud_download_rounded,
      maxWidth: 760,
      actions: [
        DebrifyTvDialogButton(
          focusNode: _cancelFocusNode,
          label: 'Cancel',
          icon: Icons.close_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final threeColumns = constraints.maxWidth >= 680;
          final cards = [
            DebrifyTvDialogOptionCard(
              autofocus: !widget.isAndroidTv,
              focusNode: _deviceFocusNode,
              icon: Icons.folder_open_rounded,
              title: 'From storage',
              subtitle: 'A .zip, .yaml, .txt, or .debrify file on this device.',
              tag: constraints.maxWidth < 320 ? null : 'File picker',
              vertical: threeColumns,
              onPressed: () =>
                  Navigator.of(context).pop(ImportChannelsMode.device),
            ),
            DebrifyTvDialogOptionCard(
              focusNode: _linkFocusNode,
              icon: Icons.link_rounded,
              title: 'From a link',
              subtitle: 'A debrify:// share link or an http(s) channel URL.',
              tag: constraints.maxWidth < 320 ? null : 'Paste or type',
              vertical: threeColumns,
              onPressed: () =>
                  Navigator.of(context).pop(ImportChannelsMode.url),
            ),
            DebrifyTvDialogOptionCard(
              focusNode: _communityFocusNode,
              icon: Icons.people_alt_rounded,
              title: 'From the community',
              subtitle:
                  'Browse ready-made channels and import several at once.',
              tag: constraints.maxWidth < 320 ? null : 'Browse',
              vertical: threeColumns,
              onPressed: () =>
                  Navigator.of(context).pop(ImportChannelsMode.community),
            ),
          ];
          if (!threeColumns) {
            return Column(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  cards[i],
                  if (i != cards.length - 1) const SizedBox(height: 10),
                ],
              ],
            );
          }
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards)
                SizedBox(width: (constraints.maxWidth - 24) / 3, child: card),
            ],
          );
        },
      ),
    );
  }
}
