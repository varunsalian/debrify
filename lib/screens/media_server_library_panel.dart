import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/media_server.dart';
import '../models/media_server_library.dart';
import '../models/profiles/connection_resource.dart';
import '../models/torrent.dart';
import '../services/media_server_library_playback.dart';
import '../services/media_server_service.dart';
import '../services/profiles/profile_runtime.dart';
import '../services/video_player_launcher.dart';
import '../theme/app_theme_scope.dart';
import '../widgets/see_all/stremio_dropdown.dart';
import '../widgets/tv_text_field.dart';
import 'settings/media_server_settings_page.dart';

/// Embedded Discover browser. Pages and authenticated artwork stay in memory.
class MediaServerLibraryPanel extends StatefulWidget {
  const MediaServerLibraryPanel({
    super.key,
    required this.kind,
    required this.leading,
    this.isTelevision = false,
    this.connectionLoader,
    this.sessionLoader,
  });
  final MediaServerKind kind;
  final Widget leading;
  final bool isTelevision;
  final Future<List<ConnectionResource>> Function()? connectionLoader;
  final Future<MediaServerLibraryAccess> Function(String)? sessionLoader;

  @override
  State<MediaServerLibraryPanel> createState() =>
      _MediaServerLibraryPanelState();
}

class _MediaServerLibraryPanelState extends State<MediaServerLibraryPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _gridFocus = FocusNode(debugLabel: 'media-library-grid');
  List<ConnectionResource> _servers = [];
  List<MediaServerLibraryItem> _libraries = [];
  final _trail = <MediaServerLibraryItem>[];
  MediaServerLibraryAccess? _session;
  String? _serverId;
  String? _libraryId;
  String _mode = 'browse';
  String _sort = 'SortName';
  String _query = '';
  MediaServerLibraryPage? _page;
  final _offsets = <int>[0];
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    ProfileRuntime.scope.addListener(_profileChanged);
    _loadServers();
  }

  @override
  void dispose() {
    ProfileRuntime.scope.removeListener(_profileChanged);
    _generation++;
    _search.dispose();
    _scroll.dispose();
    _gridFocus.dispose();
    super.dispose();
  }

  void _profileChanged() {
    _generation++;
    setState(() {
      _session = null;
      _servers = [];
      _libraries = [];
      _page = null;
      _serverId = null;
      _libraryId = null;
      _trail.clear();
      _query = '';
      _search.clear();
      _offsets
        ..clear()
        ..add(0);
    });
    _loadServers();
  }

  String _message(Object error) => error is MediaServerException
      ? error.message
      : 'Could not access this library. Test or reconnect the server in Settings.';

  Future<void> _loadServers() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _page = null;
      _session = null;
      _servers = [];
      _libraries = [];
      _serverId = null;
      _libraryId = null;
      _trail.clear();
    });
    try {
      final servers =
          await (widget.connectionLoader?.call() ??
              MediaServerService.libraryConnections(widget.kind));
      if (!mounted || generation != _generation) return;
      setState(() {
        _servers = servers;
        _loading = false;
      });
      if (servers.isNotEmpty) await _selectServer(servers.first.id);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _message(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectServer(String id) async {
    final generation = ++_generation;
    setState(() {
      _serverId = id;
      _session = null;
      _libraries = [];
      _libraryId = null;
      _trail.clear();
      _page = null;
      _loading = true;
      _error = null;
      _query = '';
      _search.clear();
      _offsets
        ..clear()
        ..add(0);
    });
    try {
      final session =
          await (widget.sessionLoader?.call(id) ??
              MediaServerService.openLibrary(id));
      if (session.kind != widget.kind) {
        throw const MediaServerException(
          'This connection has changed. Refresh the server list.',
        );
      }
      final views = await session.browse(views: true);
      if (!mounted || generation != _generation) return;
      final libraries = views.items
          .where(
            (item) => !const {
              'music',
              'books',
              'photos',
              'games',
              'livetv',
              'channels',
            }.contains(item.data['CollectionType']),
          )
          .toList();
      setState(() {
        _session = session;
        _libraries = libraries;
        _libraryId = libraries.isEmpty ? null : libraries.first.id;
        _loading = false;
      });
      if (_libraryId != null) await _loadPage();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _message(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadPage({bool reset = true}) async {
    final session = _session;
    if (session == null || _libraryId == null) return;
    final generation = ++_generation;
    setState(() {
      if (reset) {
        _offsets
          ..clear()
          ..add(0);
      }
      _loading = true;
      _error = null;
      _page = null;
    });
    try {
      final parent = _trail.isEmpty ? null : _trail.last;
      final page = await session.browse(
        parentId: parent?.id ?? _libraryId,
        offset: _offsets.last,
        search: _query,
        sort: _sort,
        mode: _mode,
        episodeOrder: parent?.type == 'Series' || parent?.type == 'Season',
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = page;
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _message(error);
          _loading = false;
        });
      }
    }
  }

  void _back() {
    if (_trail.isEmpty) return;
    setState(() {
      _trail.removeLast();
      _query = '';
      _search.clear();
    });
    _loadPage();
  }

  void _open(MediaServerLibraryItem item) async {
    if (item.isFolder) {
      setState(() {
        _trail.add(item);
        _mode = 'browse';
        _query = '';
        _search.clear();
      });
      await _loadPage();
    } else if (item.playable && _session != null) {
      final session = _session!;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              _MediaServerItemScreen(session: session, initial: item),
        ),
      );
      if (mounted) _loadPage(reset: false);
    }
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MediaServerSettingsPage()),
    );
    if (mounted) _loadServers();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final items =
        _page?.items.where((item) => item.isFolder || item.playable).toList() ??
        [];
    final hasBack = _trail.isNotEmpty;
    return PopScope(
      canPop: !hasBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && hasBack) _back();
      },
      child: ColoredBox(
        color: app.home.bg,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  widget.leading,
                  if (_servers.isNotEmpty)
                    StremioDropdown<String>(
                      label: 'Server',
                      value: _serverId ?? _servers.first.id,
                      isTelevision: widget.isTelevision,
                      options: [
                        for (final s in _servers)
                          StremioDropdownOption(s.id, s.label),
                      ],
                      onSelected: _selectServer,
                    ),
                  if (_libraries.isNotEmpty)
                    StremioDropdown<String>(
                      label: 'Library',
                      value: _libraryId ?? _libraries.first.id,
                      isTelevision: widget.isTelevision,
                      options: [
                        for (final l in _libraries)
                          StremioDropdownOption(l.id, l.name),
                      ],
                      onSelected: (value) {
                        setState(() {
                          _libraryId = value;
                          _trail.clear();
                          _query = '';
                          _search.clear();
                        });
                        _loadPage();
                      },
                    ),
                  if (_session != null && _libraryId != null) ...[
                    StremioDropdown<String>(
                      label: 'Show',
                      value: _mode,
                      isTelevision: widget.isTelevision,
                      options: const [
                        StremioDropdownOption('browse', 'Library'),
                        StremioDropdownOption('recent', 'Recently added'),
                        StremioDropdownOption('resume', 'Continue watching'),
                      ],
                      onSelected: (value) {
                        setState(() {
                          _mode = value;
                          _trail.clear();
                        });
                        _loadPage();
                      },
                    ),
                    if (_mode == 'browse')
                      StremioDropdown<String>(
                        label: 'Sort',
                        value: _sort,
                        isTelevision: widget.isTelevision,
                        options: const [
                          StremioDropdownOption('SortName', 'Name A–Z'),
                          StremioDropdownOption('DateCreated', 'Newest added'),
                          StremioDropdownOption('ProductionYear', 'Year'),
                        ],
                        onSelected: (value) {
                          setState(() => _sort = value);
                          _loadPage();
                        },
                      ),
                  ],
                  IconButton(
                    tooltip: 'Refresh servers',
                    onPressed: _loadServers,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Manage servers',
                    onPressed: _settings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
            if (_session != null && _libraryId != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (hasBack)
                      IconButton(
                        tooltip: 'Back to parent',
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    Expanded(
                      child: Text(
                        _trail.map((item) => item.name).join(' / '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: app.core.tx),
                      ),
                    ),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width < 600 ? 170 : 280,
                      child: TvTextField(
                        controller: _search,
                        hintText: 'Search this library',
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) {
                          _query = value.trim();
                          _loadPage();
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Search library',
                      onPressed: () {
                        _query = _search.text.trim();
                        _loadPage();
                      },
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _notice(
                      _error!,
                      retry: () => _session == null
                          ? (_serverId == null
                                ? _loadServers()
                                : _selectServer(_serverId!))
                          : _loadPage(reset: false),
                    )
                  : _servers.isEmpty
                  ? _notice(
                      'Connect a ${widget.kind.label} server to browse its libraries.',
                      settings: true,
                    )
                  : _libraries.isEmpty
                  ? _notice(
                      'No video libraries are available for this server user.',
                      settings: true,
                    )
                  : items.isEmpty
                  ? _notice(
                      _mode == 'resume'
                          ? 'No partially watched videos in this library.'
                          : 'No matching videos or folders.',
                    )
                  : FocusTraversalGroup(
                      child: GridView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: widget.isTelevision ? 200 : 180,
                          childAspectRatio: 0.62,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) => _LibraryCard(
                          key: ValueKey(
                            '${_session!.resource.id}:${items[index].id}',
                          ),
                          item: items[index],
                          session: _session!,
                          focusNode: index == 0 ? _gridFocus : null,
                          onOpen: () => _open(items[index]),
                        ),
                      ),
                    ),
            ),
            if (!_loading &&
                _page != null &&
                (_offsets.length > 1 || _page!.nextOffset != null))
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _offsets.length > 1
                          ? () {
                              _offsets.removeLast();
                              _loadPage(reset: false);
                            }
                          : null,
                      child: const Text('Previous page'),
                    ),
                    Text(
                      'Page ${_offsets.length}',
                      style: TextStyle(color: app.core.tx),
                    ),
                    TextButton(
                      onPressed: _page!.nextOffset != null
                          ? () {
                              _offsets.add(_page!.nextOffset!);
                              _loadPage(reset: false);
                            }
                          : null,
                      child: const Text('Next page'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _notice(String text, {VoidCallback? retry, bool settings = false}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppThemeScope.of(context).core.tx),
              ),
              if (retry != null)
                TextButton(onPressed: retry, child: const Text('Retry')),
              if (settings)
                TextButton(
                  onPressed: _settings,
                  child: const Text('Manage servers'),
                ),
            ],
          ),
        ),
      );
}

