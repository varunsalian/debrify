import 'package:flutter/material.dart';

import '../../../screens/settings/widgets/settings_widgets.dart';
import '../models/ledger_brand.dart';
import '../models/ledger_tracking.dart';

/// Trakt/Simkl accounts linked to the Ledger account on its website, with
/// "Import again". Linking itself happens on the website.
class LedgerLinkedTrackers extends StatelessWidget {
  const LedgerLinkedTrackers({
    super.key,
    required this.trackers,
    required this.busy,
    required this.onImport,
  });

  /// Null when the list could not be loaded.
  final List<LedgerLinkedTracker>? trackers;
  final bool busy;
  final void Function(String provider, String name) onImport;

  @override
  Widget build(BuildContext context) {
    final linked = trackers?.where((tracker) => tracker.connected).toList();
    return SettingsSection(
      title: 'Import history',
      blurb:
          'Bring your Trakt or Simkl history into $kLedgerDisplayName. Link '
          'those accounts on the $kLedgerDisplayName website, then import '
          'again here whenever you like. Plays already imported are not '
          'duplicated.',
      children: [
        if (linked == null)
          const ListTile(
            leading: Icon(Icons.cloud_off_rounded),
            title: Text("Couldn't load linked accounts"),
          )
        else if (linked.isEmpty)
          const ListTile(
            leading: Icon(Icons.link_off_rounded),
            title: Text('No linked accounts'),
            subtitle: Text(
              'Link Trakt or Simkl on the website to import from them.',
            ),
          )
        else
          for (final tracker in linked)
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(tracker.displayName),
              subtitle: Text(_subtitle(tracker)),
              trailing: const Icon(Icons.download_rounded),
              // A busy no-op keeps the row focusable on TV.
              onTap: busy
                  ? () {}
                  : () => onImport(tracker.provider, tracker.displayName),
            ),
      ],
    );
  }

  static String _subtitle(LedgerLinkedTracker tracker) {
    final who = tracker.remoteUsername == null
        ? 'Linked'
        : 'Linked as ${tracker.remoteUsername}';
    final state = switch (tracker.lastImportState) {
      'IMPORT_STATE_RUNNING' || 'IMPORT_STATE_QUEUED' => 'importing now',
      'IMPORT_STATE_FAILED' => 'last import failed',
      'IMPORT_STATE_SUCCEEDED' => 'imported',
      _ => null,
    };
    return state == null
        ? '$who · Select to import again'
        : '$who · $state · Select to import again';
  }
}
