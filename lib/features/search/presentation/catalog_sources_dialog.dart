import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/catalog_sources_controller.dart';
import '../models/catalog_sources_state.dart';
import '../models/search_session.dart';
import 'source_dialog_shell.dart';
import 'source_toggle_row.dart';

class CatalogSourcesDialog extends ConsumerStatefulWidget {
  final SearchSession session;
  const CatalogSourcesDialog({super.key, required this.session});

  @override
  ConsumerState<CatalogSourcesDialog> createState() =>
      _CatalogSourcesDialogState();
}

class _CatalogSourcesDialogState extends ConsumerState<CatalogSourcesDialog> {
  late final ProviderSubscription<CatalogSourcesState> _subscription;
  CatalogSourcesController get _controller =>
      ref.read(catalogSourcesProvider(widget.session).notifier);

  @override
  void initState() {
    super.initState();
    _subscription = ref.listenManual(catalogSourcesProvider(widget.session), (
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
    final state = _subscription.read();
    final Widget body;
    if (state.loading) {
      body = sourceDialogLoading(context);
    } else if (state.addons.isEmpty) {
      body = sourceDialogMessage(
        context,
        'No search-capable addons installed. Add a catalog addon that '
        'supports search (e.g. Cinemeta) from Addons.',
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        shrinkWrap: true,
        itemCount: state.addons.length,
        itemBuilder: (context, i) {
          final addon = state.addons[i];
          final searchable = addon.catalogs
              .where((c) => c.supportsSearch)
              .length;
          return SourceToggleRow(
            label: addon.displayName,
            subtitle: searchable > 1 ? '$searchable searchable catalogs' : null,
            enabled: !state.disabled.contains(addon.id),
            autofocus: i == 0,
            onToggle: (enabled) =>
                unawaited(_controller.setEnabled(addon.id, enabled)),
          );
        },
      );
    }
    return SourceDialogShell(
      title: 'Search sources',
      subtitle: 'Choose which addons catalog search queries.',
      onEnableAll: state.addons.isEmpty
          ? null
          : () => unawaited(_controller.enableAll()),
      onDisableAll: state.addons.isEmpty
          ? null
          : () => unawaited(_controller.disableAll()),
      body: body,
    );
  }
}
