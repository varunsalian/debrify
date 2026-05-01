import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/playlist_view_mode.dart';
import '../../models/webdav_item.dart';
import '../../screens/video_player/models/playlist_entry.dart';
import '../../services/download_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/webdav_service.dart';
import '../../utils/file_utils.dart';
import '../../utils/formatters.dart';
import '../../utils/series_parser.dart';
import '../debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../settings/webdav_settings_page.dart';

class WebDavFilesScreen extends StatefulWidget {
  const WebDavFilesScreen({super.key});

  @override
  State<WebDavFilesScreen> createState() => _WebDavFilesScreenState();
}

class _WebDavFilesScreenState extends State<WebDavFilesScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _firstItemFocusNode = FocusNode(debugLabel: 'webdav-first-item');
  final _refreshFocusNode = FocusNode(debugLabel: 'webdav-refresh');
  final _settingsFocusNode = FocusNode(debugLabel: 'webdav-settings');
  final _searchFocusNode = FocusNode(debugLabel: 'webdav-search');
  final _searchToggleFocusNode = FocusNode(debugLabel: 'webdav-search-toggle');
  final _serverDropdownFocusNode = FocusNode(
    debugLabel: 'webdav-server-dropdown',
  );

  WebDavConfig? _config;
  List<WebDavConfig> _configs = [];
  List<WebDavItem> _rawItems = [];
  List<WebDavItem> _items = [];
  final List<({String path, String title})> _stack = [];
  final Map<String, List<WebDavItem>> _virtualFolders = {};
  String _currentPath = '';
  String _currentTitle = 'WebDAV';
  bool _loading = true;
  bool _showVideosOnly = true;
  String _error = '';
  String _query = '';
  bool _searchActive = false;
  VoidCallback? _tvContentFocusHandler;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndRoot();
    MainPageBridge.registerTabBackHandler('webdav', _handleBackNavigation);
    _tvContentFocusHandler = () {
      if (_items.isNotEmpty) {
        _firstItemFocusNode.requestFocus();
      } else {
        _refreshFocusNode.requestFocus();
      }
    };
    MainPageBridge.registerTvContentFocusHandler(10, _tvContentFocusHandler!);
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTabBackHandler('webdav');
    if (_tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        10,
        _tvContentFocusHandler!,
      );
    }
    _scrollController.dispose();
    _searchController.dispose();
    _firstItemFocusNode.dispose();
    _refreshFocusNode.dispose();
    _settingsFocusNode.dispose();
    _searchFocusNode.dispose();
    _searchToggleFocusNode.dispose();
    _serverDropdownFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndRoot() async {
    final configs = await WebDavService.getConfigs();
    final config = await WebDavService.getConfig();
    final showVideosOnly = await StorageService.getWebDavShowVideosOnly();
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _config = config;
      _showVideosOnly = showVideosOnly;
    });
    if (config == null) {
      setState(() {
        _loading = false;
        _error = 'Connect WebDAV in Settings first.';
      });
      return;
    }
    await _loadPath('', title: 'WebDAV', replaceStack: true);
  }

  Future<void> _loadPath(
    String path, {
    required String title,
    bool replaceStack = false,
  }) async {
    final config = _config;
    if (config == null) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final rawItems = await WebDavService.listDirectory(
        config: config,
        path: path,
      );
      if (!mounted) return;
      setState(() {
        if (replaceStack) _stack.clear();
        _currentPath = path;
        _currentTitle = title;
        _rawItems = rawItems;
        _items = _applyViewMode(_filterVisible(_rawItems));
        _loading = false;
      });
      _focusFirstItem();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  bool _handleBackNavigation() {
    if (_searchActive) {
      _closeSearch();
      return true;
    }
    if (_stack.isEmpty) return false;
    final previous = _stack.removeLast();
    _loadPath(previous.path, title: previous.title);
    return true;
  }

  void _focusFirstItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_items.isNotEmpty) {
        _firstItemFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    setState(() {
      _searchActive = false;
      _query = '';
      _searchController.clear();
      _items = _applyViewMode(_filterVisible(_rawItems));
    });
  }

  void _toggleSearch() {
    if (_searchActive) {
      _closeSearch();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _serverDropdownFocusNode.requestFocus();
      });
      return;
    }

    setState(() {
      _searchActive = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  bool _hasWebDavCredentials(WebDavConfig config) {
    return config.username.isNotEmpty || config.password.isNotEmpty;
  }

  Future<void> _openWebDavPlayer(
    WebDavConfig config,
    VideoPlayerLaunchArgs args,
  ) async {
    if (_hasWebDavCredentials(config)) {
      // Authenticated WebDAV streams need HTTP headers; external/TV handoff
      // paths can drop them, so use the in-app player where headers are honored.
      await Navigator.of(context).push<Map<String, dynamic>?>(
        MaterialPageRoute(builder: (_) => args.toWidget()),
      );
      return;
    }

    await VideoPlayerLauncher.push(context, args);
  }

  List<WebDavItem> _filterVisible(List<WebDavItem> items) {
    final filtered = _showVideosOnly
        ? items
              .where(
                (item) => item.isDirectory || FileUtils.isVideoFile(item.name),
              )
              .toList()
        : List<WebDavItem>.from(items);
    if (_query.trim().isEmpty) return filtered;
    final q = _query.toLowerCase();
    return filtered
        .where((item) => item.name.toLowerCase().contains(q))
        .toList();
  }

  List<WebDavItem> _applyViewMode(List<WebDavItem> items) {
    _virtualFolders.clear();
    return items;
  }

  List<WebDavItem> _sortItems(List<WebDavItem> items) {
    final copy = List<WebDavItem>.from(items);
    copy.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      final aInfo = SeriesParser.parseFilename(a.name);
      final bInfo = SeriesParser.parseFilename(b.name);
      final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      final episodeCompare = (aInfo.episode ?? 0).compareTo(bInfo.episode ?? 0);
      if (episodeCompare != 0) return episodeCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return copy;
  }

  Future<void> _refresh() async {
    if (_currentPath.startsWith('virtual:')) {
      setState(() {
        _items = _applyViewMode(_filterVisible(_rawItems));
      });
      return;
    }
    await _loadPath(_currentPath, title: _currentTitle);
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WebDavSettingsPage()));
    if (!mounted) return;
    await _loadSettingsAndRoot();
  }

  Future<void> _selectConfig(String id) async {
    await StorageService.setSelectedWebDavServerId(id);
    WebDavConfig? selected;
    for (final config in _configs) {
      if (config.id == id) {
        selected = config;
        break;
      }
    }
    if (!mounted || selected == null) return;
    setState(() {
      _config = selected;
      _stack.clear();
      _currentPath = '';
      _currentTitle = 'WebDAV';
      _query = '';
      _searchController.clear();
      _searchActive = false;
    });
    await _loadPath('', title: 'WebDAV', replaceStack: true);
  }

  void _openFolder(WebDavItem item) {
    if (_virtualFolders.containsKey(item.path)) {
      _stack.add((path: _currentPath, title: _currentTitle));
      setState(() {
        _currentPath = item.path;
        _currentTitle = item.name;
        _rawItems = _virtualFolders[item.path] ?? const [];
        _items = _rawItems;
      });
      _focusFirstItem();
      return;
    }
    _stack.add((path: _currentPath, title: _currentTitle));
    _loadPath(item.path, title: item.name);
  }

  Future<void> _playItem(WebDavItem item) async {
    if (item.isDirectory) {
      await _playFolder(item);
      return;
    }
    final config = _config;
    if (config == null) return;
    await _openWebDavPlayer(
      config,
      VideoPlayerLaunchArgs(
        videoUrl: WebDavService.directUrl(config, item.path),
        title: item.name,
        subtitle: item.sizeBytes != null
            ? Formatters.formatFileSize(item.sizeBytes!)
            : null,
        viewMode: PlaylistViewMode.sorted,
        httpHeaders: WebDavService.authHeaders(config),
      ),
    );
  }

  Future<void> _playFolder(WebDavItem folder) async {
    final config = _config;
    if (config == null) return;
    try {
      _showLoading('Preparing playlist...');
      final files =
          _virtualFolders[folder.path] ??
          await WebDavService.collectVideoFiles(config: config, folder: folder);
      if (mounted) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      if (files.isEmpty) {
        _showSnack('No video files found in this folder', error: true);
        return;
      }
      final sorted = _sortItems(files);
      final names = sorted.map((e) => e.name).toList();
      final isSeries =
          sorted.length > 1 && SeriesParser.isSeriesPlaylist(names);
      final playlist = sorted.map((file) {
        return PlaylistEntry(
          url: WebDavService.directUrl(config, file.path),
          title: file.name,
          relativePath: file.path,
          sizeBytes: file.sizeBytes,
          provider: 'webdav',
        );
      }).toList();
      await _openWebDavPlayer(
        config,
        VideoPlayerLaunchArgs(
          videoUrl: playlist.first.url,
          title: folder.name,
          subtitle: '${playlist.length} videos',
          playlist: playlist,
          startIndex: 0,
          viewMode: isSeries
              ? PlaylistViewMode.series
              : PlaylistViewMode.sorted,
          httpHeaders: WebDavService.authHeaders(config),
        ),
      );
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _addItemToPlaylist(WebDavItem item) async {
    final config = _config;
    if (config == null) return;

    if (item.isDirectory) {
      await _addFolderToPlaylist(config, item);
      return;
    }

    await _addFileToPlaylist(config, item);
  }

  Future<void> _addFileToPlaylist(WebDavConfig config, WebDavItem file) async {
    if (!FileUtils.isVideoFile(file.name)) {
      _showSnack('Only video files can be added to playlist', error: true);
      return;
    }

    try {
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'webdav',
        'title': FileUtils.cleanPlaylistTitle(file.name),
        'kind': 'single',
        'webdavServerId': config.id,
        'webdavServerName': config.name,
        'webdavPath': file.path,
        'webdavFile': _playlistFileData(file),
        'sizeBytes': file.sizeBytes,
      });

      _showSnack(
        added ? 'Added to playlist' : 'Already in playlist',
        error: !added,
      );
    } catch (e) {
      _showSnack('Failed to add to playlist: ${e.toString()}', error: true);
    }
  }

  Future<void> _addFolderToPlaylist(
    WebDavConfig config,
    WebDavItem folder,
  ) async {
    try {
      _showLoading('Scanning folder for videos...');
      final files =
          _virtualFolders[folder.path] ??
          await WebDavService.collectVideoFiles(config: config, folder: folder);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;

      if (files.isEmpty) {
        _showSnack('This folder does not contain any videos', error: true);
        return;
      }

      final sorted = _sortItems(files);
      if (sorted.length == 1) {
        await _addFileToPlaylist(config, sorted.first);
        return;
      }

      final totalBytes = sorted.fold<int>(
        0,
        (sum, file) => sum + (file.sizeBytes ?? 0),
      );
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'webdav',
        'title': FileUtils.cleanPlaylistTitle(folder.name),
        'kind': 'collection',
        'webdavServerId': config.id,
        'webdavServerName': config.name,
        'webdavFolderPath': folder.path,
        'webdavFiles': sorted.map(_playlistFileData).toList(),
        'count': sorted.length,
        'totalBytes': totalBytes,
      });

      _showSnack(
        added
            ? 'Added ${sorted.length} videos to playlist'
            : 'Already in playlist',
        error: !added,
      );
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showSnack('Failed to add to playlist: ${e.toString()}', error: true);
    }
  }

  Map<String, dynamic> _playlistFileData(WebDavItem item) {
    return {
      'name': item.name,
      'path': item.path,
      'sizeBytes': item.sizeBytes,
      'contentType': item.contentType,
      'modifiedAt': item.modifiedAt?.toIso8601String(),
    };
  }

  Future<void> _downloadItem(WebDavItem item) async {
    final config = _config;
    if (config == null) return;
    try {
      if (item.isDirectory) {
        _showLoading('Collecting files...');
        final files = await WebDavService.collectFiles(
          config: config,
          folder: item,
        );
        final visibleFiles = _showVideosOnly
            ? files.where((f) => FileUtils.isVideoFile(f.name)).toList()
            : files;
        if (mounted) {
          Navigator.of(context).pop();
        }
        if (visibleFiles.isEmpty) {
          _showSnack('No downloadable files found', error: true);
          return;
        }
        for (final file in visibleFiles) {
          await _queueDownload(config, file, parentFolder: item);
        }
        _showSnack('Queued ${visibleFiles.length} downloads');
      } else {
        await _queueDownload(config, item);
        _showSnack('Download queued: ${item.name}');
      }
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _queueDownload(
    WebDavConfig config,
    WebDavItem file, {
    WebDavItem? parentFolder,
  }) async {
    final relativeDir = parentFolder == null
        ? null
        : _relativeDirectoryForDownload(parentFolder, file);
    final meta = jsonEncode({
      'webdavDownload': true,
      'webdavPath': file.path,
      if (relativeDir != null && relativeDir.isNotEmpty)
        'webdavRelativeDir': relativeDir,
      'sizeBytes': file.sizeBytes,
    });
    await DownloadService.instance.enqueueDownload(
      url: WebDavService.directUrl(config, file.path),
      fileName: file.name,
      headers: WebDavService.authHeaders(config),
      meta: meta,
      torrentName: parentFolder?.name,
      relativeSubDir: relativeDir,
      context: context,
    );
  }

  String? _relativeDirectoryForDownload(WebDavItem parent, WebDavItem file) {
    final parentPath = parent.path.replaceFirst(RegExp(r'/+$'), '');
    final filePath = file.path.replaceFirst(RegExp(r'/+$'), '');
    if (parentPath.isEmpty || !filePath.startsWith('$parentPath/')) {
      return null;
    }
    final relativePath = filePath.substring(parentPath.length + 1);
    final lastSlash = relativePath.lastIndexOf('/');
    if (lastSlash <= 0) return null;
    return relativePath.substring(0, lastSlash);
  }

  Future<void> _deleteItem(WebDavItem item) async {
    final config = _config;
    if (config == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${item.isDirectory ? 'folder' : 'file'}?'),
        content: Text(item.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await WebDavService.delete(config: config, item: item);
      _showSnack('Deleted ${item.name}');
      await _refresh();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _showLoading(String text) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF334155).withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          if (_stack.isNotEmpty)
            Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                    MainPageBridge.focusTvSidebar != null) {
                  MainPageBridge.focusTvSidebar!();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: IconButton(
                onPressed: _handleBackNavigation,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                tooltip: 'Back',
              ),
            ),
          Expanded(child: _buildServerAndSearch()),
          const SizedBox(width: 8),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft):
                  _focusFromSearchToggleLeft,
              const SingleActivator(LogicalKeyboardKey.arrowDown):
                  _focusFirstItem,
              const SingleActivator(LogicalKeyboardKey.select): _toggleSearch,
              const SingleActivator(LogicalKeyboardKey.enter): _toggleSearch,
            },
            child: _buildToolbarIconButton(
              focusNode: _searchToggleFocusNode,
              onKeyEvent: _handleSearchToggleKey,
              onTap: _toggleSearch,
              icon: _searchActive ? Icons.close_rounded : Icons.search_rounded,
              tooltip: _searchActive ? 'Close search' : 'Search',
            ),
          ),
          IconButton(
            focusNode: _refreshFocusNode,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
          ),
          IconButton(
            focusNode: _settingsFocusNode,
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildServerAndSearch() {
    if (_searchActive) {
      return Focus(
        onKeyEvent: _handleSearchFieldKey,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (_) => _focusFirstItem(),
          onChanged: (value) {
            setState(() {
              _query = value;
              _items = _applyViewMode(_filterVisible(_rawItems));
            });
          },
          decoration: InputDecoration(
            hintText: 'Search $_currentTitle',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFFA5B4FC),
            ),
            filled: true,
            fillColor: const Color(0xFF111827),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: const Color(0xFF334155).withValues(alpha: 0.8),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFFA5B4FC),
                width: 1.6,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.arrowLeft) {
                MainPageBridge.focusTvSidebar?.call();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowRight) {
                _searchToggleFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: DropdownButtonFormField<String>(
              focusNode: _serverDropdownFocusNode,
              value: _config?.id,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E1B4B),
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.cloud_sync_rounded,
                  color: Color(0xFFA5B4FC),
                ),
                filled: true,
                fillColor: const Color(0xFF2D2578),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.7),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.42),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFFA5B4FC),
                    width: 1.6,
                  ),
                ),
              ),
              items: [
                for (final config in _configs)
                  DropdownMenuItem(value: config.id, child: Text(config.name)),
              ],
              onChanged: (id) {
                if (id != null) _selectConfig(id);
              },
            ),
          ),
        ),
      ],
    );
  }

  KeyEventResult _handleSearchFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final textLength = _searchController.text.length;
    final selection = _searchController.selection;
    final isTextEmpty = textLength == 0;
    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart =
        !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd =
        !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    if (key == LogicalKeyboardKey.arrowLeft && (isTextEmpty || isAtStart)) {
      MainPageBridge.focusTvSidebar?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && (isTextEmpty || isAtEnd)) {
      _searchToggleFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && (isTextEmpty || isAtEnd)) {
      _focusFirstItem();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _handleBackNavigation();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSearchToggleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _focusFromSearchToggleLeft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusFirstItem();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _toggleSearch();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _focusFromSearchToggleLeft() {
    if (_searchActive) {
      _searchFocusNode.requestFocus();
    } else {
      _serverDropdownFocusNode.requestFocus();
    }
  }

  Widget _buildToolbarIconButton({
    required FocusNode focusNode,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent,
  }) {
    return Tooltip(
      message: tooltip,
      child: Focus(
        focusNode: focusNode,
        onKeyEvent: onKeyEvent,
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: focused ? const Color(0xFF312E81) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: focused
                      ? Border.all(color: const Color(0xFFA5B4FC), width: 1.4)
                      : null,
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Open WebDAV Settings'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No files found'));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return TvFocusScrollWrapper(child: _buildItemCard(item, index));
      },
    );
  }

  Widget _buildItemCard(WebDavItem item, int index) {
    final isVideo = !item.isDirectory && FileUtils.isVideoFile(item.name);
    final canOpen = item.isDirectory;
    final canPlay = item.isDirectory || isVideo;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.isDirectory
                      ? Icons.folder_rounded
                      : Icons.insert_drive_file_rounded,
                  color: item.isDirectory ? Colors.amber : Colors.blueGrey,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitleFor(item),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildWebDavActionButton(
                    focusNode: index == 0 && canOpen
                        ? _firstItemFocusNode
                        : null,
                    autofocus: index == 0 && canOpen,
                    icon: Icons.folder_open,
                    label: 'Open',
                    color: const Color(0xFF8B5CF6),
                    enabled: canOpen,
                    handoffLeftToSidebar: true,
                    upFocusNode: index == 0 ? _serverDropdownFocusNode : null,
                    onTap: () => _openFolder(item),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildWebDavActionButton(
                    focusNode: index == 0 && !canOpen && canPlay
                        ? _firstItemFocusNode
                        : null,
                    autofocus: index == 0 && !canOpen && canPlay,
                    icon: Icons.play_arrow_rounded,
                    label: 'Play',
                    color: const Color(0xFF22C55E),
                    enabled: canPlay,
                    upFocusNode: index == 0 ? _serverDropdownFocusNode : null,
                    onTap: () => _playItem(item),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More options',
                  onSelected: (value) {
                    if (value == 'download') _downloadItem(item);
                    if (value == 'add_to_playlist') _addItemToPlaylist(item);
                    if (value == 'delete') _deleteItem(item);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(
                            Icons.download_rounded,
                            size: 18,
                            color: Colors.green,
                          ),
                          SizedBox(width: 12),
                          Text('Download'),
                        ],
                      ),
                    ),
                    if (canPlay)
                      const PopupMenuItem(
                        value: 'add_to_playlist',
                        child: Row(
                          children: [
                            Icon(
                              Icons.playlist_add,
                              size: 18,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 12),
                            Text('Add to Playlist'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 12),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebDavActionButton({
    FocusNode? focusNode,
    bool autofocus = false,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
    bool handoffLeftToSidebar = false,
    FocusNode? upFocusNode,
  }) {
    final button = Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      canRequestFocus: enabled,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            handoffLeftToSidebar &&
            MainPageBridge.focusTvSidebar != null) {
          MainPageBridge.focusTvSidebar!();
          return KeyEventResult.handled;
        }
        if (!enabled) return KeyEventResult.ignored;
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowUp &&
            upFocusNode != null) {
          upFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          final effectiveColor = enabled ? color : Colors.grey;
          return GestureDetector(
            onTap: enabled ? onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isFocused && enabled
                    ? effectiveColor
                    : Colors.black.withValues(alpha: enabled ? 0.85 : 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: enabled
                      ? effectiveColor.withValues(alpha: isFocused ? 1 : 0.6)
                      : Colors.white.withValues(alpha: 0.12),
                  width: isFocused && enabled ? 1.5 : 1,
                ),
                boxShadow: isFocused && enabled
                    ? [
                        BoxShadow(
                          color: effectiveColor.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.35),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(
                        alpha: enabled ? 0.9 : 0.35,
                      ),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (upFocusNode == null) return button;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          upFocusNode.requestFocus();
        },
      },
      child: button,
    );
  }

  String _subtitleFor(WebDavItem item) {
    final parts = <String>[];
    if (item.isDirectory) {
      parts.add('Folder');
    } else if (item.sizeBytes != null) {
      parts.add(Formatters.formatFileSize(item.sizeBytes!));
    }
    if (item.modifiedAt != null) {
      parts.add(_formatDate(item.modifiedAt!));
    }
    return parts.isEmpty ? item.path : parts.join(' • ');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
