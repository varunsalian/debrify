import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/local_source_document.dart';

Future<List<LocalSourceDocument>> readLocalFolderWithProgress(
  BuildContext context, {
  required Future<List<LocalSourceDocument>> Function() scan,
  bool Function()? canContinue,
}) async {
  bool active() => canContinue?.call() ?? true;
  if (canContinue != null && (!context.mounted || !active())) return const [];
  final navigator = Navigator.of(context);
  final progress = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Reading local folder…')),
          ],
        ),
      ),
    ),
  );
  unawaited(navigator.push(progress));
  try {
    final videos = await scan();
    return active() ? videos : const [];
  } finally {
    if (navigator.mounted && progress.isActive) {
      navigator.removeRoute(progress);
    }
  }
}
