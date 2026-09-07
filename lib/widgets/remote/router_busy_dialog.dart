import 'package:flutter/material.dart';

/// Busy dialog for long-running remote imports: undismissable while work
/// runs, closed through its OWN context when `done` fires — the initiating
/// State may be anywhere, and an orphaned `canPop: false` modal on the root
/// navigator would wedge the app.
class RouterBusyDialog extends StatefulWidget {
  const RouterBusyDialog({
    super.key,
    required this.message,
    required this.done,
  });

  final String message;
  final ValueNotifier<bool> done;

  @override
  State<RouterBusyDialog> createState() => _RouterBusyDialogState();
}

class _RouterBusyDialogState extends State<RouterBusyDialog> {
  @override
  void initState() {
    super.initState();
    widget.done.addListener(_maybeClose);
    if (widget.done.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeClose());
    }
  }

  @override
  void dispose() {
    widget.done.removeListener(_maybeClose);
    super.dispose();
  }

  void _maybeClose() {
    if (widget.done.value && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(widget.message)),
          ],
        ),
      ),
    );
  }
}