class _LibraryCard extends StatefulWidget {
  const _LibraryCard({
    super.key,
    required this.item,
    required this.session,
    required this.onOpen,
    this.focusNode,
  });
  final MediaServerLibraryItem item;
  final MediaServerLibraryAccess session;
  final VoidCallback onOpen;
  final FocusNode? focusNode;
  @override
  State<_LibraryCard> createState() => _LibraryCardState();
}

class _LibraryCardState extends State<_LibraryCard> {
  bool _focused = false;
  late Future<Uint8List?> _image;
  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _LibraryCard old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session ||
        old.item.imageId != widget.item.imageId) {
      _loadImage();
    }
  }

  void _loadImage() {
    final id = widget.item.imageId;
    _image = id == null
        ? Future.value(null)
        : widget.session.image(id).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final item = widget.item;
    final placeholder = Center(
      child: Icon(
        item.isFolder ? Icons.folder_outlined : Icons.movie_outlined,
        size: 48,
        color: app.core.tx,
      ),
    );
    return Semantics(
      button: true,
      label: '${item.name}, ${item.subtitle}',
      child: Material(
        color: app.fade(app.core.tx, 0.06),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: widget.focusNode,
          onTap: widget.onOpen,
          onFocusChange: (value) {
            setState(() => _focused = value);
            if (value) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.5,
                duration: const Duration(milliseconds: 150),
              );
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? app.home.chromeAccent : Colors.transparent,
                width: 3,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder<Uint8List?>(
                        future: _image,
                        builder: (_, snapshot) => snapshot.data == null
                            ? placeholder
                            : Image.memory(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                cacheWidth: 360,
                                errorBuilder: (_, _, _) => placeholder,
                              ),
                      ),
                      if (item.watched)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            radius: 12,
                            child: Icon(Icons.check, size: 16),
                          ),
                        ),
                    ],
                  ),
                ),
                if (item.progress > 0)
                  LinearProgressIndicator(value: item.progress, minHeight: 3),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.core.tx,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.fade(app.core.tx, 0.65),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaServerItemScreen extends StatefulWidget {
  const _MediaServerItemScreen({required this.session, required this.initial});
  final MediaServerLibraryAccess session;
  final MediaServerLibraryItem initial;
  @override
  State<_MediaServerItemScreen> createState() => _MediaServerItemScreenState();
}

