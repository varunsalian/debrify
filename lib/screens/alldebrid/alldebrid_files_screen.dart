import 'dart:async';
import 'package:debrify/features/alldebrid_files/models/alldebrid_view.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart'; // re-exports PlaylistEntry
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:debrify/widgets/cloud/cloud_segmented_tabs.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cloud-library browser for AllDebrid. AllDebrid's cloud is a flat list of
/// magnets (each with files), so this is a two-level browser (magnet list →
/// the selected magnet's files), built on the shared cloud widgets
/// (CloudFileRow rows, CloudSegmentedTabs view switcher, CloudScaffold).
class AllDebridFilesScreen extends StatefulWidget {
  final bool isPushedRoute;
  final String? initialSearchQuery;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;

  const AllDebridFilesScreen({
    super.key,
    this.isPushedRoute = false,
    this.initialSearchQuery,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  @override
  State<AllDebridFilesScreen> createState() => _AllDebridFilesScreenState();
}

class _AllDebridFilesScreenState extends State<AllDebridFilesScreen> {
  final _library = AllDebridLibraryState();
  final _navigation = AllDebridNavigationState();
  final _search = AllDebridSearchState();
  final _focus = AllDebridFocusState();
  final _selection = AllDebridSelectionState();
  final _feedback = AllDebridFeedbackState();
  AllDebridFocusState get _f => _focus;
  static const int _tabIndex = 12;

  bool get _isAtRoot => _navigation.currentMagnet == null;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('alldebrid_files');
    final initialQuery = widget.initialSearchQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _search.searchActive = true;
      _search.searchQuery = initialQuery;
      _search.searchController.text = initialQuery;
    }
    if (widget.isPushedRoute) {
      // Pushed as a route (e.g. from the consolidated Cloud hub) — register a
      // pushed-route back handler so hardware/gesture Back navigates up within
      // the screen before popping, matching the other provider screens.
      MainPageBridge.pushRouteBackHandler(_handleBackNavigation);
    } else {
      MainPageBridge.registerTabBackHandler('alldebrid', _handleBackNavigation);
      _f.tvContentFocusHandler = () {
        _f.shouldFocusOnLoad = true;
        _focusFirstItem();
      };
      MainPageBridge.registerTvContentFocusHandler(
        _tabIndex,
        _f.tvContentFocusHandler!,
      );
    }
    // The "shared web link → open on Web Downloads" deep link works in BOTH tab
    // and pushed (Cloud hub) modes — the Cloud hub always pushes, so gating this
    // on !isPushedRoute would silently drop the feature. Wire the live handler
    // and consume any pending flag regardless of how we were opened.
    MainPageBridge.focusAllDebridWebDownloads = _focusWebDownloads;
    if (MainPageBridge.getAndClearAllDebridFocusWebDownloads()) {
      _navigation.selectedView = AllDebridView.webDownloads;
    }
    _load();
    if (_navigation.selectedView == AllDebridView.webDownloads) {
      _loadLinks();
    }
  }

  /// Switches to the Web Downloads view and refreshes it. Invoked via
  /// [MainPageBridge.focusAllDebridWebDownloads] when a shared web link is saved
  /// while this screen is already mounted.
  Future<void> _focusWebDownloads() async {
    if (!mounted) return;
    setState(() {
      _navigation.selectedView = AllDebridView.webDownloads;
      _navigation.currentMagnet = null;
      _navigation.currentFiles = [];
      _selection.selectionMode = false;
      _selection.selectedIds.clear();
      _search.searchActive = false;
      _search.searchQuery = '';
      _search.searchController.clear();
    });
    await _loadLinks();
  }

