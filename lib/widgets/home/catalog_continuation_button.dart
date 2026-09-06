import 'package:flutter/material.dart';

/// Keeps the remote's focus on a pending action while suppressing repeat presses.
class CatalogContinuationButton extends StatelessWidget {
  const CatalogContinuationButton({
    super.key,
    required this.focusNode,
    required this.busy,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  final FocusNode focusNode;
  final bool busy;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    focusNode: focusNode,
    autofocus: autofocus,
    onPressed: () {
      if (!busy) onPressed();
    },
    icon: const Icon(Icons.arrow_forward_rounded),
    label: Text(busy ? '$label · Loading…' : label),
  );
}
