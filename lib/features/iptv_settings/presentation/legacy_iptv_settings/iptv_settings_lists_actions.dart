import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/iptv/iptv_list_name_dialog.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsListsActionsDeps = ({
  IptvSettingsSourcesOwner sourcesOwner,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  void Function() ensureFocusNodes,
  Future<void> Function(Future<void> Function() body) runProfileAction,
  BuildContext Function() context,
  void Function(String message, {bool isError}) showSnackBar,
  IptvSettingsFocusOwner focusOwner,
  void Function(FocusNode node) focusAndReveal,
});

class IptvSettingsListsActions {
  IptvSettingsListsActions(this._deps);
  final IptvSettingsListsActionsDeps _deps;

  List<IptvListMeta> get customLists => [
    for (final list in _deps.sourcesOwner.lists)
      if (!list.isBuiltin) list,
  ];

  // ── Channel lists ────────────────────────────────────────────────────────

  Future<void> reloadLists() async {
    final lists = await IptvFavoritesStorage.getIptvLists();
    if (!_deps.mounted()) return;
    _deps.setState(() => _deps.sourcesOwner.lists = lists);
    _deps.ensureFocusNodes();
  }

  Future<void> createList() => _deps.runProfileAction(createListForProfile);

  Future<void> createListForProfile() async {
    final name = await showIptvListNameDialog(
      context: _deps.context(),
      title: 'New list',
      confirmLabel: 'Create',
      existingNames: [for (final list in _deps.sourcesOwner.lists) list.name],
    );
    if (name == null || !_deps.mounted()) return;
    await IptvFavoritesStorage.createIptvList(name);
    await reloadLists();
    if (!_deps.mounted()) return;
    _deps.showSnackBar('Created "$name"', isError: false);
  }

  Future<void> renameList(IptvListMeta list) =>
      _deps.runProfileAction(() => renameListForProfile(list));

  Future<void> renameListForProfile(IptvListMeta list) async {
    final name = await showIptvListNameDialog(
      context: _deps.context(),
      title: 'Rename list',
      confirmLabel: 'Save',
      initialValue: list.name,
      existingNames: [for (final entry in _deps.sourcesOwner.lists) entry.name],
    );
    if (name == null || name == list.name || !_deps.mounted()) return;
    await IptvFavoritesStorage.renameIptvList(list.id, name);
    await reloadLists();
  }

  Future<void> deleteList(IptvListMeta list) =>
      _deps.runProfileAction(() => deleteListForProfile(list));

  Future<void> deleteListForProfile(IptvListMeta list) async {
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: Text('Delete "${list.name}"?'),
        content: Text(
          list.channelCount == 0
              ? 'The list is empty, so nothing else changes.'
              : 'The ${list.channelCount} channels in it stay in your '
                    'playlists — only the list goes away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_deps.mounted()) return;
    await IptvFavoritesStorage.deleteIptvList(list.id);
    await reloadLists();
    if (!_deps.mounted()) return;
    // The deleted row's focus node is gone with it; land DPAD on the same
    // slot of a surviving list, or on Create when the section empties.
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_deps.mounted()) return;
        if (_deps.focusOwner.listFocusNodes.isEmpty) {
          _deps.focusAndReveal(_deps.focusOwner.createListFocusNode);
        } else {
          _deps.focusAndReveal(_deps.focusOwner.listFocusNodes.first);
        }
      });
    }
    _deps.showSnackBar('Deleted "${list.name}"', isError: false);
  }

  Future<void> moveList(IptvListMeta list, int delta) =>
      _deps.runProfileAction(() => moveListForProfile(list, delta));

  Future<void> moveListForProfile(IptvListMeta list, int delta) async {
    final order = [for (final entry in customLists) entry.id];
    final index = order.indexOf(list.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= order.length) return;
    order.removeAt(index);
    order.insert(target, list.id);
    await IptvFavoritesStorage.reorderIptvLists(order);
    await reloadLists();
  }

  /// Rename / reorder / delete for one list, as a sheet.
  ///
  /// The single-column layout spends four DPAD stops per list on an icon
  /// strip; the wide layout spends one and opens this. Move up/down are
  /// omitted at the ends rather than shown disabled — a focusable dead
  /// control is worse than an absent one on a remote.
  Future<void> showListActions(IptvListMeta list) async {
    final t = AppThemeScope.of(_deps.context()).settings;
    final lists = customLists;
    final index = lists.indexWhere((l) => l.id == list.id);
    if (index < 0) return;

    final action = await showModalBottomSheet<String>(
      context: _deps.context(),
      backgroundColor: t.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.bookmark_rounded, color: t.accent2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      list.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${list.channelCount} channel'
                    '${list.channelCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12.5, color: t.dim),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              autofocus: true,
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            if (index > 0)
              ListTile(
                leading: const Icon(Icons.arrow_upward_rounded),
                title: const Text('Move up'),
                onTap: () => Navigator.of(context).pop('up'),
              ),
            if (index < lists.length - 1)
              ListTile(
                leading: const Icon(Icons.arrow_downward_rounded),
                title: const Text('Move down'),
                onTap: () => Navigator.of(context).pop('down'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: t.danger),
              title: Text('Delete', style: TextStyle(color: t.danger)),
              subtitle: const Text('The channels themselves are kept'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!_deps.mounted() || action == null) return;
    switch (action) {
      case 'rename':
        await renameList(list);
      case 'up':
        await moveList(list, -1);
      case 'down':
        await moveList(list, 1);
      case 'delete':
        await deleteList(list);
    }
  }

  FocusNode? listNodeAt(int index) =>
      index < _deps.focusOwner.listFocusNodes.length
      ? _deps.focusOwner.listFocusNodes[index]
      : null;
}