  @override
  void dispose() {
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(_handleBackNavigation);
    } else {
      MainPageBridge.unregisterTabBackHandler('alldebrid');
      if (_f.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          _tabIndex,
          _f.tvContentFocusHandler!,
        );
      }
    }
    if (MainPageBridge.focusAllDebridWebDownloads == _focusWebDownloads) {
      MainPageBridge.focusAllDebridWebDownloads = null;
    }
    _search.searchController.dispose();
    _f.searchFocusNode.dispose();
    _f.searchClearFocusNode.dispose();
    _search.fileSearchController.dispose();
    _f.fileSearchFocusNode.dispose();
    _f.scrollController.dispose();
    _f.backButtonFocusNode.dispose();
    _f.deleteButtonFocusNode.dispose();
    _f.toolbarSearchFocusNode.dispose();
    _f.firstItemFocusNode.dispose();
    super.dispose();
  }

  void _focusFirstItem() {
    if (!_f.shouldFocusOnLoad) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_f.shouldFocusOnLoad) return;
      final hasItems = _navigation.selectedView == AllDebridView.webDownloads
          ? _visibleLinks.isNotEmpty
          : _visibleMagnets.isNotEmpty;
      if (_isAtRoot && hasItems) {
        _f.shouldFocusOnLoad = false;
        _f.firstItemFocusNode.requestFocus();
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _library.loading = true;
      _library.error = null;
    });
    final apiKey = await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _library.loading = false;
        _library.error = 'Add your AllDebrid API key in Settings first.';
      });
      return;
    }
    _library.apiKey = apiKey;
    try {
      final magnets = await AllDebridService.listMagnets(apiKey);
      if (!mounted) return;
      setState(() {
        _library.magnets = magnets.where((m) => m.isReady).toList();
        _library.loading = false;
        _selection.selectedIds.removeWhere(
          (id) => !_library.magnets.any((m) => m.id == id),
        );
      });
      _focusFirstItem();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _library.loading = false;
        _library.error = 'Failed to load your AllDebrid library: $e';
      });
    }
  }

  Future<void> _loadLinks() async {
    setState(() {
      _library.loadingLinks = true;
      _library.linksError = null;
    });
    final apiKey =
        _library.apiKey ?? await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _library.loadingLinks = false;
        _library.linksLoadedOnce = true;
        _library.linksError = 'Add your AllDebrid API key in Settings first.';
      });
      return;
    }
    _library.apiKey = apiKey;
    try {
      final links = await AllDebridService.listSavedLinks(apiKey);
      if (!mounted) return;
      setState(() {
        _library.links = links;
        _library.loadingLinks = false;
        _library.linksLoadedOnce = true;
      });
      _focusFirstItem();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _library.loadingLinks = false;
        _library.linksLoadedOnce = true;
        _library.linksError = 'Failed to load your saved links: $e';
      });
    }
  }

  Future<void> _refresh() async {
    if (_navigation.selectedView == AllDebridView.webDownloads) {
      await _loadLinks();
    } else if (_navigation.currentMagnet != null) {
      await _openMagnet(_navigation.currentMagnet!, force: true);
    } else {
      await _load();
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _openMagnet(AllDebridMagnet magnet, {bool force = false}) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (!magnet.isReady) {
      _snack(
        magnet.isError
            ? 'This magnet failed on AllDebrid.'
            : 'This magnet is still downloading on AllDebrid.',
        isError: true,
      );
      return;
    }
    setState(() {
      _navigation.currentMagnet = magnet;
      _navigation.loadingFiles = true;
      _search.fileSearchActive = false;
      _search.fileSearchQuery = '';
      _search.fileSearchController.clear();
      if (!force) _navigation.currentFiles = [];
    });
    try {
      final files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      if (!mounted) return;
      setState(() {
        _navigation.currentFiles = files;
        _navigation.loadingFiles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _navigation.loadingFiles = false);
      _snack('Failed to load files: $e', isError: true);
    }
  }

  void _navigateUp() {
    // Refocus the first magnet row after this synchronous swap back to the
    // (already-loaded) magnet list — the file row that binds
    // _firstItemFocusNode is disposed here and nothing else reclaims DPAD
    // focus. No reload fires, so do it directly.
    _f.shouldFocusOnLoad = true;
    if (_f.scrollController.hasClients) _f.scrollController.jumpTo(0);
    setState(() {
      _navigation.currentMagnet = null;
      _navigation.currentFiles = [];
      _navigation.loadingFiles = false;
      _search.fileSearchActive = false;
      _search.fileSearchQuery = '';
      _search.fileSearchController.clear();
    });
    _focusFirstItem();
  }

  bool _handleBackNavigation() {
    if (_selection.selectionMode) {
      _exitSelectionMode();
      return true;
    }
    if (_search.fileSearchActive) {
      setState(() {
        _search.fileSearchActive = false;
        _search.fileSearchQuery = '';
        _search.fileSearchController.clear();
      });
      return true;
    }
    if (_search.searchActive) {
      _toggleSearch();
      return true;
    }
    if (_navigation.currentMagnet != null) {
      _navigateUp();
      return true;
    }
    return false;
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  bool _looksLikeVideo(AllDebridFile f) => FileUtils.isVideoFile(f.fileName);

  Future<String> _unlockStart(String apiKey, String lockedLink) async {
    try {
      return await AllDebridService.unlockLink(apiKey, lockedLink);
    } catch (e) {
      debugPrint('AllDebridFiles: unlock failed: $e');
      return '';
    }
  }

  Future<void> _playFile(AllDebridFile file) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _showLoading('Unlocking…');
    final url = await _unlockStart(apiKey, file.link);
    _dismissLoading();
    if (!mounted) return;
    if (url.isEmpty) {
      _snack('Failed to unlock this file.', isError: true);
      return;
    }
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: file.fileName,
        subtitle: file.size > 0 ? Formatters.formatFileSize(file.size) : null,
        playlist: [
          PlaylistEntry(
            url: url,
            title: file.fileName,
            relativePath: file.fileName,
            provider: 'alldebrid',
            allDebridLink: file.link,
            sizeBytes: file.size > 0 ? file.size : null,
          ),
        ],
        startIndex: 0,
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }

  Future<void> _playMagnet(AllDebridMagnet magnet) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (!magnet.isReady) {
      _snack('This magnet is not ready yet.', isError: true);
      return;
    }
    List<AllDebridFile> files = _navigation.currentFiles;
    if (_navigation.currentMagnet?.id != magnet.id || files.isEmpty) {
      _showLoading('Scanning magnet…');
      try {
        files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      } catch (e) {
        _dismissLoading();
        _snack('Failed to scan magnet: $e', isError: true);
        return;
      }
      _dismissLoading();
    }
    await _playVideos(files, magnet.name);
  }

  Future<void> _playVideos(
    List<AllDebridFile> files,
    String collectionName,
  ) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final videos = files.where(_looksLikeVideo).toList();
    if (videos.isEmpty) {
      _snack('No playable video files found.', isError: true);
      return;
    }

    if (videos.length == 1) {
      await _playFile(videos.first);
      return;
    }

    // Multi-file: build a series-aware playlist, unlocking only the start file
    // up front. The rest carry their stable locked link and are unlocked on
    // demand by the player's lazy AllDebrid resolver.
    final infos = videos
        .map((v) => SeriesParser.parseFilename(v.fileName))
        .toList();
    final filenames = videos.map((v) => v.fileName).toList();
    final bool isSeries =
        videos.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final order = List<int>.generate(videos.length, (i) => i);
    if (isSeries) {
      order.sort((a, b) {
        final sa = infos[a].season ?? 0, sb = infos[b].season ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        final ea = infos[a].episode ?? 0, eb = infos[b].episode ?? 0;
        if (ea != eb) return ea.compareTo(eb);
        return videos[a].fileName.toLowerCase().compareTo(
          videos[b].fileName.toLowerCase(),
        );
      });
    } else {
      order.sort(
        (a, b) => videos[a].fileName.toLowerCase().compareTo(
          videos[b].fileName.toLowerCase(),
        ),
      );
    }

    final sortedVideos = [for (final i in order) videos[i]];
    final sortedInfos = [for (final i in order) infos[i]];
    int startIndex = isSeries ? _findFirstEpisodeIndex(sortedInfos) : 0;
    if (startIndex < 0 || startIndex >= sortedVideos.length) startIndex = 0;

    _showLoading('Unlocking…');
    String startUrl = await _unlockStart(apiKey, sortedVideos[startIndex].link);
    if (startUrl.isEmpty) {
      for (int i = 0; i < sortedVideos.length; i++) {
        if (i == startIndex) continue;
        final u = await _unlockStart(apiKey, sortedVideos[i].link);
        if (u.isNotEmpty) {
          startUrl = u;
          startIndex = i;
          break;
        }
      }
    }
    _dismissLoading();
    if (!mounted) return;
    if (startUrl.isEmpty) {
      _snack('Failed to resolve playable links from AllDebrid.', isError: true);
      return;
    }

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < sortedVideos.length; i++) {
      final v = sortedVideos[i];
      String relativePath = v.path;
      final firstSlash = relativePath.indexOf('/');
      if (firstSlash > 0) {
        relativePath = relativePath.substring(firstSlash + 1);
      }
      entries.add(
        PlaylistEntry(
          url: i == startIndex ? startUrl : '',
          title: v.fileName,
          relativePath: relativePath,
          provider: 'alldebrid',
          allDebridLink: v.link,
          sizeBytes: v.size > 0 ? v.size : null,
        ),
      );
    }

    final totalBytes = sortedVideos.fold<int>(0, (s, v) => s + v.size);
    final subtitle =
        '${entries.length} ${isSeries ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

    if (!mounted) return;
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: startUrl,
        title: collectionName,
        subtitle: subtitle,
        playlist: entries,
        startIndex: startIndex,
        viewMode: isSeries ? PlaylistViewMode.series : PlaylistViewMode.sorted,
      ),
    );
  }

  int _findFirstEpisodeIndex(List<SeriesInfo> infos) {
    int startIndex = 0;
    int? bestSeason;
    int? bestEpisode;
    for (int i = 0; i < infos.length; i++) {
      final info = infos[i];
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries || season == null || episode == null) continue;
      final betterSeason = bestSeason == null || season < bestSeason;
      final betterEpisode =
          bestSeason != null &&
          season == bestSeason &&
          (bestEpisode == null || episode < bestEpisode);
      if (betterSeason || betterEpisode) {
        bestSeason = season;
        bestEpisode = episode;
        startIndex = i;
      }
    }
    return startIndex;
  }

  // ── Download ─────────────────────────────────────────────────────────────

  Future<void> _downloadFile(AllDebridFile file) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _showLoading('Preparing download…');
    final url = await _unlockStart(apiKey, file.link);
    _dismissLoading();
    if (!mounted) return;
    if (url.isEmpty) {
      _snack('Failed to unlock this file.', isError: true);
      return;
    }
    try {
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'alldebrid_api_key',
        url: url,
        fileName: file.fileName,
        context: mounted ? context : null,
      );
      _snack('Download queued: ${file.fileName}', isError: false);
    } catch (e) {
      _snack('Failed to download: $e', isError: true);
    }
  }

  Future<void> _downloadMagnet(AllDebridMagnet magnet) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    List<AllDebridFile> files = _navigation.currentFiles;
    if (_navigation.currentMagnet?.id != magnet.id || files.isEmpty) {
      _showLoading('Scanning magnet…');
      try {
        files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      } catch (e) {
        _dismissLoading();
        _snack('Failed to scan magnet: $e', isError: true);
        return;
      }
      _dismissLoading();
    }
    if (!mounted) return;
    if (files.isEmpty) {
      _snack('This magnet has no files.', isError: true);
      return;
    }
    final dialogFiles = <Map<String, dynamic>>[];
    for (int i = 0; i < files.length; i++) {
      dialogFiles.add({
        'name': files[i].path,
        '_fullPath': files[i].path,
        'size': files[i].size.toString(),
        '_adIndex': i,
      });
    }
    await showDialog(
      context: context,
      builder: (ctx) => FileSelectionDialog(
        files: dialogFiles,
        torrentName: magnet.name,
        onDownload: (selected) =>
            _downloadSelectedFiles(selected, files, magnet.name),
      ),
    );
  }

  Future<void> _downloadSelectedFiles(
    List<Map<String, dynamic>> selected,
    List<AllDebridFile> allFiles,
    String magnetName,
  ) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (selected.isEmpty) return;
    int success = 0, fail = 0;
    for (final f in selected) {
      final idx = f['_adIndex'] as int? ?? -1;
      if (idx < 0 || idx >= allFiles.length) {
        fail++;
        continue;
      }
      final target = allFiles[idx];
      final url = await _unlockStart(apiKey, target.link);
      if (url.isEmpty) {
        fail++;
        continue;
      }
      try {
        await DownloadService.instance.enqueueDownload(
          credentialKey: 'alldebrid_api_key',
          url: url,
          fileName: target.fileName,
          torrentName: magnetName,
          context: mounted ? context : null,
        );
        success++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    if (success > 0 && fail == 0) {
      _snack('Queued $success file${success == 1 ? '' : 's'}', isError: false);
    } else if (success > 0) {
      _snack('Queued $success, $fail failed', isError: true);
    } else {
      _snack('Failed to queue any files', isError: true);
    }
  }

  // ── Add magnet ─────────────────────────────────────────────────────────────

  Future<void> _showAddMagnetDialog() async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final controller = TextEditingController();
    final magnet = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add magnet'),
        content: Focus(
          // D-pad: let arrow-down leave the field for the Cancel/Add buttons.
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              node.nextFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'Paste a magnet link or infohash',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (magnet == null || magnet.isEmpty) return;
    _showLoading('Adding…');
    try {
      await AllDebridService.uploadMagnet(apiKey, magnet);
      _dismissLoading();
      _snack('Magnet added', isError: false);
      await _load();
    } catch (e) {
      _dismissLoading();
      _snack('Failed to add magnet: $e', isError: true);
    }
  }

  // ── Web Downloads (saved links) ──────────────────────────────────────────

  Future<void> _playLink(AllDebridLink l) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _showLoading('Unlocking…');
    final url = await _unlockStart(apiKey, l.link);
    _dismissLoading();
    if (!mounted) return;
    if (url.isEmpty) {
      _snack('Failed to unlock this link.', isError: true);
      return;
    }
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: l.fileName,
        subtitle: l.size > 0 ? Formatters.formatFileSize(l.size) : null,
        playlist: [
          PlaylistEntry(
            url: url,
            title: l.fileName,
            relativePath: l.fileName,
            provider: 'alldebrid',
            allDebridLink: l.link,
            sizeBytes: l.size > 0 ? l.size : null,
          ),
        ],
        startIndex: 0,
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }

  Future<void> _downloadLink(AllDebridLink l) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _showLoading('Preparing download…');
    final url = await _unlockStart(apiKey, l.link);
    _dismissLoading();
    if (!mounted) return;
    if (url.isEmpty) {
      _snack('Failed to unlock this link.', isError: true);
      return;
    }
    try {
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'alldebrid_api_key',
        url: url,
        fileName: l.fileName,
        context: mounted ? context : null,
      );
      _snack('Download queued: ${l.fileName}', isError: false);
    } catch (e) {
      _snack('Failed to download: $e', isError: true);
    }
  }

  Future<void> _copyLink(AllDebridLink l) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _showLoading('Unlocking…');
    final url = await _unlockStart(apiKey, l.link);
    _dismissLoading();
    if (!mounted) return;
    if (url.isEmpty) {
      _snack('Failed to unlock this link.', isError: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _snack('Link copied', isError: false);
  }

  Future<void> _showAddLinkDialog() async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final controller = TextEditingController();
    // Auto-paste a URL from the clipboard, matching the Real-Debrid page.
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = clip?.text?.trim() ?? '';
    if (clipText.startsWith('http://') || clipText.startsWith('https://')) {
      controller.text = clipText;
    }
    if (!mounted) return;
    final link = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add link'),
        content: Focus(
          // D-pad: let arrow-down leave the field for the Cancel/Add buttons.
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              node.nextFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'Paste a download link',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (link == null || link.isEmpty) return;
    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      _snack(
        'Enter a valid URL (must start with http:// or https://)',
        isError: true,
      );
      return;
    }
    _showLoading('Adding…');
    try {
      // Unlock first to validate the host is supported, then persist it to the
      // saved-links library so it shows up in this view.
      await AllDebridService.unlockLink(apiKey, link);
      await AllDebridService.saveLink(apiKey, link);
      _dismissLoading();
      _snack('Link added', isError: false);
      await _loadLinks();
    } catch (e) {
      _dismissLoading();
      _snack('Failed to add link: $e', isError: true);
    }
  }

  Future<void> _deleteLinks(List<AllDebridLink> links, {String? title}) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty || links.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title ??
              (links.length == 1
                  ? 'Delete link?'
                  : 'Delete ${links.length} links?'),
        ),
        content: Text(
          links.length == 1
              ? 'Remove "${links.first.fileName}" from your AllDebrid saved links?'
              : 'Remove these ${links.length} links from your AllDebrid saved links?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _showLoading('Deleting…');
    int fail = 0;
    for (final l in links) {
      try {
        await AllDebridService.deleteSavedLink(apiKey, l.link);
      } catch (_) {
        fail++;
      }
    }
    _dismissLoading();
    await _loadLinks();
    if (!mounted) return;
    if (fail == 0) {
      _snack(
        links.length == 1 ? 'Link deleted' : '${links.length} links deleted',
        isError: false,
      );
    } else {
      _snack(
        'Failed to delete $fail link${fail == 1 ? '' : 's'}',
        isError: true,
      );
    }
  }

  void _confirmDeleteAllLinks() {
    if (_library.links.isEmpty) return;
    _deleteLinks(List.of(_library.links), title: 'Delete all links?');
  }

  // ── Add to playlist ─────────────────────────────────────────────────────

  /// Saves a magnet to the playlist (RD-manner: keyed by infohash). Single
  /// video → 'single' with its locked link; multiple → 'collection' re-resolved
  /// by hash at play time.
  Future<void> _addMagnetToPlaylist(AllDebridMagnet magnet) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (magnet.hash.isEmpty) {
      _snack('This magnet has no infohash to save.', isError: true);
      return;
    }
    List<AllDebridFile> files = _navigation.currentFiles;
    if (_navigation.currentMagnet?.id != magnet.id || files.isEmpty) {
      _showLoading('Scanning magnet…');
      try {
        files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      } catch (e) {
        _dismissLoading();
        _snack('Failed to scan magnet: $e', isError: true);
        return;
      }
      _dismissLoading();
    }
    final videos = files.where(_looksLikeVideo).toList();
    if (videos.isEmpty) {
      _snack('No video files to add.', isError: true);
      return;
    }
    bool added;
    if (videos.length == 1) {
      added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'alldebrid',
        'title': FileUtils.cleanPlaylistTitle(magnet.name),
        'kind': 'single',
        'torrent_hash': magnet.hash,
        'allDebridLink': videos.first.link,
        'sizeBytes': videos.first.size,
      });
    } else {
      added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'alldebrid',
        'title': FileUtils.cleanPlaylistTitle(magnet.name),
        'kind': 'collection',
        'torrent_hash': magnet.hash,
        'count': videos.length,
      });
    }
    if (!mounted) return;
    _snack(
      added ? 'Added to playlist' : 'Already in playlist',
      isError: !added,
    );
  }

  // ── Delete ─────────────────────────────────────────────────────────────

  Future<void> _deleteMagnets(
    List<AllDebridMagnet> magnets, {
    String? title,
  }) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty || magnets.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title ??
              (magnets.length == 1
                  ? 'Delete magnet?'
                  : 'Delete ${magnets.length} magnets?'),
        ),
        content: Text(
          magnets.length == 1
              ? 'Remove "${magnets.first.name}" from your AllDebrid account?'
              : 'Remove these ${magnets.length} magnets from your AllDebrid account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _showLoading('Deleting…');
    for (final m in magnets) {
      await AllDebridService.deleteMagnet(apiKey, m.id);
    }
    _dismissLoading();
    _exitSelectionMode();
    await _load();
    if (mounted) {
      _snack(
        magnets.length == 1
            ? 'Magnet deleted'
            : '${magnets.length} magnets deleted',
        isError: false,
      );
    }
  }

  void _confirmDeleteAll() {
    if (_library.magnets.isEmpty) return;
    _deleteMagnets(List.of(_library.magnets), title: 'Delete all magnets?');
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void _toggleSelectionMode() {
    setState(() {
      _selection.selectionMode = !_selection.selectionMode;
      if (!_selection.selectionMode) _selection.selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    if (!_selection.selectionMode && _selection.selectedIds.isEmpty) return;
    setState(() {
      _selection.selectionMode = false;
      _selection.selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selection.selectedIds.contains(id)) {
        _selection.selectedIds.remove(id);
      } else {
        _selection.selectedIds.add(id);
      }
    });
  }

  bool get _isAllSelected =>
      _visibleMagnets.isNotEmpty &&
      _visibleMagnets.every((m) => _selection.selectedIds.contains(m.id));

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        for (final m in _visibleMagnets) {
          _selection.selectedIds.remove(m.id);
        }
      } else {
        for (final m in _visibleMagnets) {
          _selection.selectedIds.add(m.id);
        }
      }
    });
  }

  Future<void> _handleDeleteSelected() async {
    final targets = _library.magnets
        .where((m) => _selection.selectedIds.contains(m.id))
        .toList();
    if (targets.isEmpty) return;
    await _deleteMagnets(targets);
  }

  // ── Search ─────────────────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _search.searchActive = !_search.searchActive;
      if (!_search.searchActive) {
        _search.searchQuery = '';
        _search.searchController.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _f.searchFocusNode.requestFocus();
        });
      }
    });
  }

  List<AllDebridMagnet> get _visibleMagnets {
    if (_search.searchQuery.trim().isEmpty) return _library.magnets;
    final q = _search.searchQuery.trim().toLowerCase();
    return _library.magnets
        .where((m) => m.name.toLowerCase().contains(q))
        .toList();
  }

  List<AllDebridFile> get _visibleFiles {
    if (_search.fileSearchQuery.trim().isEmpty) return _navigation.currentFiles;
    final q = _search.fileSearchQuery.trim().toLowerCase();
    return _navigation.currentFiles
        .where((f) => f.fileName.toLowerCase().contains(q))
        .toList();
  }

  List<AllDebridLink> get _visibleLinks {
    if (_search.searchQuery.trim().isEmpty) return _library.links;
    final q = _search.searchQuery.trim().toLowerCase();
    return _library.links
        .where(
          (l) =>
              l.fileName.toLowerCase().contains(q) ||
              l.host.toLowerCase().contains(q),
        )
        .toList();
  }

  void _showLoading(String message) {
    if (_feedback.loadingDialogOpen || !mounted) return;
    _feedback.loadingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _dismissLoading() {
    if (!_feedback.loadingDialogOpen) return;
    _feedback.loadingDialogOpen = false;
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  void _snack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CloudScaffold(
      appBar: _isAtRoot
          ? null
          : AppBar(
              leading: IconButton(
                focusNode: _f.backButtonFocusNode,
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateUp,
                tooltip: 'Back',
              ),
              title: Text(_navigation.currentMagnet!.name),
              actions: [
                if (_navigation.currentFiles.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _search.fileSearchActive ? Icons.close : Icons.search,
                    ),
                    onPressed: () {
                      setState(() {
                        _search.fileSearchActive = !_search.fileSearchActive;
                        if (!_search.fileSearchActive) {
                          _search.fileSearchQuery = '';
                          _search.fileSearchController.clear();
                        } else {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _f.fileSearchFocusNode.requestFocus();
                          });
                        }
                      });
                    },
                    tooltip: 'Search files',
                  ),
              ],
            ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          if (_isAtRoot) _buildToolbar(),
          if (_isAtRoot) _buildViewSelectorBar(),
          if (_isAtRoot && _search.searchActive) _buildSearchBar(),
          if (_isAtRoot && _selection.selectionMode) _buildSelectionBar(),
          if (!_isAtRoot && _search.fileSearchActive) _buildFileSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// Pushed (from the Cloud hub or the openAllDebridFolder deep link) to browse
  /// — the root has no other Back affordance, so show one.
  bool get _isBrowsePush => widget.isPushedRoute;

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    final app = AppThemeScope.of(context);
    final isWeb = _navigation.selectedView == AllDebridView.webDownloads;
    final hasItems = isWeb
        ? _library.links.isNotEmpty
        : _library.magnets.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        final double iconSize = isCompact ? 20 : 24;
        final iconPadding = isCompact
            ? const EdgeInsets.all(6)
            : const EdgeInsets.all(8);
        final iconConstraints = isCompact
            ? const BoxConstraints(minWidth: 36, minHeight: 36)
            : const BoxConstraints(minWidth: 44, minHeight: 44);
        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, 0.05),
            borderRadius: app.shape.br(12),
            border: Border.all(color: app.fade(app.core.tx, 0.08)),
          ),
          child: Row(
            children: [
              if (_isBrowsePush) ...[
                Tooltip(
                  message: 'Back',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.arrow_back),
                    color: theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(width: isCompact ? 4 : 8),
              ],
              if (widget.selectSourceMode)
                const Text(
                  'Select AllDebrid Source',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              const Spacer(),
              // Selection mode is torrents-only (it bulk-deletes magnets).
              if (!widget.selectSourceMode && !isWeb && hasItems)
                Tooltip(
                  message: _selection.selectionMode
                      ? 'Exit selection'
                      : 'Select items',
                  child: IconButton(
                    onPressed: _toggleSelectionMode,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _selection.selectionMode
                          ? Icons.close
                          : Icons.checklist_outlined,
                    ),
                    color: _selection.selectionMode
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (!widget.selectSourceMode && hasItems) ...[
                Tooltip(
                  message: isWeb ? 'Delete all links' : 'Delete all magnets',
                  child: IconButton(
                    onPressed: isWeb
                        ? _confirmDeleteAllLinks
                        : _confirmDeleteAll,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    color: theme.colorScheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Tooltip(
                  message: _search.searchActive
                      ? 'Close search'
                      : (isWeb ? 'Search links' : 'Search magnets'),
                  child: IconButton(
                    focusNode: _f.toolbarSearchFocusNode,
                    onPressed: _toggleSearch,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _search.searchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                    ),
                    color: _search.searchActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              if (widget.selectSourceMode && hasItems)
                Tooltip(
                  message: _search.searchActive
                      ? 'Close search'
                      : (isWeb ? 'Search links' : 'Search magnets'),
                  child: IconButton(
                    focusNode: _f.toolbarSearchFocusNode,
                    onPressed: _toggleSearch,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _search.searchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                    ),
                    color: _search.searchActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (!widget.selectSourceMode)
                Tooltip(
                  message: isWeb ? 'Add link' : 'Add magnet link',
                  child: IconButton(
                    onPressed: isWeb
                        ? _showAddLinkDialog
                        : _showAddMagnetDialog,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.add_circle_outline),
                    color: theme.colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Tooltip(
                message: 'Refresh',
                child: IconButton(
                  onPressed: _refresh,
                  iconSize: iconSize,
                  padding: iconPadding,
                  constraints: iconConstraints,
                  icon: const Icon(Icons.refresh),
                  color: theme.colorScheme.onSurface,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Full-width view switcher on its own line under the toolbar (two labels
  /// don't fit the toolbar slot the old single-label dropdown used).
  Widget _buildViewSelectorBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: CloudSegmentedTabs<AllDebridView>(
        segments: const [
          CloudSegment(
            AllDebridView.torrents,
            'Torrent Downloads',
            Icons.folder_rounded,
          ),
          CloudSegment(
            AllDebridView.webDownloads,
            'Web Downloads',
            Icons.link_rounded,
          ),
        ],
        selected: _navigation.selectedView,
        onSelected: (value) {
          if (value == _navigation.selectedView) return;
          _exitSelectionMode();
          // Both root lists share _scrollController; reset so the incoming
          // view doesn't inherit the outgoing list's scroll offset.
          if (_f.scrollController.hasClients) _f.scrollController.jumpTo(0);
          setState(() {
            _navigation.selectedView = value;
            _search.searchActive = false;
            _search.searchQuery = '';
            _search.searchController.clear();
          });
          if (value == AllDebridView.webDownloads &&
              !_library.linksLoadedOnce) {
            _loadLinks();
          }
        },
      ),
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    final count = _selection.selectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _toggleSelectAll,
            child: Text(_isAllSelected ? 'Deselect All' : 'Select All'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            focusNode: _f.deleteButtonFocusNode,
            onPressed: count > 0 ? _handleDeleteSelected : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              disabledBackgroundColor: theme.colorScheme.error.withValues(
                alpha: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shared search-field decoration matching the cloud-screen styling.
  InputDecoration _searchDecoration(String hint) {
    final app = AppThemeScope.of(context);
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: app.fade(app.core.tx, 0.3)),
      prefixIcon: Icon(
        Icons.search_rounded,
        color: app.fade(app.core.tx, 0.4),
        size: 20,
      ),
      filled: true,
      fillColor: app.fade(app.core.tx, 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: app.cloud.accent),
      ),
    );
  }

  /// D-pad escape target for a search field (used by the TvTextField arrow
  /// callbacks below).
  void _moveFocusTo(FocusNode? target, FocusNode field) {
    // Move focus to [target] if it's mounted; otherwise just release the field
    // so the remote can traverse onward.
    if (target != null && target.context != null) {
      target.requestFocus();
    } else {
      field.unfocus();
    }
  }

  Widget _buildSearchBar() {
    final app = AppThemeScope.of(context);
    final hasText = _search.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _search.searchController,
              focusNode: _f.searchFocusNode,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              // D-pad exits (formerly a Focus/onKeyEvent wrapper): up to the
              // toolbar, down into the results, right to the clear button.
              onUpArrow: () =>
                  _moveFocusTo(_f.toolbarSearchFocusNode, _f.searchFocusNode),
              onDownArrow: () =>
                  _moveFocusTo(_f.firstItemFocusNode, _f.searchFocusNode),
              onRightArrow: hasText
                  ? () => _f.searchClearFocusNode.requestFocus()
                  : null,
              onChanged: (v) => setState(() => _search.searchQuery = v),
              onSubmitted: (_) => _f.searchFocusNode.unfocus(),
              decoration: _searchDecoration(
                _navigation.selectedView == AllDebridView.webDownloads
                    ? 'Search your links...'
                    : 'Search your magnets...',
              ),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _f.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key)) {
                    _search.searchController.clear();
                    setState(() => _search.searchQuery = '');
                    _f.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _f.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return Container(
                      decoration: BoxDecoration(
                        color: app.fade(app.core.tx, 0.06),
                        borderRadius: app.shape.br(8),
                        border: isFocused
                            ? Border.all(color: app.core.tx, width: 2)
                            : null,
                      ),
                      child: IconButton(
                        onPressed: () {
                          _search.searchController.clear();
                          setState(() => _search.searchQuery = '');
                          _f.searchFocusNode.requestFocus();
                        },
                        icon: Icon(
                          Icons.clear_rounded,
                          color: app.fade(app.core.tx, 0.4),
                          size: 18,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TvTextField(
        controller: _search.fileSearchController,
        focusNode: _f.fileSearchFocusNode,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        // D-pad exits (formerly a Focus/onKeyEvent wrapper): up to the back
        // button, down into the results.
        onUpArrow: () =>
            _moveFocusTo(_f.backButtonFocusNode, _f.fileSearchFocusNode),
        onDownArrow: () =>
            _moveFocusTo(_f.firstItemFocusNode, _f.fileSearchFocusNode),
        onChanged: (v) => setState(() => _search.fileSearchQuery = v),
        onSubmitted: (_) => _f.fileSearchFocusNode.unfocus(),
        decoration: _searchDecoration('Search files...'),
      ),
    );
  }

  Widget _buildBody() {
    final app = AppThemeScope.of(context);
    if (_navigation.selectedView == AllDebridView.webDownloads) {
      return _buildLinksView();
    }
    if (_library.loading) {
      return const CloudRowSkeletonList();
    }
    if (_library.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 48,
                color: app.fade(app.core.tx, 0x62 / 0xFF),
              ),
              const SizedBox(height: 16),
              Text(_library.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (!_isAtRoot) {
      return _buildFilesView();
    }
    return _buildMagnetsView();
  }

  Widget _buildMagnetsView() {
    final app = AppThemeScope.of(context);
    final magnets = _visibleMagnets;
    if (magnets.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                _search.searchQuery.isNotEmpty
                    ? 'No magnets match your search.'
                    : 'Your AllDebrid library is empty.',
                style: TextStyle(color: app.fade(app.core.tx, 0x8A / 0xFF)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _f.scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: magnets.length,
        itemBuilder: (context, index) {
          return KeyedSubtree(
            key: ValueKey(magnets[index].id),
            child: _buildMagnetCard(magnets[index], index),
          );
        },
      ),
    );
  }

  Widget _buildMagnetCard(AllDebridMagnet m, int index) {
    if (widget.selectSourceMode) {
      return CloudFileRow(
        kind: CloudRowKind.folder,
        title: m.name.isEmpty ? '(unnamed)' : m.name,
        meta: Formatters.formatFileSize(m.size),
        badges: const [CloudRowBadge('Ready', CloudBadgeKind.ok)],
        onTap: () async {
          if (m.hash.trim().isEmpty) {
            _snack(
              'This AllDebrid magnet has no infohash to bind.',
              isError: true,
            );
            return;
          }
          await widget.onSourceSelected?.call(
            SeriesSource(
              torrentHash: m.hash,
              torrentName: m.name,
              debridService: 'alldebrid',
              debridTorrentId: m.id,
              boundAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          if (!mounted) return;
          Navigator.of(context).pop();
        },
        focusNode: index == 0 ? _f.firstItemFocusNode : null,
      );
    }

    // Same action set (labels, conditions) the old Open/Play pills + ⋮ menu
    // offered; the row's tap now carries Open for ready magnets.
    final actions = <CloudRowAction>[
      if (m.isReady)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _playMagnet(m),
        ),
      if (m.isReady)
        CloudRowAction(
          icon: Icons.download,
          label: 'Download to device',
          showInStrip: true,
          onSelected: () => _downloadMagnet(m),
        ),
      if (m.isReady)
        CloudRowAction(
          icon: Icons.folder_open,
          label: 'Open',
          onSelected: () => _openMagnet(m),
        ),
      if (m.isReady)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _addMagnetToPlaylist(m),
        ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _deleteMagnets([m]),
      ),
    ];

    return CloudFileRow(
      kind: m.isError ? CloudRowKind.error : CloudRowKind.folder,
      title: m.name.isEmpty ? '(unnamed)' : m.name,
      meta: m.isReady ? Formatters.formatFileSize(m.size) : null,
      badges: [
        if (m.isError)
          const CloudRowBadge('Failed', CloudBadgeKind.error)
        else if (!m.isReady)
          CloudRowBadge(
            'Downloading ${m.progressPercent}%',
            CloudBadgeKind.warn,
          ),
      ],
      // Not-ready magnets keep a tap action too: _openMagnet explains why it
      // can't open ("still downloading" / "failed") — better than the menu
      // fallback, which here would be a Delete-only menu.
      onTap: () => _openMagnet(m),
      actions: actions,
      selectionMode: _selection.selectionMode,
      selected: _selection.selectedIds.contains(m.id),
      onToggleSelected: () => _toggleSelection(m.id),
      focusNode: index == 0 ? _f.firstItemFocusNode : null,
    );
  }

  Widget _buildLinksView() {
    final app = AppThemeScope.of(context);
    if (_library.loadingLinks) {
      return const CloudRowSkeletonList();
    }
    if (_library.linksError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 48,
                color: app.fade(app.core.tx, 0x62 / 0xFF),
              ),
              const SizedBox(height: 16),
              Text(_library.linksError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadLinks, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final links = _visibleLinks;
    if (links.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadLinks,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                _search.searchQuery.isNotEmpty
                    ? 'No links match your search.'
                    : 'No saved links yet.',
                style: TextStyle(color: app.fade(app.core.tx, 0x8A / 0xFF)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadLinks,
      child: ListView.builder(
        controller: _f.scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: links.length,
        itemBuilder: (context, index) {
          return KeyedSubtree(
            key: ValueKey(links[index].link),
            child: _buildLinkCard(links[index], index),
          );
        },
      ),
    );
  }

  Widget _buildLinkCard(AllDebridLink l, int index) {
    final isVideo = FileUtils.isVideoFile(l.fileName);
    final subtitle = [
      if (l.size > 0) Formatters.formatFileSize(l.size),
      if (l.host.isNotEmpty) l.host,
    ].join(' · ');

    if (widget.selectSourceMode) {
      return CloudFileRow(
        kind: isVideo ? CloudRowKind.video : CloudRowKind.file,
        title: l.fileName,
        meta: subtitle.isEmpty ? null : subtitle,
        onTap: isVideo
            ? () async {
                await widget.onSourceSelected?.call(
                  SeriesSource(
                    torrentHash: '',
                    torrentName: l.fileName,
                    debridService: 'alldebrid',
                    debridTorrentId: SeriesSource.opaqueCloudReference(l.link),
                    cloudSourceKind: SeriesSource.cloudKindWebDownload,
                    boundAt: DateTime.now().millisecondsSinceEpoch,
                  ),
                );
                if (!mounted) return;
                Navigator.of(context).pop();
              }
            : null,
        focusNode: index == 0 ? _f.firstItemFocusNode : null,
      );
    }

    final actions = <CloudRowAction>[
      if (isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _playLink(l),
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: isVideo ? 'Download to device' : 'Download',
        showInStrip: true,
        onSelected: () => _downloadLink(l),
      ),
      CloudRowAction(
        icon: Icons.link,
        label: 'Copy link',
        onSelected: () => _copyLink(l),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _deleteLinks([l]),
      ),
    ];

    return CloudFileRow(
      kind: isVideo ? CloudRowKind.video : CloudRowKind.file,
      title: l.fileName,
      meta: subtitle.isEmpty ? null : subtitle,
      onTap: isVideo ? () => _playLink(l) : null,
      actions: actions,
      focusNode: index == 0 ? _f.firstItemFocusNode : null,
    );
  }

  Widget _buildFilesView() {
    final app = AppThemeScope.of(context);
    if (_navigation.loadingFiles) {
      return const CloudRowSkeletonList();
    }
    final files = _visibleFiles;
    if (files.isEmpty) {
      return Center(
        child: Text(
          _search.fileSearchQuery.isNotEmpty
              ? 'No files match your search.'
              : 'No files in this magnet.',
          style: TextStyle(color: app.fade(app.core.tx, 0x8A / 0xFF)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        return KeyedSubtree(
          key: ValueKey(
            '${_navigation.currentMagnet!.id}:${files[index].path}:$index',
          ),
          child: _buildFileCard(files[index], index),
        );
      },
    );
  }

  Widget _buildFileCard(AllDebridFile f, int index) {
    final isVideo = _looksLikeVideo(f);

    // Parity with the old card: files inside a magnet only offer Play (video)
    // and Download — no delete or playlist at file granularity.
    final actions = <CloudRowAction>[
      if (isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _playFile(f),
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _downloadFile(f),
      ),
    ];

    return CloudFileRow(
      kind: isVideo ? CloudRowKind.video : CloudRowKind.file,
      title: f.fileName,
      meta: Formatters.formatFileSize(f.size),
      onTap: isVideo ? () => _playFile(f) : null,
      actions: actions,
      focusNode: index == 0 ? _f.firstItemFocusNode : null,
    );
  }
}

/// Frozen step-0 seam: state reads and the dormant forced-files refresh only.
@visibleForTesting
Map<String, Object?> allDebridFilesTestAccess(
  State<AllDebridFilesScreen> state,
) {
  final s = state as _AllDebridFilesScreenState;
  return {
    'apiKey': s._library.apiKey,
    'loading': s._library.loading,
    'error': s._library.error,
    'magnets': List<AllDebridMagnet>.unmodifiable(s._library.magnets),
    'selectedView': s._navigation.selectedView.name,
    'links': List<AllDebridLink>.unmodifiable(s._library.links),
    'loadingLinks': s._library.loadingLinks,
    'linksLoadedOnce': s._library.linksLoadedOnce,
    'linksError': s._library.linksError,
    'currentMagnet': s._navigation.currentMagnet,
    'currentFiles': List<AllDebridFile>.unmodifiable(
      s._navigation.currentFiles,
    ),
    'loadingFiles': s._navigation.loadingFiles,
    'isAtRoot': s._isAtRoot,
    'searchActive': s._search.searchActive,
    'searchQuery': s._search.searchQuery,
    'fileSearchActive': s._search.fileSearchActive,
    'fileSearchQuery': s._search.fileSearchQuery,
    'selectionMode': s._selection.selectionMode,
    'selectedIds': Set<String>.unmodifiable(s._selection.selectedIds),
    'isAllSelected': s._isAllSelected,
    'visibleMagnets': List<AllDebridMagnet>.unmodifiable(s._visibleMagnets),
    'visibleFiles': List<AllDebridFile>.unmodifiable(s._visibleFiles),
    'visibleLinks': List<AllDebridLink>.unmodifiable(s._visibleLinks),
    'loadingDialogOpen': s._feedback.loadingDialogOpen,
    'scrollController': s._f.scrollController,
    'searchFocusNode': s._f.searchFocusNode,
    'searchClearFocusNode': s._f.searchClearFocusNode,
    'fileSearchFocusNode': s._f.fileSearchFocusNode,
    'backButtonFocusNode': s._f.backButtonFocusNode,
    'deleteButtonFocusNode': s._f.deleteButtonFocusNode,
    'toolbarSearchFocusNode': s._f.toolbarSearchFocusNode,
    'firstItemFocusNode': s._f.firstItemFocusNode,
    'shouldFocusOnLoad': s._f.shouldFocusOnLoad,
    'refresh': s._refresh,
  };
}
