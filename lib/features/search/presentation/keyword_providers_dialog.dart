import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/keyword_results_controller.dart';
import '../models/search_session.dart';
import 'keyword_source_label.dart';

class KeywordProvidersDialog extends ConsumerWidget {
  const KeywordProvidersDialog({
    super.key,
    required this.session,
    required this.onChanged,
  });
  final SearchSession session;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(keywordResultsProvider(session));
    final controller = ref.read(keywordResultsProvider(session).notifier);
    final scheme = Theme.of(context).colorScheme;
    void apply(VoidCallback action) {
      action();
      onChanged();
    }

    Widget group(
      String title,
      Map<String, int> counts,
      Set<String> selected,
      bool direct,
    ) {
      if (counts.isEmpty) return const SizedBox.shrink();
      final entries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final allOn = selected.length == counts.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => apply(() {
                    controller.toggleProviderGroup(direct);
                  }),
                  child: Text(allOn ? 'None' : 'All'),
                ),
              ],
            ),
          ),
          ...entries.map(
            (e) => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: selected.contains(e.key),
              title: Text(
                keywordSourceLabel(state.pending ?? state.all, e.key),
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
              secondary: Text(
                '${e.value}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              onChanged: (_) => apply(() {
                controller.toggleProvider(direct, e.key);
              }),
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Filter by source'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              group(
                'Direct',
                state.providers.directCounts,
                state.providers.selectedDirect,
                true,
              ),
              group(
                'Torrent',
                state.providers.torrentCounts,
                state.providers.selectedTorrent,
                false,
              ),
            ],
          ),
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
