import 'dart:async';

import 'package:flutter/material.dart';

/// Confirmation and loading UI for a caller-owned reset operation.
/// Owns the loader route, but neither persistence nor the operation's lifetime.
Future<void> runProgressResetDialog({
  required BuildContext context,
  required WidgetBuilder confirmation,
  required bool Function() isCurrent,
  required Future<List<String>> Function() reset,
  required String Function(List<String>) message,
}) async {
  if (!context.mounted || !isCurrent()) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: confirmation,
  );
  if (confirmed != true || !context.mounted || !isCurrent()) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  if (!navigator.mounted) return;
  final loader = DialogRoute<void>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierColor:
        DialogTheme.of(context).barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        Colors.black54,
    barrierDismissible: false,
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Clearing watch progress…')),
          ],
        ),
      ),
    ),
  );
  unawaited(navigator.push<void>(loader));
  late final List<String> failures;
  try {
    failures = await reset();
  } finally {
    if (navigator.mounted && loader.isActive) {
      if (loader.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(loader);
      }
    }
  }
  if (!context.mounted || !isCurrent()) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message(failures))));
}
