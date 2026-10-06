import 'package:debrify/features/stremio_tv_catalogs/data/local_catalog_importer.dart';
import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:debrify/services/trakt/trakt_item_transformer.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter/material.dart';

// ─── Import from Trakt dialog ────────────────────────────────────────────────

enum _TraktListSource {
  watchlist,
  history,
  collection,
  ratings,
  trending,
  popular,
  anticipated,
  recommendations,
  customLists,
  likedLists,
}

extension _TraktListSourceExt on _TraktListSource {
  String get label {
    switch (this) {
      case _TraktListSource.watchlist:
        return 'Watchlist';
      case _TraktListSource.history:
        return 'History';
      case _TraktListSource.collection:
        return 'Collection';
      case _TraktListSource.ratings:
        return 'Ratings';
      case _TraktListSource.trending:
        return 'Trending';
      case _TraktListSource.popular:
        return 'Popular';
      case _TraktListSource.anticipated:
        return 'Anticipated';
      case _TraktListSource.recommendations:
        return 'Recommendations';
      case _TraktListSource.customLists:
        return 'Custom Lists';
      case _TraktListSource.likedLists:
        return 'Liked Lists';
    }
  }

  /// Whether this source requires picking a specific list before importing.
  bool get needsListPicker =>
      this == _TraktListSource.customLists ||
      this == _TraktListSource.likedLists;

  /// The API list type value for direct-fetch sources.
  String get apiValue {
    switch (this) {
      case _TraktListSource.watchlist:
        return 'watchlist';
      case _TraktListSource.history:
        return 'history';
      case _TraktListSource.collection:
        return 'collection';
      case _TraktListSource.ratings:
        return 'ratings';
      case _TraktListSource.trending:
        return 'trending';
      case _TraktListSource.popular:
        return 'popular';
      case _TraktListSource.anticipated:
        return 'anticipated';
      case _TraktListSource.recommendations:
        return 'recommendations';
      default:
        return '';
    }
  }
}

class _ImportTraktDialog extends StatefulWidget {
  const _ImportTraktDialog();

  @override
  State<_ImportTraktDialog> createState() => _ImportTraktDialogState();
}

typedef LcTraktDialog = _ImportTraktDialog;

