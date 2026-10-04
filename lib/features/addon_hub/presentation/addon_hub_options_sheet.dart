import 'package:debrify/features/addon_hub/presentation/addon_hub_option_tile.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

// ── Options bottom sheet ─────────────────────────────────────────────────────
class AddonHubAddonOptionsSheet extends StatelessWidget {
  final StremioAddon addon;
  final VoidCallback onToggle;
  final VoidCallback onUpdate;
  final VoidCallback? onRename;
  final VoidCallback onDetails;
  final VoidCallback onRemove;

  const AddonHubAddonOptionsSheet({
    required this.addon,
    required this.onToggle,
    required this.onUpdate,
    this.onRename,
    required this.onDetails,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: app.fade(app.core.tx, 0.2),
                borderRadius: app.shape.br(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                addon.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            AddonHubOptionTile(
              autofocus: true,
              icon: addon.enabled
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              label: addon.enabled ? 'Disable' : 'Enable',
              onTap: onToggle,
            ),
            if (!addon.connectionResourceSecretPending)
              AddonHubOptionTile(
                icon: Icons.sync_rounded,
                label: 'Update',
                onTap: onUpdate,
              ),
            if (onRename != null)
              AddonHubOptionTile(
                icon: Icons.drive_file_rename_outline_rounded,
                label: 'Rename',
                onTap: onRename!,
              ),
            AddonHubOptionTile(
              icon: Icons.info_outline_rounded,
              label: 'View details',
              onTap: onDetails,
            ),
            AddonHubOptionTile(
              icon: Icons.delete_outline_rounded,
              label: 'Remove',
              danger: true,
              onTap: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
