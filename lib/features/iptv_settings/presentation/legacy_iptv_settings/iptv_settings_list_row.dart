import 'package:debrify/features/iptv_settings/presentation/iptv_settings_icon_button.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// One custom list in the Settings "Your Lists" section: name, count, and the
/// four actions. Each action carries its own focus node so DPAD walks them in
/// reading order.
class IptvSettingsListRow extends StatelessWidget {
  final IptvListMeta list;
  final bool isFirst;
  final bool isLast;
  final FocusNode? renameFocusNode;
  final FocusNode? upFocusNode;
  final FocusNode? downFocusNode;
  final FocusNode? deleteFocusNode;
  final VoidCallback onRename;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  const IptvSettingsListRow({
    required this.list,
    required this.isFirst,
    required this.isLast,
    required this.renameFocusNode,
    required this.upFocusNode,
    required this.downFocusNode,
    required this.deleteFocusNode,
    required this.onRename,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.bookmark_rounded, size: 20, color: t.dim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  list.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  list.channelCount == 1
                      ? '1 channel'
                      : '${list.channelCount} channels',
                  style: TextStyle(fontSize: 12, color: t.dim2),
                ),
              ],
            ),
          ),
          IptvSettingsIconButton(
            focusNode: renameFocusNode,
            icon: Icons.edit_outlined,
            tooltip: 'Rename',
            onPressed: onRename,
          ),
          // The ends of the list keep their arrows for a stable focus order,
          // but a no-op move would just be a dead keypress — skip it.
          IptvSettingsIconButton(
            focusNode: upFocusNode,
            icon: Icons.keyboard_arrow_up_rounded,
            color: isFirst ? t.dim2 : null,
            tooltip: 'Move up',
            onPressed: isFirst ? () {} : onMoveUp,
          ),
          IptvSettingsIconButton(
            focusNode: downFocusNode,
            icon: Icons.keyboard_arrow_down_rounded,
            color: isLast ? t.dim2 : null,
            tooltip: 'Move down',
            onPressed: isLast ? () {} : onMoveDown,
          ),
          IptvSettingsIconButton(
            focusNode: deleteFocusNode,
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
