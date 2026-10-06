import 'package:debrify/features/stremio_tv_catalogs/data/local_catalog_importer.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:flutter/material.dart';

// ─── Import from MDBList dialog ──────────────────────────────────────────────

/// Which MDBList lists to browse in the import picker.
enum _MdblistListCategory {
  mine,
  liked,
  top;

  String get label => switch (this) {
    _MdblistListCategory.mine => 'My Lists',
    _MdblistListCategory.liked => 'Liked Lists',
    _MdblistListCategory.top => 'Top Lists',
  };
}

/// Picks an MDBList list (the user's own or a public/top list) and saves it as
/// a local catalog — which the service then surfaces as a Stremio TV channel.
/// Mirrors [_ImportTraktDialog]; items come from [MdblistListSource] already as
/// [StremioMeta], and `mdblistListId` is stored so the catalog can be refreshed.
class _ImportMdblistDialog extends StatefulWidget {
  const _ImportMdblistDialog();

  @override
  State<_ImportMdblistDialog> createState() => _ImportMdblistDialogState();
}

typedef LcMdblistDialog = _ImportMdblistDialog;

class _ImportMdblistDialogState extends State<_ImportMdblistDialog> {
  _MdblistListCategory _category = _MdblistListCategory.mine;
  List<MdblistListChoice> _lists = [];
  bool _loading = false;
  bool _importing = false;
  String? _error;
  bool _connected = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoad();
  }

  Future<void> _checkAuthAndLoad() async {
    final auth = await MdblistService.instance.isAuthenticated();
    if (!mounted) return;
    setState(() {
      _connected = auth;
      _checked = true;
    });
    if (auth) _fetchLists();
  }

  Future<void> _onCategoryChanged(_MdblistListCategory category) {
    setState(() {
      _category = category;
      _error = null;
      _lists = [];
    });
    return _fetchLists();
  }

  Future<void> _fetchLists() async {
    setState(() {
      _loading = true;
      _error = null;
      _lists = [];
    });
    try {
      final lists = switch (_category) {
        _MdblistListCategory.mine =>
          await MdblistListSource.instance.loadUserLists(),
        _MdblistListCategory.liked =>
          await MdblistListSource.instance.loadLikedLists(),
        _MdblistListCategory.top =>
          await MdblistListSource.instance.loadTopLists(),
      };
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load lists: $e';
        _loading = false;
      });
    }
  }

  Future<void> _importList(MdblistListChoice choice) async {
    final name = choice.name;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      // Duplicate check (mirrors the Trakt importer: a mixed list splits into
      // "— Movies"/"— Series", so guard those names too).
      final existing = await StremioCatalogStorage.getStremioTvLocalCatalogs();
      if (existing.any(
        (c) =>
            c['name'] == name ||
            c['name'] == '$name — Movies' ||
            c['name'] == '$name — Series',
      )) {
        setState(() {
          _error = '"$name" already imported';
          _importing = false;
        });
        return;
      }

      final loaded = await MdblistListSource.instance.loadListItems(choice);
      if (!mounted) return;
      if (loaded.failed || !loaded.complete) {
        setState(() {
          _error = 'Failed to load "$name"';
          _importing = false;
        });
        return;
      }

      await _saveAsCatalog(
        loaded.items,
        name,
        mdblistMeta: {
          'mdblistListId': choice.id,
          if (choice.ownerName != null) 'mdblistOwner': choice.ownerName,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to import: $e';
        _importing = false;
      });
    }
  }

  /// Map items to the native catalog format, split by type, and save. A list
  /// with both movies and series becomes two channels (a Stremio TV channel is
  /// single-type), matching the Trakt importer.
  Future<void> _saveAsCatalog(
    List<StremioMeta> metas,
    String name, {
    required Map<String, dynamic> mdblistMeta,
  }) async {
    if (metas.isEmpty) {
      setState(() {
        _error = '"$name" is empty';
        _importing = false;
      });
      return;
    }

    final catalogItems = <Map<String, dynamic>>[];
    for (final meta in metas) {
      catalogItems.add({
        'id': meta.id,
        'name': meta.name,
        'type': meta.type,
        if (meta.year != null) 'year': int.tryParse(meta.year!) ?? meta.year,
        if (meta.description != null) 'overview': meta.description,
        if (meta.imdbRating != null) 'rating': meta.imdbRating,
        if (meta.poster != null) 'poster': meta.poster,
        if (meta.background != null) 'fanart': meta.background,
        if (meta.genres != null && meta.genres!.isNotEmpty)
          'genres': meta.genres,
      });
    }

    final movies = catalogItems.where((i) => i['type'] != 'series').toList();
    final series = catalogItems.where((i) => i['type'] == 'series').toList();

    if (movies.isNotEmpty && series.isNotEmpty) {
      for (final entry in [
        (items: movies, type: 'movie', suffix: 'Movies'),
        (items: series, type: 'series', suffix: 'Series'),
      ]) {
        final catName = '$name — ${entry.suffix}';
        await StremioCatalogStorage.addStremioTvLocalCatalog({
          'id': LocalCatalogImporter.generateId(catName),
          'name': catName,
          'type': entry.type,
          'addedAt': DateTime.now().toIso8601String(),
          'items': entry.items,
          ...mdblistMeta,
        });
      }
    } else {
      final catalogType = series.length > movies.length ? 'series' : 'movie';
      await StremioCatalogStorage.addStremioTvLocalCatalog({
        'id': LocalCatalogImporter.generateId(name),
        'name': name,
        'type': catalogType,
        'addedAt': DateTime.now().toIso8601String(),
        'items': catalogItems,
        ...mdblistMeta,
      });
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_checked) {
      return const AlertDialog(
        content: Center(heightFactor: 1, child: CircularProgressIndicator()),
      );
    }

    if (!_connected) {
      return AlertDialog(
        title: const Text('Import from MDBList'),
        content: const Text('Connect MDBList first in Settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Import from MDBList'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<_MdblistListCategory>(
              isExpanded: true,
              value: _category,
              decoration: InputDecoration(
                labelText: 'Lists',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: _MdblistListCategory.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) _onCategoryChanged(value);
              },
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_lists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  _category == _MdblistListCategory.top
                      ? 'No top lists found.'
                      : 'No lists found. Create some on mdblist.com.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _lists.length,
                  itemBuilder: (context, index) {
                    final list = _lists[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.playlist_play_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      title: Text(list.name, style: theme.textTheme.bodyMedium),
                      subtitle: Text(
                        [
                          if (list.ownerName != null) 'by ${list.ownerName}',
                          '${list.itemCount} items',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: _importing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded, size: 20),
                      onTap: _importing ? null : () => _importList(list),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
