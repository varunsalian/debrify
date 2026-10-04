import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/iptv_category_order_page.dart';
import 'package:debrify/screens/settings/iptv_channel_order_page.dart';
import 'package:debrify/screens/settings/iptv_hidden_categories_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/profiles/profile_async_authorization.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsCatalogActionsDeps = ({
  IptvSettingsSourcesOwner sourcesOwner,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  void Function(String message, {bool isError}) showSnackBar,
});

class IptvSettingsCatalogActions {
  IptvSettingsCatalogActions(this._deps);
  final IptvSettingsCatalogActionsDeps _deps;

  /// Sources whose categories can be hidden: the ones stored as catalogs.
  /// Imported files and (elsewhere) virtual shelves never become one, so
  /// there is nothing to hide against.
  List<IptvPlaylist> get hideableSources => [
    for (final p in _deps.sourcesOwner.playlists)
      if (!p.isLocalFile) p,
  ];

  /// Category ordering also works for imported files: they have no catalog
  /// rows, but their saved playlist id is a stable profile-local order key.
  List<IptvPlaylist> get categoryOrderSources =>
      List.unmodifiable(_deps.sourcesOwner.playlists);

  /// Every catalog key a source can store under — an Xtream login has one per
  /// content type, everything else exactly one.
  List<String> catalogKeysFor(IptvPlaylist playlist) {
    if (playlist.isXtreamCodes) {
      final keys = <String>[];
      for (final type in IptvCatalogKey.xtreamContentTypes) {
        final key = IptvCatalogKey.forPlaylist(playlist, type);
        if (key != null) keys.add(key);
      }
      return keys;
    }
    final key = IptvCatalogKey.forPlaylist(playlist, 'live');
    return key == null ? const [] : [key];
  }

  Map<String, WebDavSyncCatalogOwnerReference> catalogOwnerReferencesFor(
    IptvPlaylist playlist,
  ) {
    final resourceId = playlist.connectionResourceId;
    if (resourceId == null) {
      return const <String, WebDavSyncCatalogOwnerReference>{};
    }
    if (playlist.isLocalFile) {
      final key = IptvCatalogKey.forLocalCategoryOrder(playlist.id);
      return <String, WebDavSyncCatalogOwnerReference>{
        key: WebDavSyncCatalogOwnerReference(
          localResourceId: resourceId,
          variant: 'local',
        ),
      };
    }
    if (playlist.isXtreamCodes) {
      return <String, WebDavSyncCatalogOwnerReference>{
        for (final type in IptvCatalogKey.xtreamContentTypes)
          if (IptvCatalogKey.forPlaylist(playlist, type) case final key?)
            key: WebDavSyncCatalogOwnerReference(
              localResourceId: resourceId,
              variant: 'xc-$type',
            ),
      };
    }
    final key = IptvCatalogKey.forPlaylist(playlist, 'live');
    return key == null
        ? const <String, WebDavSyncCatalogOwnerReference>{}
        : <String, WebDavSyncCatalogOwnerReference>{
            key: WebDavSyncCatalogOwnerReference(
              localResourceId: resourceId,
              variant: 'm3u',
            ),
          };
  }

  /// Open the per-source hidden-categories manager, then re-read the counts
  /// the section badges rows with — the page is where they change.
  Future<void> openHiddenCategories(IptvPlaylist playlist) async {
    await Navigator.of(_deps.context()).push(
      MaterialPageRoute(
        builder: (_) => IptvHiddenCategoriesPage(playlist: playlist),
      ),
    );
    if (!_deps.mounted()) return;
    _deps.setState(reloadHiddenCounts);
  }

  Future<void> openCategoryOrder(IptvPlaylist playlist) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.iptv,
    );
    if (!_deps.mounted()) return;
    try {
      await authorization?.runIfCurrent(() async {});
    } on StateError {
      _deps.showSnackBar(
        'The active profile changed. Category order was not opened.',
        isError: true,
      );
      return;
    }
    if (!_deps.mounted()) return;
    await Navigator.of(_deps.context()).push(
      MaterialPageRoute(
        builder: (_) => IptvCategoryOrderPage(
          playlist: playlist,
          authorization: authorization,
        ),
      ),
    );
  }

  Future<void> openChannelOrder() async {
    await pushSettingsPage<void>(_deps.context(), const IptvChannelOrderPage());
  }

  /// Re-read how many categories each source hides. One query for every key,
  /// then summed per source.
  void reloadHiddenCounts() {
    if (!IptvCatalogDb.isOpen) return;
    final keysBySource = <String, List<String>>{
      for (final p in hideableSources) p.id: catalogKeysFor(p),
    };
    final counts = IptvCatalogDb.hiddenGroupCounts(
      keysBySource.values.expand((keys) => keys),
    );
    final out = <String, int>{};
    for (final entry in keysBySource.entries) {
      var total = 0;
      for (final key in entry.value) {
        total += counts[key] ?? 0;
      }
      if (total > 0) out[entry.key] = total;
    }
    _deps.sourcesOwner.hiddenCounts = out;
  }
}
