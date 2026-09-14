import 'package:flutter/material.dart';
import '../../../services/webdav_sync/webdav_sync_device_names.dart';
import '../../../widgets/tv_text_field.dart';

class SyncDeviceNameDialog extends StatefulWidget {
  const SyncDeviceNameDialog({super.key, required this.initialName});
  final String initialName;
  @override
  State<SyncDeviceNameDialog> createState() => _SyncDeviceNameDialogState();
}

class _SyncDeviceNameDialogState extends State<SyncDeviceNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _error;
  void _submit() {
    try {
      final name = WebDavSyncDeviceNames.validate(_controller.text);
      Navigator.of(context).pop(name);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Rename this device'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a name such as “Living room TV”. It will appear on your connected devices. To rename another device, open this setting on that device.',
          ),
          const SizedBox(height: 16),
          TvTextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            keyboardSubmitLabel: 'Save',
            decoration: InputDecoration(
              labelText: 'Device name',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}

/// Actions have their own line so names and status remain readable on phones.
class SyncDeviceTile extends StatelessWidget {
  const SyncDeviceTile({
    super.key,
    required this.name,
    required this.status,
    this.onRename,
    this.onRemove,
  });
  final String name;
  final String status;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(status, style: Theme.of(context).textTheme.bodySmall),
        if (onRename != null || onRemove != null)
          Wrap(
            spacing: 8,
            children: [
              if (onRename != null)
                TextButton(onPressed: onRename, child: const Text('Rename')),
              if (onRemove != null)
                TextButton(onPressed: onRemove, child: const Text('Remove')),
            ],
          ),
      ],
    ),
  );
}
