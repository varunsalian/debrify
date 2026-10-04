import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:flutter/material.dart';

class _MdblistQuickActions extends StatelessWidget {
  const _MdblistQuickActions({required this.options, required this.onSelected});
  final List<MdblistMenuOption> options;
  final void Function(MdblistItemMenuAction) onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'MDBLIST ACTIONS',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.2,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            ActionChip(
              avatar: Icon(option.icon, size: 18, color: option.color),
              label: Text(option.caption),
              tooltip: option.label,
              onPressed: () => onSelected(option.action),
            ),
        ],
      ),
    ],
  );
}

typedef CatalogMdblistQuickActions = _MdblistQuickActions;

const catalogMdblistQuickActionsConstructor = _MdblistQuickActions.new;
