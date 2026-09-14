import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native button traversal plus explicit TV remote Select activation.
class ClearPinnedSourcesButton extends StatefulWidget {
  const ClearPinnedSourcesButton({super.key, required this.onClear});
  final Future<void> Function() onClear;

  @override
  State<ClearPinnedSourcesButton> createState() =>
      _ClearPinnedSourcesButtonState();
}

class _ClearPinnedSourcesButtonState extends State<ClearPinnedSourcesButton> {
  bool _busy = false;

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onClear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not clear pinned sources. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    },
    child: OutlinedButton.icon(
      onPressed: _busy ? null : _clear,
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
      label: Text(_busy ? 'Clearing…' : 'Clear all'),
    ),
  );
}
