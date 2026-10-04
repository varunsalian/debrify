import 'package:debrify/features/iptv_settings/presentation/iptv_settings_focusable_tile.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_list_row.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsListViewsDeps = ({
  BuildContext Function() context,
  List<IptvListMeta> Function() customLists,
  FocusNode? Function(int index) listNodeAt,
  Future<void> Function(IptvListMeta list) renameList,
  Future<void> Function(IptvListMeta list, int delta) moveList,
  Future<void> Function(IptvListMeta list) deleteList,
  IptvSettingsFocusOwner focusOwner,
  Future<void> Function() createList,
});

class IptvSettingsListViews {
  IptvSettingsListViews(this._deps);
  final IptvSettingsListViewsDeps _deps;

  List<Widget> buildListsSection() {
    final t = AppThemeScope.of(_deps.context()).settings;
    final lists = _deps.customLists();
    if (lists.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          child: Row(
            children: [
              Icon(Icons.bookmark_border_rounded, color: t.dim2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No lists yet — Favorites is always there.',
                  style: TextStyle(fontSize: 13, color: t.dim),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < lists.length; i++)
        IptvSettingsListRow(
          list: lists[i],
          isFirst: i == 0,
          isLast: i == lists.length - 1,
          renameFocusNode: _deps.listNodeAt(i * 4),
          upFocusNode: _deps.listNodeAt(i * 4 + 1),
          downFocusNode: _deps.listNodeAt(i * 4 + 2),
          deleteFocusNode: _deps.listNodeAt(i * 4 + 3),
          onRename: () => _deps.renameList(lists[i]),
          onMoveUp: () => _deps.moveList(lists[i], -1),
          onMoveDown: () => _deps.moveList(lists[i], 1),
          onDelete: () => _deps.deleteList(lists[i]),
        ),
    ];
  }

  Widget buildListsView() {
    final t = AppThemeScope.of(_deps.context()).settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Your Lists'),
        Text(
          'Hold OK (or long-press) any channel to add it to a list. '
          'Deleting a list never deletes its channels.',
          style: TextStyle(fontSize: 12, color: t.dim),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ...buildListsSection(),
              IptvSettingsFocusableTile(
                focusNode: _deps.focusOwner.createListFocusNode,
                icon: Icons.add_rounded,
                label: 'Create list',
                onTap: _deps.createList,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
