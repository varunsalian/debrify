import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How a cloud folder's contents are arranged.
///
/// Was `_FolderViewMode`, declared privately and identically in both the
/// TorBox and Real-Debrid cloud files screens; the shared dropdown needs one
/// public type. Values and their order are unchanged, and the enum is never
/// persisted — the hosts keep it in in-memory maps keyed by torrent id.
enum CloudFolderViewMode { raw, sortedAZ, seriesArrange }

/// The in-folder "View Mode" dropdown shared by the TorBox and Real-Debrid
/// cloud files screens (G4-5). Moved verbatim from the byte-identical
/// `_buildViewModeDropdown` each host carried.
///
/// Only [CloudFolderViewMode.raw] and [CloudFolderViewMode.sortedAZ] are
/// offered; [CloudFolderViewMode.seriesArrange] is reachable in the model but
/// not from this control. That is the origin behaviour.
class CloudViewModeDropdown extends StatelessWidget {
  const CloudViewModeDropdown({
    super.key,
    required this.mode,
    required this.dropdownFocusNode,
    required this.backButtonFocusNode,
    required this.onChanged,
  });

  /// `_getCurrentViewMode()` on the host.
  final CloudFolderViewMode mode;

  final FocusNode dropdownFocusNode;

  /// Up-arrow from the dropdown lands here.
  final FocusNode backButtonFocusNode;

  /// `_setViewMode` on the host.
  final ValueChanged<CloudFolderViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          // Navigate to back button on up arrow
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<CloudFolderViewMode>(
          focusNode: dropdownFocusNode,
          autofocus: true,
          isExpanded: true,
          // The origin hosts carried this deprecation under the path-keyed
          // analyzer baseline; it moves here with the code (same handling as
          // G1'-2's onReorder). Switching to initialValue changes behaviour.
          // ignore: deprecated_member_use
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == CloudFolderViewMode.raw
                  ? Icons.view_list
                  : mode == CloudFolderViewMode.sortedAZ
                  ? Icons.sort_by_alpha
                  : Icons.video_library,
              color: theme.colorScheme.primary,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: const [
            DropdownMenuItem(
              value: CloudFolderViewMode.raw,
              child: Text('Raw'),
            ),
            DropdownMenuItem(
              value: CloudFolderViewMode.sortedAZ,
              child: Text('Sort (A-Z)'),
            ),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}
