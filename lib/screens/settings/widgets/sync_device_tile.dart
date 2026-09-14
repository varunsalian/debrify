import 'dart:async';
import '../../../services/webdav_sync/webdav_sync_graph_tier.dart';
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
    this.isThisDevice = false,
    this.isRegistered = true,
  });
  final String name;
  final String status;
  final bool isThisDevice;
  final bool isRegistered;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isThisDevice
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
            : Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              isThisDevice
                  ? Icons.devices_rounded
                  : Icons.devices_other_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            Text(
              isThisDevice
                  ? 'THIS DEVICE'
                  : isRegistered
                  ? 'OTHER DEVICE'
                  : 'SIGNED OUT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          name,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(status, style: Theme.of(context).textTheme.bodySmall),
        if (!isRegistered) ...[
          const SizedBox(height: 6),
          Text(
            'Saved data retained. Remove to free a device slot.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (onRename != null || onRemove != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                if (onRename != null)
                  TextButton.icon(
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Rename'),
                  ),
                if (onRemove != null)
                  TextButton.icon(
                    onPressed: onRemove,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Remove'),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// A relative label describes sync activity, not whether the app is online.
String syncDeviceLastSynced(int timestampMs, DateTime now) {
  if (timestampMs <= 0) return 'No sync time available';
  final elapsed = now.millisecondsSinceEpoch - timestampMs;
  if (elapsed < 60000) return 'Last synced just now';
  final minutes = elapsed ~/ 60000;
  if (minutes < 60) {
    return 'Last synced $minutes ${minutes == 1 ? "minute" : "minutes"} ago';
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return 'Last synced $hours ${hours == 1 ? "hour" : "hours"} ago';
  }
  final days = hours ~/ 24;
  return 'Last synced $days ${days == 1 ? "day" : "days"} ago';
}

class SyncDevicesDialog extends StatefulWidget {
  const SyncDevicesDialog({
    super.key,
    required this.devices,
    required this.canRename,
    this.clock = DateTime.now,
  });
  final List<WebDavSyncDeviceSummary> devices;
  final bool canRename;
  final DateTime Function() clock;
  @override
  State<SyncDevicesDialog> createState() => _SyncDevicesDialogState();
}

class _SyncDevicesDialogState extends State<SyncDevicesDialog> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    return AlertDialog(
      title: const Text('Connected devices'),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Devices sharing your sync account.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (widget.devices.isEmpty)
              const Text('No devices to show yet. Run Sync now and try again.'),
            for (final device in widget.devices) ...[
              SyncDeviceTile(
                name:
                    device.displayName ??
                    (device.isThisDevice
                        ? 'This device'
                        : 'Device · ${device.deviceId.length > 12 ? device.deviceId.substring(0, 12) : device.deviceId}'),
                status: syncDeviceLastSynced(device.lastSeenMs, now),
                isThisDevice: device.isThisDevice,
                isRegistered: device.isRegistered,
                onRename: device.isThisDevice && widget.canRename
                    ? () => Navigator.of(context).pop('@rename')
                    : null,
                onRemove: device.isThisDevice
                    ? null
                    : () => Navigator.of(context).pop(device.deviceId),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
