import 'package:debrify/features/addon_hub/presentation/addon_hub_dialog.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_options_sheet.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AddonHubMenusDeps = ({
  BuildContext Function() context,
  Future<void> Function(StremioAddon) toggleAddon,
  Future<void> Function(StremioAddon) updateAddon,
  Future<void> Function(StremioAddon) renameAddon,
  Future<void> Function(StremioAddon) removeAddon,
  AddonHubNavigationState navigationState,
  Future<void> Function() importJson,
  Future<void> Function() updateAll,
  Future<void> Function() deleteAll,
  Future<bool> Function() autoUpdateEnabled,
  Future<void> Function(bool enabled) setAutoUpdate,
});

class AddonHubMenus {
  AddonHubMenus(this._deps);
  final AddonHubMenusDeps _deps;

  // ── Sheets / menus ───────────────────────────────────────────────────────
  void showOptions(StremioAddon a) {
    final app = AppThemeScope.of(_deps.context());
    showModalBottomSheet<void>(
      context: _deps.context(),
      backgroundColor: app.seeAll.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => AddonHubAddonOptionsSheet(
        addon: a,
        onToggle: () {
          Navigator.of(ctx).pop();
          _deps.toggleAddon(a);
        },
        onUpdate: () {
          Navigator.of(ctx).pop();
          _deps.updateAddon(a);
        },
        onRename: a.canManage && !a.connectionResourceSecretPending
            ? () {
                Navigator.of(ctx).pop();
                _deps.renameAddon(a);
              }
            : null,
        onDetails: () {
          Navigator.of(ctx).pop();
          showDetails(a);
        },
        onRemove: () {
          Navigator.of(ctx).pop();
          _deps.removeAddon(a);
        },
      ),
    );
  }

  void showDetails(StremioAddon a) {
    final app = AppThemeScope.of(_deps.context());
    showDialog<void>(
      context: _deps.context(),
      builder: (ctx) => AddonHubHubDialog(
        title: a.displayName,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (a.description != null) ...[
                Text(
                  a.description!,
                  style: TextStyle(color: app.fade(app.core.tx, 0.8)),
                ),
                const SizedBox(height: 14),
              ],
              if (a.userAlias != null) detailRow('Manifest name', a.name),
              detailRow('ID', a.id),
              if (a.version != null) detailRow('Version', a.version!),
              detailRow('Types', a.types.isEmpty ? 'None' : a.types.join(', ')),
              detailRow(
                'Resources',
                a.resources.isEmpty ? 'None' : a.resources.join(', '),
              ),
              const SizedBox(height: 10),
              SelectableText(
                a.manifestUrl,
                style: TextStyle(
                  color: app.seeAll.accent2,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          AddonHubHubDialogButton(
            label: 'Copy URL',
            onTap: () {
              Clipboard.setData(ClipboardData(text: a.manifestUrl));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(_deps.context()).showSnackBar(
                const SnackBar(content: Text('URL copied to clipboard')),
              );
            },
          ),
          AddonHubHubDialogButton(
            label: 'Close',
            primary: true,
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Widget detailRow(String label, String value) {
    final app = AppThemeScope.of(_deps.context());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: app.fade(app.core.tx, 0.4),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }

  Future<void> showActionsMenu() async {
    final app = AppThemeScope.of(_deps.context());
    final overlay =
        Overlay.of(_deps.context()).context.findRenderObject() as RenderBox?;
    final btn =
        _deps.navigationState.moreFocus.context?.findRenderObject()
            as RenderBox?;
    if (overlay == null || btn == null) return;
    final topLeft = btn.localToGlobal(
      Offset(0, btn.size.height + 6),
      ancestor: overlay,
    );
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        topLeft,
        btn.localToGlobal(btn.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    // The menu must open even when the setting cannot be read.
    final autoUpdate = await _deps.autoUpdateEnabled().catchError((_) => true);
    if (!_deps.context().mounted) return;
    final choice = await showMenu<String>(
      context: _deps.context(),
      position: pos,
      color: app.seeAll.panel2,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(14),
        side: BorderSide(color: app.seeAll.line),
      ),
      items: [
        menuItem('import', Icons.file_upload_outlined, 'Import from JSON'),
        menuItem('update', Icons.sync_rounded, 'Update all'),
        menuItem(
          'auto',
          autoUpdate ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
          autoUpdate ? 'Auto-update: on' : 'Auto-update: off',
        ),
        menuItem(
          'delete',
          Icons.delete_outline_rounded,
          'Delete all',
          danger: true,
        ),
      ],
    );
    switch (choice) {
      case 'import':
        _deps.importJson();
        break;
      case 'update':
        _deps.updateAll();
        break;
      case 'auto':
        final saved = await _deps
            .setAutoUpdate(!autoUpdate)
            .then((_) => true, onError: (_) => false);
        final context = _deps.context();
        if (saved && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                autoUpdate
                    ? 'Addons will only update when you ask'
                    : 'Addons will update once a day',
              ),
            ),
          );
        }
        break;
      case 'delete':
        _deps.deleteAll();
        break;
    }
  }

  PopupMenuItem<String> menuItem(
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final app = AppThemeScope.of(_deps.context());
    final color = danger ? const Color(0xFFEF4444) : app.core.tx;
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