class _MediaServerItemScreenState extends State<_MediaServerItemScreen> {
  MediaServerLibraryItem? _item;
  List<Torrent>? _sources;
  String? _error;
  bool _busy = false;
  bool _loading = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    ProfileRuntime.scope.addListener(_changed);
    _load();
  }

  void _changed() {
    _generation++;
    if (mounted) {
      setState(() {
        _item = null;
        _sources = null;
        _loading = false;
        _error = 'Profile changed. Return to Discover.';
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    ProfileRuntime.scope.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _sources = null;
    });
    try {
      final item = await widget.session.item(widget.initial.id);
      final sources = await widget.session.sources(item);
      if (!mounted || generation != _generation) return;
      setState(() {
        _item = item;
        _sources = sources;
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error is MediaServerException
              ? error.message
              : 'Could not load this item. Test or reconnect the server in Settings.';
        });
      }
    }
  }

  Future<void> _play(int index) async {
    if (_busy || _sources == null || _item == null) return;
    setState(() => _busy = true);
    final generation = _generation;
    try {
      final sources = _sources!;
      final item = _item!;
      await widget.session.authorize();
      await MediaServerService.authorize(sources[index]);
      if (!mounted || generation != _generation) return;
      await VideoPlayerLauncher.push(
        context,
        MediaServerLibraryPlayback.arguments(
          sources,
          index,
          title: item.numberedEpisode ? item.seriesName : item.name,
        ),
      );
      if (mounted && generation == _generation) await _load();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is MediaServerException
              ? error.message
              : 'Playback could not start. Refresh this item or reconnect the server.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: app.home.bg,
      appBar: AppBar(title: Text(_item?.name ?? 'Server video')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_item != null) ...[
                  Text(_item!.subtitle, style: TextStyle(color: app.core.tx)),
                  const SizedBox(height: 12),
                  if (_item!.overview.isNotEmpty)
                    Text(_item!.overview, style: TextStyle(color: app.core.tx)),
                  const SizedBox(height: 20),
                ],
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: app.core.tx)),
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Retry'),
                  ),
                ],
                if (_sources != null) ...[
                  Text(
                    'Play from ${widget.session.resource.label}',
                    style: TextStyle(color: app.core.tx, fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _sources!.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _play(i),
                        icon: const Icon(Icons.play_arrow),
                        label: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _sources![i].streamDescription ?? 'Original',
                          ),
                        ),
                      ),
                    ),
                ],
                if (_busy) const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
