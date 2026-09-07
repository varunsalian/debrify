import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../settings/widgets/settings_widgets.dart';

/// Edits a detached draft. The caller saves only after the user presses Save,
/// with its captured profile session still current.
class CollectionEditorScreen extends StatefulWidget {
  const CollectionEditorScreen({
    super.key,
    this.collection,
    required this.addons,
  });
  final HomeCollection? collection;
  final List<StremioAddon> addons;
  @override
  State<CollectionEditorScreen> createState() => _CollectionEditorScreenState();
}

class _CollectionEditorScreenState extends State<CollectionEditorScreen> {
  late final Map<String, dynamic> _draft =
      widget.collection?.toJson() ??
      {'id': _id('collection'), 'title': '', 'folders': <dynamic>[]};
  final _form = GlobalKey<FormState>();
  List<dynamic> get _folders => _draft['folders'] as List<dynamic>;

  Future<void> _editFolder([int? index]) async {
    final folder = index == null
        ? <String, dynamic>{
            'id': _id('folder'),
            'title': '',
            'sources': <dynamic>[],
          }
        : Map<String, dynamic>.from(_folders[index] as Map);
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => _FolderEditor(folder: folder, addons: widget.addons),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _folders.add(result);
      } else {
        _folders[index] = result;
      }
    });
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    _draft['debrifyCollectionVersion'] = 2;
    final collection = HomeCollection.fromJson(_draft);
    if (collection != null) Navigator.of(context).pop(collection);
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: settingsPageTheme(context),
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.collection == null ? 'Create collection' : 'Edit collection',
        ),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: _EditorBody(
          padding: const EdgeInsets.all(20),
          children: [
            _text(_draft, 'title', 'Collection title', required: true),
            _text(
              _draft,
              'backdropImageUrl',
              'Collection backdrop URL',
              url: true,
            ),
            _choice(_draft, 'viewMode', 'Folder layout', const {
              '': 'Use profile setting',
              'TABBED_GRID': 'Tabs',
              'FOLLOW_LAYOUT': 'Rows',
            }),
            _toggle(_draft, 'pinToTop', 'Pin to top', false),
            _toggle(_draft, 'focusGlowEnabled', 'Focus glow', true),
            _toggle(_draft, 'showAllTab', 'Show merged All view', true),
            const SizedBox(height: 20),
            const Text(
              'Folders',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            for (var i = 0; i < _folders.length; i++)
              _orderedTile(
                title: '${(_folders[i] as Map)['title']}',
                index: i,
                values: _folders,
                onEdit: () => _editFolder(i),
                onChanged: () => setState(() {}),
              ),
            OutlinedButton.icon(
              onPressed: () => _editFolder(),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add folder'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FolderEditor extends StatefulWidget {
  const _FolderEditor({required this.folder, required this.addons});
  final Map<String, dynamic> folder;
  final List<StremioAddon> addons;
  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final Map<String, dynamic> _draft = jsonDecode(
    jsonEncode(widget.folder),
  );
  late final List<CollectionCatalogSource> _sources =
      HomeCollectionFolder.fromJson(
        _draft,
        collectionId: 'draft',
      )!.sources.toList();
  final _form = GlobalKey<FormState>();

  Future<void> _editSource([int? index]) async {
    final source = await Navigator.of(context).push<CollectionCatalogSource>(
      MaterialPageRoute(
        builder: (_) => _SourceEditor(
          source: index == null ? null : _sources[index],
          addons: widget.addons,
        ),
      ),
    );
    if (!mounted || source == null) return;
    setState(() {
      if (index == null) {
        _sources.add(source);
      } else {
        _sources[index] = source;
      }
    });
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    _draft.remove('catalogSources');
    _draft['sources'] = [
      for (final s in _sources) {...s.toJson(), 'provider': s.provider},
    ];
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Edit folder'),
      actions: [TextButton(onPressed: _save, child: const Text('Save'))],
    ),
    body: Form(
      key: _form,
      child: _EditorBody(
        padding: const EdgeInsets.all(20),
        children: [
          _text(_draft, 'title', 'Folder title', required: true),
          _text(_draft, 'coverImageUrl', 'Cover image URL', url: true),
          _text(_draft, 'coverEmoji', 'Cover emoji'),
          _choice(_draft, 'tileShape', 'Tile shape', const {
            'LANDSCAPE': 'Landscape',
            'PORTRAIT': 'Portrait',
            'SQUARE': 'Square',
          }, fallback: 'LANDSCAPE'),
          _toggle(_draft, 'hideTitle', 'Hide title on cover', false),
          _text(_draft, 'heroBackdropUrl', 'Folder backdrop URL', url: true),
          _text(
            _draft,
            'heroVideoUrl',
            'Folder background video URL',
            url: true,
          ),
          _text(_draft, 'titleLogoUrl', 'Title logo URL', url: true),
          _text(_draft, 'focusGifUrl', 'Focus GIF URL', url: true),
          _toggle(_draft, 'focusGifEnabled', 'Play focus GIF', true),
          _text(_draft, 'focusVideoUrl', 'Focus video URL', url: true),
          _toggle(_draft, 'focusVideoEnabled', 'Play focus video', true),
          const SizedBox(height: 20),
          const Text(
            'Sources',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          for (var i = 0; i < _sources.length; i++)
            _orderedTile(
              title: '${_sources[i].label} · ${_sources[i].provider}',
              index: i,
              values: _sources,
              onEdit: () => _editSource(i),
              onChanged: () => setState(() {}),
            ),
          OutlinedButton.icon(
            onPressed: () => _editSource(),
            icon: const Icon(Icons.add),
            label: const Text('Add source'),
          ),
        ],
      ),
    ),
  );
}

class _SourceEditor extends StatefulWidget {
  const _SourceEditor({this.source, required this.addons});
  final CollectionCatalogSource? source;
  final List<StremioAddon> addons;
  @override
  State<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<_SourceEditor> {
  late Map<String, dynamic> _draft = widget.source == null
      ? {'provider': 'tmdb', 'tmdbSourceType': 'DISCOVER', 'mediaType': 'MOVIE'}
      : jsonDecode(
          jsonEncode({
            ...widget.source!.toJson(),
            'provider': widget.source!.provider,
          }),
        );
  final _form = GlobalKey<FormState>();
  String get _provider => _draft['provider'] as String;
  int _generation = 0;

  void _save() {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    final source = CollectionCatalogSource.fromJson(_draft);
    if (source != null) Navigator.of(context).pop(source);
  }

  static const _filters = <String, String>{
    'withGenres': 'Include genre IDs',
    'withoutGenres': 'Exclude genre IDs',
    'releaseDateGte': 'Released from (YYYY-MM-DD)',
    'releaseDateLte': 'Released through (YYYY-MM-DD)',
    'voteAverageGte': 'Minimum rating (0–10)',
    'voteAverageLte': 'Maximum rating (0–10)',
    'voteCountGte': 'Minimum vote count',
    'withOriginalLanguage': 'Original language code',
    'withOriginCountry': 'Origin country code',
    'withKeywords': 'Include keyword IDs',
    'withoutKeywords': 'Exclude keyword IDs',
    'withCompanies': 'Include company IDs',
    'withoutCompanies': 'Exclude company IDs',
    'withNetworks': 'Network IDs',
    'year': 'Release year',
    'watchRegion': 'Watch region code',
    'withWatchProviders': 'Include streaming provider IDs',
    'withoutWatchProviders': 'Exclude streaming provider IDs',
  };

  @override
  Widget build(BuildContext context) {
    final filters =
        (_draft['filters'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    final addon = widget.addons
        .where((a) => (a.manifestId ?? a.id) == _draft['addonId'])
        .firstOrNull;
    final providerChoices = <String, String>{
      'addon': 'Installed addon',
      'tmdb': 'TMDB',
      'trakt': 'Public Trakt list',
      if (!const ['addon', 'tmdb', 'trakt'].contains(_provider))
        _provider: _provider,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit source'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: _EditorBody(
          key: ValueKey(_generation),
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _provider,
              decoration: const InputDecoration(labelText: 'Source'),
              items: [
                for (final e in providerChoices.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (value) {
                if (value == null || value == _provider) return;
                setState(() {
                  _draft = {
                    'provider': value,
                    'title': _draft['title'],
                    'tmdbSourceType': 'DISCOVER',
                    'mediaType': 'MOVIE',
                  };
                  _generation++;
                });
              },
            ),
            _text(_draft, 'title', 'List title'),
            if (_provider == 'addon') ...[
              if (widget.addons.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: addon?.manifestId ?? addon?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Installed addon',
                  ),
                  items: [
                    for (final id
                        in widget.addons
                            .map((a) => a.manifestId ?? a.id)
                            .toSet())
                      DropdownMenuItem(
                        value: id,
                        child: Text(
                          widget.addons
                              .firstWhere((a) => (a.manifestId ?? a.id) == id)
                              .name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    _form.currentState!.save();
                    setState(() {
                      _draft['addonId'] = value;
                      _generation++;
                    });
                  },
                ),
              _text(_draft, 'addonId', 'Addon ID', required: true),
              if (addon != null && addon.catalogs.any((c) => c.isBrowsable))
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Choose configured catalog',
                  ),
                  items: [
                    for (final c in addon.catalogs.where((c) => c.isBrowsable))
                      DropdownMenuItem(
                        value: '${c.type}\u0000${c.id}',
                        child: Text(
                          '${c.name} · ${c.type}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _form.currentState!.save();
                    final parts = value.split('\u0000');
                    setState(() {
                      _draft['type'] = parts[0];
                      _draft['catalogId'] = parts[1];
                      _generation++;
                    });
                  },
                ),
              _text(_draft, 'catalogId', 'Catalog ID', required: true),
              _text(_draft, 'type', 'Catalog type', required: true),
              _text(_draft, 'genre', 'Genre (optional)'),
            ] else if (_provider == 'tmdb' || _provider == 'trakt') ...[
              _choice(_draft, 'mediaType', 'Media type', const {
                'MOVIE': 'Movies',
                'TV': 'Series',
              }, fallback: 'MOVIE'),
              if (_provider == 'tmdb') ...[
                _choice(
                  _draft,
                  'tmdbSourceType',
                  'TMDB source',
                  const {
                    'DISCOVER': 'Discover with filters',
                    'LIST': 'List',
                    'COLLECTION': 'Movie franchise',
                    'COMPANY': 'Production company',
                    'NETWORK': 'TV network',
                    'PERSON': 'Actor credits',
                    'DIRECTOR': 'Director credits',
                  },
                  fallback: 'DISCOVER',
                  onChanged: () => setState(() {}),
                ),
                _text(
                  _draft,
                  'tmdbId',
                  'TMDB ID',
                  integer: true,
                  required: _draft['tmdbSourceType'] != 'DISCOVER',
                ),
                _choice(_draft, 'sortBy', 'Sort by', const {
                  'original': 'Original order',
                  'popularity.desc': 'Popularity',
                  'vote_average.desc': 'Rating',
                  'vote_count.desc': 'Vote count',
                  'primary_release_date.desc': 'Newest movies',
                  'first_air_date.desc': 'Newest series',
                }, fallback: 'popularity.desc'),
                if (const [
                  'DISCOVER',
                  'COMPANY',
                  'NETWORK',
                ].contains(_draft['tmdbSourceType'])) ...[
                  const SizedBox(height: 16),
                  const Text('Filters (optional)'),
                  const Text(
                    'Separate IDs with commas for AND, or | for OR where supported by TMDB.',
                  ),
                  for (final e in _filters.entries)
                    _text(
                      filters,
                      e.key,
                      e.value,
                      integer: e.key == 'year' || e.key == 'voteCountGte',
                      decimal: e.key.startsWith('voteAverage'),
                    ),
                ],
              ] else ...[
                _text(
                  _draft,
                  'traktListId',
                  'Trakt list ID',
                  required: true,
                  integer: true,
                ),
                _choice(_draft, 'sortBy', 'Sort by', const {
                  'rank': 'List order',
                  'added': 'Date added',
                  'title': 'Title',
                  'released': 'Release date',
                  'runtime': 'Runtime',
                  'popularity': 'Popularity',
                  'percentage': 'Rating',
                  'votes': 'Vote count',
                }, fallback: 'rank'),
                _choice(_draft, 'sortHow', 'Direction', const {
                  'asc': 'Ascending',
                  'desc': 'Descending',
                }, fallback: 'asc'),
              ],
            ] else
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'This provider is not supported. Its data will be preserved; choose a supported source to replace it.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Form fields must remain registered even after scrolling away, so Save
/// validates and normalizes the whole draft rather than only visible fields.
class _EditorBody extends StatelessWidget {
  const _EditorBody({super.key, required this.padding, required this.children});
  final EdgeInsets padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

String _id(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';

Widget _text(
  Map<String, dynamic> values,
  String key,
  String label, {
  bool required = false,
  bool url = false,
  bool integer = false,
  bool decimal = false,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: TextFormField(
    initialValue: values[key]?.toString() ?? '',
    decoration: InputDecoration(labelText: label),
    keyboardType: url
        ? TextInputType.url
        : integer || decimal
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    onChanged: (value) => values[key] = value.trim(),
    validator: (raw) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) return required ? 'Enter $label' : null;
      if (url) {
        final uri = Uri.tryParse(value);
        if (uri == null ||
            !const ['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          return 'Enter an HTTP or HTTPS URL';
        }
      }
      if (integer &&
          (int.tryParse(value) == null ||
              int.parse(value) < (key.endsWith('Id') ? 1 : 0))) {
        return 'Enter a valid whole number';
      }
      if (decimal &&
          (double.tryParse(value) == null ||
              !double.parse(value).isFinite ||
              double.parse(value) < 0 ||
              double.parse(value) > 10)) {
        return 'Enter a rating from 0 to 10';
      }
      if (key.startsWith('releaseDate') &&
          (DateTime.tryParse(value)?.toIso8601String().substring(0, 10) !=
                  value ||
              !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value))) {
        return 'Use YYYY-MM-DD';
      }
      return null;
    },
    onSaved: (raw) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) {
        values.remove(key);
      } else {
        values[key] = integer
            ? int.parse(value)
            : decimal
            ? double.parse(value)
            : value;
      }
    },
  ),
);

Widget _choice(
  Map<String, dynamic> values,
  String key,
  String label,
  Map<String, String> options, {
  String fallback = '',
  VoidCallback? onChanged,
}) {
  final value = values[key] as String? ?? fallback;
  final choices = {...options, if (!options.containsKey(value)) value: value};
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in choices.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (value) {
        if (value != null) {
          values[key] = value;
          onChanged?.call();
        }
      },
      onSaved: (value) {
        if (value != null && value.isNotEmpty) {
          values[key] = value;
        } else {
          values.remove(key);
        }
      },
    ),
  );
}

Widget _toggle(
  Map<String, dynamic> values,
  String key,
  String title,
  bool fallback,
) => StatefulBuilder(
  builder: (context, update) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    value: values[key] as bool? ?? fallback,
    onChanged: (value) => update(() => values[key] = value),
  ),
);

Widget _orderedTile<T>({
  required String title,
  required int index,
  required List<T> values,
  required VoidCallback onEdit,
  required VoidCallback onChanged,
}) => Column(
  key: ValueKey(values[index]),
  children: [
    ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      onTap: onEdit,
      trailing: const Icon(Icons.edit_outlined),
    ),
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Move up',
          onPressed: index == 0
              ? null
              : () {
                  final item = values.removeAt(index);
                  values.insert(index - 1, item);
                  onChanged();
                },
          icon: const Icon(Icons.arrow_upward),
        ),
        IconButton(
          tooltip: 'Move down',
          onPressed: index == values.length - 1
              ? null
              : () {
                  final item = values.removeAt(index);
                  values.insert(index + 1, item);
                  onChanged();
                },
          icon: const Icon(Icons.arrow_downward),
        ),
        IconButton(
          tooltip: 'Remove',
          onPressed: () {
            values.removeAt(index);
            onChanged();
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  ],
);
