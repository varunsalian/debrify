import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/keyword_sources_controller.dart';
import '../models/keyword_source.dart';
import '../models/search_session.dart';
import 'source_dialog_shell.dart';
import 'source_toggle_row.dart';

class KeywordSourcesDialog extends ConsumerStatefulWidget {
  final SearchSession session;
  const KeywordSourcesDialog({super.key, required this.session});

  @override
  ConsumerState<KeywordSourcesDialog> createState() =>
      _KeywordSourcesDialogState();
}

class _KeywordSourcesDialogState extends ConsumerState<KeywordSourcesDialog> {
  late final ProviderSubscription<List<KeywordSource>?> _subscription;
  KeywordSourcesController get _controller =>
      ref.read(keywordSourcesProvider(widget.session).notifier);

  @override
  void initState() {
    super.initState();
    _subscription = ref.listenManual(keywordSourcesProvider(widget.session), (
      _,
      _,
    ) {
      if (mounted) setState(() {});
    });
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources = _subscription.read();
    final Widget body;
    if (sources == null) {
      body = sourceDialogLoading(context);
    } else if (sources.isEmpty) {
      body = sourceDialogMessage(context, 'No search sources installed.');
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        shrinkWrap: true,
        itemCount: sources.length,
        itemBuilder: (context, i) {
          final source = sources[i];
          return SourceToggleRow(
            label: source.label,
            enabled: source.enabled,
            autofocus: i == 0,
            onToggle: (value) =>
                unawaited(_controller.setEnabled(source.id, value)),
          );
        },
      );
    }
    return SourceDialogShell(
      title: 'Search sources',
      subtitle: 'Choose which trackers keyword search queries.',
      onEnableAll: sources == null || sources.isEmpty
          ? null
          : () => unawaited(_controller.setAll(true)),
      onDisableAll: sources == null || sources.isEmpty
          ? null
          : () => unawaited(_controller.setAll(false)),
      body: body,
    );
  }
}
