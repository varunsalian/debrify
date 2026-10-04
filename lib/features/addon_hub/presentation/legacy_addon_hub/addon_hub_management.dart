import 'package:debrify/features/addon_hub/presentation/addon_hub_dialog.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef AddonHubManagementDeps = ({
  BuildContext Function() context,
  AddonHubInstalledState installedState,
  bool Function() mounted,
});

class AddonHubManagement {
  AddonHubManagement(this._deps);
  final AddonHubManagementDeps _deps;

  Future<void> updateAll() async {
    final messenger = ScaffoldMessenger.of(_deps.context());
    try {
      final result = await _deps.installedState.stremio.refreshAllAddons();
      if (!_deps.mounted()) return;
      final parts = <String>[];
      if (result.updated > 0) parts.add('${result.updated} updated');
      if (result.unchanged > 0) parts.add('${result.unchanged} up to date');
      if (result.failed > 0) parts.add('${result.failed} failed');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty ? 'No addons to update' : parts.join('  ·  '),
          ),
          backgroundColor: result.failed > 0 ? Colors.orange.shade800 : null,
        ),
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> deleteAll() async {
    final count = _deps.installedState.installed.length;
    if (count == 0) return;
    final app = AppThemeScope.of(_deps.context());
    final messenger = ScaffoldMessenger.of(_deps.context());
    final int sharedCount;
    try {
      sharedCount = await _deps.installedState.stremio.sharedAddonCount();
    } catch (e) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to check sharing: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_deps.mounted()) return;
    final hasSharedAddons = sharedCount > 0;
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (ctx) => AddonHubHubDialog(
        title: 'Delete all addons?',
        content: Text(
          hasSharedAddons
              ? '$sharedCount addon${sharedCount == 1 ? ' is' : 's are'} '
                    'shared with other profiles. Deleting all addons will '
                    'also remove those addons from every shared profile.'
              : 'This removes all $count installed Stremio '
                    'addon${count == 1 ? '' : 's'} from Debrify.',
          style: TextStyle(color: app.fade(app.core.tx, 0.75)),
        ),
        actions: [
          AddonHubHubDialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          AddonHubHubDialogButton(
            label: 'Delete all',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !_deps.mounted()) return;
    try {
      await _deps.installedState.stremio.clearAllAddons(
        revokeSharedProfiles: hasSharedAddons,
      );
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted $count addon${count == 1 ? '' : 's'}')),
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // storageKey, NOT manifestUrl: under profiles an addon is a connection
  // resource and its key is that resource's id, so the URL matches nothing
  // and the toggle silently did nothing at all.
  Future<void> toggleAddon(StremioAddon a) =>
      _deps.installedState.stremio.setAddonEnabled(a.storageKey, !a.enabled);

  Future<void> renameAddon(StremioAddon a) async {
    var value = a.userAlias ?? a.name;
    final alias = await showDialog<String>(
      context: _deps.context(),
      builder: (ctx) => AddonHubHubDialog(
        title: 'Rename addon',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              autofocus: true,
              initialValue: value,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'For example, AIOStreams Main',
              ),
              onChanged: (next) => value = next,
              onFieldSubmitted: (next) => Navigator.of(ctx).pop(next.trim()),
            ),
            const SizedBox(height: 8),
            Text(
              'Manifest name: ${a.name}',
              style: TextStyle(
                color: AppThemeScope.of(
                  ctx,
                ).fade(AppThemeScope.of(ctx).core.tx, 0.58),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          AddonHubHubDialogButton(
            label: 'Use manifest name',
            onTap: () => Navigator.of(ctx).pop(''),
          ),
          AddonHubHubDialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(ctx).pop(),
          ),
          AddonHubHubDialogButton(
            label: 'Save',
            primary: true,
            onTap: () => Navigator.of(ctx).pop(value.trim()),
          ),
        ],
      ),
    );
    if (alias == null || !_deps.mounted()) return;
    final messenger = ScaffoldMessenger.of(_deps.context());
    try {
      await _deps.installedState.stremio.setAddonAlias(a.storageKey, alias);
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            alias.isEmpty ? 'Using ${a.name}' : 'Renamed to ${alias.trim()}',
          ),
        ),
      );
    } catch (error) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not rename addon: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> updateAddon(StremioAddon a) async {
    final messenger = ScaffoldMessenger.of(_deps.context());
    final refreshed = await _deps.installedState.stremio.refreshAddon(
      a.manifestUrl,
    );
    if (!_deps.mounted()) return;
    if (refreshed == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update ${a.displayName}'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (refreshed.version != a.version) {
      final detail = (a.version != null && refreshed.version != null)
          ? ' (v${a.version} → v${refreshed.version})'
          : '';
      messenger.showSnackBar(
        SnackBar(content: Text('${a.displayName} updated$detail')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('${a.displayName} is already up to date')),
      );
    }
  }

  Future<void> removeAddon(StremioAddon a) async {
    final app = AppThemeScope.of(_deps.context());
    final messenger = ScaffoldMessenger.of(_deps.context());
    final int borrowerCount;
    try {
      borrowerCount = await _deps.installedState.stremio.addonBorrowerCount(
        a.storageKey,
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to check sharing: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_deps.mounted()) return;
    final isShared = borrowerCount > 0;
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (ctx) => AddonHubHubDialog(
        title: 'Remove addon',
        content: Text(
          isShared
              ? '"${a.displayName}" is shared with $borrowerCount other '
                    'profile${borrowerCount == 1 ? '' : 's'}. Removing it '
                    'will also remove it from those shared profiles.'
              : 'Remove "${a.displayName}" from your addons?',
          style: TextStyle(color: app.fade(app.core.tx, 0.75)),
        ),
        actions: [
          AddonHubHubDialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          AddonHubHubDialogButton(
            label: 'Remove',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !_deps.mounted()) return;
    try {
      await _deps.installedState.stremio.removeAddon(
        a.storageKey,
        revokeSharedProfiles: isShared,
      );
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${a.displayName} removed')),
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to remove: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