class _ImportTraktDialogState extends State<_ImportTraktDialog> {
  final TraktService _traktService = TraktService.instance;
  _TraktListSource _source = _TraktListSource.watchlist;
  List<Map<String, dynamic>> _lists = [];
  bool _loading = false;
  bool _importing = false;
  String? _error;
  bool _authenticated = false;
  bool _authChecked = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoad();
  }

  Future<void> _checkAuthAndLoad() async {
    final auth = await _traktService.isAuthenticated();
    if (!mounted) return;
    setState(() {
      _authenticated = auth;
      _authChecked = true;
    });
    if (auth && _source.needsListPicker) _fetchLists();
  }

  Future<void> _onSourceChanged(_TraktListSource source) {
    setState(() {
      _source = source;
      _error = null;
      _lists = [];
    });
    if (source.needsListPicker) {
      return _fetchLists();
    }
    return Future.value();
  }

  Future<void> _fetchLists() async {
    setState(() {
      _loading = true;
      _error = null;
      _lists = [];
    });

    try {
      final List<Map<String, dynamic>> lists;
      if (_source == _TraktListSource.customLists) {
        lists = await _traktService.fetchCustomLists();
      } else {
        lists = await _traktService.fetchLikedLists();
      }
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

  /// Import a direct list type (watchlist, trending, etc.) — no list picker needed.
  Future<void> _importDirect() async {
    final name = 'Trakt ${_source.label}';

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      // Check for duplicates
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

      final movies = await _traktService.fetchList(_source.apiValue, 'movies');
      final shows = await _traktService.fetchList(_source.apiValue, 'shows');
      final rawItems = [...movies, ...shows];

      if (!mounted) return;
      await _saveAsCatalog(
        rawItems,
        name,
        traktMeta: {'traktSource': _source.apiValue},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to import: $e';
        _importing = false;
      });
    }
  }

  /// Import a specific custom/liked list.
  Future<void> _importList(Map<String, dynamic> list) async {
    final name = list['name'] as String? ?? 'Unknown';
    final slug = list['ids']?['slug'] as String? ?? '';
    final listId = list['ids']?['trakt']?.toString();
    final listedCount = list['item_count'];
    final ownerSlug =
        (list['user'] as Map<String, dynamic>?)?['ids']?['slug'] as String?;
    final owner =
        (list['user'] as Map<String, dynamic>?)?['username'] as String?;
    debugPrint(
      'StremioTV TraktImport: start list="$name" slug="$slug" '
      'listId=${listId ?? 'none'} source=${_source.label} '
      'owner=${owner ?? 'none'} ownerSlug=${ownerSlug ?? 'none'} '
      'itemCount=$listedCount',
    );
    if (slug.isEmpty) return;

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      // Check for duplicates
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

      final List<dynamic> rawItems;
      if (_source == _TraktListSource.customLists) {
        final movies = await _traktService.fetchCustomListItems(slug, 'movies');
        final shows = await _traktService.fetchCustomListItems(slug, 'shows');
        debugPrint(
          'StremioTV TraktImport: fetched custom list="$name" '
          'movies=${movies.length} shows=${shows.length}',
        );
        rawItems = [...movies, ...shows];
      } else {
        if ((listId == null || listId.isEmpty) &&
            (ownerSlug == null || ownerSlug.isEmpty) &&
            (owner == null || owner.isEmpty)) {
          debugPrint(
            'StremioTV TraktImport: missing owner for liked list="$name"',
          );
          setState(() {
            _error = 'Missing list owner';
            _importing = false;
          });
          return;
        }
        final movies = await _traktService.fetchLikedListItemsFromList(
          list,
          'movies',
        );
        final shows = await _traktService.fetchLikedListItemsFromList(
          list,
          'shows',
        );
        debugPrint(
          'StremioTV TraktImport: fetched liked list="$name" '
          'listId=${listId ?? 'none'} owner=${ownerSlug ?? owner ?? 'none'} '
          'movies=${movies.length} shows=${shows.length}',
        );
        rawItems = [...movies, ...shows];
      }

      if (!mounted) return;

      await _saveAsCatalog(
        rawItems,
        name,
        traktMeta: {
          'traktSource': _source == _TraktListSource.customLists
              ? 'custom'
              : 'liked',
          'traktSlug': slug,
          if (listId != null) 'traktListId': listId,
          if (ownerSlug != null) 'traktOwnerSlug': ownerSlug,
          if (owner != null) 'traktOwner': owner,
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

  /// Shared logic: transform raw items, split by type, save as catalog(s).
  Future<void> _saveAsCatalog(
    List<dynamic> rawItems,
    String name, {
    required Map<String, dynamic> traktMeta,
  }) async {
    debugPrint(
      'StremioTV TraktImport: save start name="$name" '
      'rawItems=${rawItems.length} meta=$traktMeta',
    );
    if (rawItems.isEmpty) {
      debugPrint('StremioTV TraktImport: "$name" rejected: raw list is empty');
      setState(() {
        _error = '"$name" is empty';
        _importing = false;
      });
      return;
    }

    final metas = TraktItemTransformer.transformList(rawItems);
    debugPrint(
      'StremioTV TraktImport: transformed name="$name" '
      'metas=${metas.length} rawItems=${rawItems.length}',
    );
    if (metas.isEmpty) {
      debugPrint(
        'StremioTV TraktImport: "$name" rejected: no transformable IMDB items',
      );
      setState(() {
        _error = 'No items with IMDB IDs found';
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
    debugPrint(
      'StremioTV TraktImport: catalog split name="$name" '
      'movies=${movies.length} series=${series.length}',
    );

    if (movies.isNotEmpty && series.isNotEmpty) {
      for (final entry in [
        (items: movies, type: 'movie', suffix: 'Movies'),
        (items: series, type: 'series', suffix: 'Series'),
      ]) {
        final catName = '$name — ${entry.suffix}';
        debugPrint(
          'StremioTV TraktImport: saving split catalog "$catName" '
          'type=${entry.type} items=${entry.items.length}',
        );
        await StremioCatalogStorage.addStremioTvLocalCatalog({
          'id': LocalCatalogImporter.generateId(catName),
          'name': catName,
          'type': entry.type,
          'addedAt': DateTime.now().toIso8601String(),
          'items': entry.items,
          ...traktMeta,
        });
      }
    } else {
      final catalogType = series.length > movies.length ? 'series' : 'movie';
      debugPrint(
        'StremioTV TraktImport: saving catalog "$name" '
        'type=$catalogType items=${catalogItems.length}',
      );
      await StremioCatalogStorage.addStremioTvLocalCatalog({
        'id': LocalCatalogImporter.generateId(name),
        'name': name,
        'type': catalogType,
        'addedAt': DateTime.now().toIso8601String(),
        'items': catalogItems,
        ...traktMeta,
      });
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_authChecked) {
      return const AlertDialog(
        content: Center(heightFactor: 1, child: CircularProgressIndicator()),
      );
    }

    if (!_authenticated) {
      return AlertDialog(
        title: const Text('Import from Trakt'),
        content: const Text('Sign in to Trakt first in Settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Import from Trakt'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Source dropdown
            DropdownButtonFormField<_TraktListSource>(
              isExpanded: true,
              value: _source,
              decoration: InputDecoration(
                labelText: 'List Type',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: _TraktListSource.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) _onSourceChanged(value);
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
            // Direct import sources — just show an import button
            if (!_source.needsListPicker) ...[
              if (_importing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                FilledButton.icon(
                  onPressed: _importDirect,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('Import ${_source.label}'),
                ),
            ],
            // List picker sources — show list of lists
            if (_source.needsListPicker) ...[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_lists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _source == _TraktListSource.customLists
                        ? 'No custom lists found.'
                        : 'No liked lists found.',
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
                      final name = list['name'] as String? ?? 'Unknown';
                      final itemCount = list['item_count'] as int?;
                      final owner =
                          (list['user'] as Map<String, dynamic>?)?['username']
                              as String?;

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.playlist_play_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        title: Text(name, style: theme.textTheme.bodyMedium),
                        subtitle: Text(
                          [
                            if (owner != null &&
                                _source == _TraktListSource.likedLists)
                              'by $owner',
                            if (itemCount != null) '$itemCount items',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: _importing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_rounded, size: 20),
                        onTap: _importing ? null : () => _importList(list),
                      );
                    },
                  ),
                ),
            ],
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
