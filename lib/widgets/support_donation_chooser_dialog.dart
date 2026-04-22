import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/support_remote_config_service.dart';

Future<void> showSupportDonationChooserDialog(
  BuildContext context, {
  required SupportDonationConfig donation,
  String title = 'Support Debrify',
}) async {
  if (!donation.hasProviders) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _SupportDonationChooserDialog(donation: donation, title: title),
  );
}

class _SupportDonationChooserDialog extends StatefulWidget {
  final SupportDonationConfig donation;
  final String title;

  const _SupportDonationChooserDialog({
    required this.donation,
    required this.title,
  });

  @override
  State<_SupportDonationChooserDialog> createState() =>
      _SupportDonationChooserDialogState();
}

class _SupportDonationChooserDialogState
    extends State<_SupportDonationChooserDialog> {
  late final List<FocusNode> _providerFocusNodes;
  final FocusNode _closeFocusNode = FocusNode(debugLabel: 'supportClose');

  @override
  void initState() {
    super.initState();
    _providerFocusNodes = List<FocusNode>.generate(
      widget.donation.providers.length,
      (index) => FocusNode(debugLabel: 'supportProvider$index'),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _providerFocusNodes.isEmpty) return;
      _providerFocusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _providerFocusNodes) {
      node.dispose();
    }
    _closeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusTraversalGroup(
      child: FocusScope(
        autofocus: true,
        child: AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Text(widget.title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: widget.donation.providers.asMap().entries.map((
                  entry,
                ) {
                  final index = entry.key;
                  final provider = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        focusNode: _providerFocusNodes[index],
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final navigator = Navigator.of(context);
                          final uri = Uri.tryParse(provider.url);
                          if (uri != null) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                          if (mounted) {
                            navigator.pop();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                child: Text(
                                  provider.name.characters.first.toUpperCase(),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(provider.name),
                                    if (provider.subtitle.isNotEmpty)
                                      Text(
                                        provider.subtitle,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: Colors.white.withValues(
                                                alpha: 0.65,
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
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              focusNode: _closeFocusNode,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
