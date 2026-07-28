import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/iptv_playlist.dart';
import '../../services/iptv_service.dart';
import '../../services/xtream_codes_service.dart';
import '../../services/storage_service.dart';
import '../../services/analytics_service.dart';
import '../../utils/m3u_parser.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../../utils/tv_reveal.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';

class IptvSettingsPage extends StatefulWidget {
  const IptvSettingsPage({super.key});

  @override
  State<IptvSettingsPage> createState() => _IptvSettingsPageState();
}

class _IptvSettingsPageState extends State<IptvSettingsPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _epgUrlController = TextEditingController();
  final FocusNode _backButtonFocusNode = FocusNode(
    debugLabel: 'iptv-back-button',
  );
  final FocusNode _nameInputFocusNode = FocusNode(
    debugLabel: 'iptv-name-input',
  );
  final FocusNode _urlInputFocusNode = FocusNode(debugLabel: 'iptv-url-input');
  final FocusNode _epgUrlInputFocusNode =
      FocusNode(debugLabel: 'iptv-epg-url-input');
  final FocusNode _addButtonFocusNode = FocusNode(
    debugLabel: 'iptv-add-button',
  );
  final FocusNode _importFileButtonFocusNode = FocusNode(
    debugLabel: 'iptv-import-file-button',
  );

  // Xtream Codes controllers and focus nodes
  final TextEditingController _xcNameController = TextEditingController();
  final TextEditingController _xcServerController = TextEditingController();
  final TextEditingController _xcUsernameController = TextEditingController();
  final TextEditingController _xcPasswordController = TextEditingController();
  final FocusNode _xcNameFocusNode = FocusNode(debugLabel: 'iptv-xc-name');
  final FocusNode _xcServerFocusNode = FocusNode(debugLabel: 'iptv-xc-server');
  final FocusNode _xcUsernameFocusNode = FocusNode(
    debugLabel: 'iptv-xc-username',
  );
  final FocusNode _xcPasswordFocusNode = FocusNode(
    debugLabel: 'iptv-xc-password',
  );
  final FocusNode _xcLoginButtonFocusNode = FocusNode(
    debugLabel: 'iptv-xc-login-button',
  );
  bool _isXcAdding = false;

  // Tab focus nodes
  final FocusNode _urlTabFocusNode = FocusNode(debugLabel: 'iptv-url-tab');
  final FocusNode _fileTabFocusNode = FocusNode(debugLabel: 'iptv-file-tab');
  final FocusNode _xcTabFocusNode = FocusNode(debugLabel: 'iptv-xc-tab');

  late TabController _tabController;

  // Focus nodes for playlist items (3 per item: star + refresh + delete)
  final List<FocusNode> _playlistFocusNodes = [];

  List<IptvPlaylist> _playlists = [];
  String? _defaultPlaylistId;
  bool _loading = true;
  bool _isAdding = false;
  // Ids of playlists currently being refreshed (re-fetched from source)
  final Set<String> _refreshingIds = {};

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('iptv_settings');
    _tabController = TabController(length: 3, vsync: this);
    // Rebuild on tab change so the inactive tabs' ExcludeFocus updates —
    // otherwise DPAD traversal can wander into off-screen tab content.
    _tabController.addListener(_onTabChanged);
    _loadSettings();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  /// DOWN from a tab may select it first — the new tab's content is still
  /// under `ExcludeFocus(excluding: true)` until the rebuild, so a same-frame
  /// focus request is refused. Defer one frame — and MANUFACTURE that frame:
  /// when the tab was already selected, animateTo() early-returns (no
  /// setState, nothing schedules a frame on an idle screen) and an
  /// unscheduled post-frame callback just sits parked — the "DOWN does
  /// nothing, then the next keypress teleports focus into the form" glitch
  /// (the parked callback fired on the LATER press's frame and stole its
  /// focus move).
  void _focusContentAfterTabSwitch(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAndReveal(node);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// House DPAD idiom: focus a node, then scroll it into view next frame.
  /// Minimal + vertical-only via [tvRevealMinimal] — the alignment-pinning
  /// `Scrollable.ensureVisible` both over-scrolled (button focus dragged the
  /// playlists section into view) and dragged the TabBarView pager sideways
  /// (focusing the right-aligned Add button visibly switched tabs).
  void _focusAndReveal(FocusNode node) {
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx != null) tvRevealMinimal(ctx);
    });
    // If the node was already focused nothing above schedules a frame, and
    // the reveal would stall until some unrelated repaint — see
    // _focusContentAfterTabSwitch.
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _nameController.dispose();
    _urlController.dispose();
    _epgUrlController.dispose();
    _backButtonFocusNode.dispose();
    _nameInputFocusNode.dispose();
    _urlInputFocusNode.dispose();
    _epgUrlInputFocusNode.dispose();
    _addButtonFocusNode.dispose();
    _importFileButtonFocusNode.dispose();
    _xcNameController.dispose();
    _xcServerController.dispose();
    _xcUsernameController.dispose();
    _xcPasswordController.dispose();
    _xcNameFocusNode.dispose();
    _xcServerFocusNode.dispose();
    _xcUsernameFocusNode.dispose();
    _xcPasswordFocusNode.dispose();
    _xcLoginButtonFocusNode.dispose();
    _urlTabFocusNode.dispose();
    _fileTabFocusNode.dispose();
    _xcTabFocusNode.dispose();
    for (final node in _playlistFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _ensureFocusNodes() {
    // 4 focus nodes per playlist (star + refresh + edit-EPG + delete)
    final needed = _playlists.length * 4;

    while (_playlistFocusNodes.length > needed) {
      _playlistFocusNodes.removeLast().dispose();
    }

    while (_playlistFocusNodes.length < needed) {
      final index = _playlistFocusNodes.length;
      _playlistFocusNodes.add(FocusNode(debugLabel: 'iptv-playlist-$index'));
    }
  }

  Future<void> _loadSettings() async {
    final playlists = await StorageService.getIptvPlaylists();
    final defaultId = await StorageService.getIptvDefaultPlaylist();

    if (!mounted) return;

    setState(() {
      _playlists = playlists;
      _defaultPlaylistId = defaultId;
      _loading = false;
    });
    _ensureFocusNodes();

    // TV entry focus: land on the first tab (not a TextField, so no keyboard
    // pops) so DPAD users are never stranded on nothing.
    if (PlatformUtil.isAndroidTvCached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Only a bare FocusScopeNode as primary focus means DPAD is
        // stranded — don't steal focus the user already placed somewhere.
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _urlTabFocusNode.requestFocus();
      });
    }
  }

  Future<void> _addPlaylist() async {
    // The busy button is a no-op, but the fields' onSubmitted calls this
    // directly — guard so an in-flight add can't run twice.
    if (_isAdding) return;
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty) {
      _showSnackBar('Please enter a playlist name');
      return;
    }

    if (url.isEmpty) {
      _showSnackBar('Please enter a playlist URL');
      return;
    }

    if (!IptvService.isValidPlaylistUrl(url)) {
      _showSnackBar('Please enter a valid HTTP/HTTPS URL');
      return;
    }

    // Check for duplicate URL
    if (_playlists.any((p) => p.url == url)) {
      _showSnackBar('This playlist URL already exists');
      return;
    }

    setState(() => _isAdding = true);

    // Validate URL by trying to fetch it
    final result = await IptvService.instance.fetchPlaylist(url);

    if (!mounted) return;

    if (result.hasError) {
      setState(() => _isAdding = false);
      _showSnackBar('Failed to load playlist: ${result.error}');
      return;
    }

    if (result.isEmpty) {
      setState(() => _isAdding = false);
      _showSnackBar('Playlist is empty or invalid');
      return;
    }

    // Create new playlist
    final epgUrl = _epgUrlController.text.trim();
    final playlist = IptvPlaylist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      url: url,
      epgUrl: epgUrl.isEmpty ? null : epgUrl,
      addedAt: DateTime.now(),
    );

    final newPlaylists = [..._playlists, playlist];
    await StorageService.setIptvPlaylists(newPlaylists);

    setState(() {
      _playlists = newPlaylists;
      _nameController.clear();
      _urlController.clear();
      _epgUrlController.clear();
      _isAdding = false;
    });
    _ensureFocusNodes();

    _showSnackBar(
      'Added "$name" (${result.channels.length} channels)',
      isError: false,
    );
  }

  Future<void> _importFromFile() async {
    try {
      // FileType.any instead of custom extensions: Android's MIME mapping for
      // .m3u/.m3u8 is unreliable and can leave valid files unselectable in the
      // picker. The extension is validated below instead.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final file = result.files.first;
      final fileName = file.name.toLowerCase();

      // Validate extension
      if (!fileName.endsWith('.m3u') && !fileName.endsWith('.m3u8')) {
        _showSnackBar('Please select an M3U or M3U8 file');
        return;
      }

      // Read file content
      final Uint8List? fileBytes =
          file.bytes ??
          (file.path != null ? await file.xFile.readAsBytes() : null);
      if (fileBytes == null) {
        _showSnackBar('Could not read file content');
        return;
      }

      // Decode as UTF-8 so non-ASCII channel names survive; falls back to
      // latin1 for legacy playlists.
      final content = M3uParser.decodeBytes(fileBytes);

      // Validate file size (warn for >5MB)
      if (content.length > 5 * 1024 * 1024) {
        _showSnackBar(
          'File is very large (>${(content.length / 1024 / 1024).toStringAsFixed(1)}MB). This may cause issues.',
        );
      }

      // Parse to validate content (off the UI isolate for large files)
      final parseResult = await IptvService.instance.parseContent(content);

      if (parseResult.hasError) {
        _showSnackBar('Failed to parse playlist: ${parseResult.error}');
        return;
      }

      if (parseResult.isEmpty) {
        _showSnackBar('Playlist is empty or invalid');
        return;
      }

      // Extract default name from filename (without extension)
      String defaultName = file.name;
      if (defaultName.toLowerCase().endsWith('.m3u8')) {
        defaultName = defaultName.substring(0, defaultName.length - 5);
      } else if (defaultName.toLowerCase().endsWith('.m3u')) {
        defaultName = defaultName.substring(0, defaultName.length - 4);
      }

      // Show dialog to get playlist name
      if (!mounted) return;
      final playlistName = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Theme(
          data: settingsPageTheme(context),
          child: _PlaylistNameDialog(
            defaultName: defaultName,
            channelCount: parseResult.channels.length,
            existingNames: _playlists.map((p) => p.name).toSet(),
          ),
        ),
      );

      // User cancelled
      if (playlistName == null || playlistName.isEmpty) {
        return;
      }

      // Create new playlist with content
      final playlist = IptvPlaylist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: playlistName,
        url: '', // Empty URL for file-based playlists
        content: content,
        addedAt: DateTime.now(),
      );

      final newPlaylists = [..._playlists, playlist];
      await StorageService.setIptvPlaylists(newPlaylists);

      setState(() {
        _playlists = newPlaylists;
      });
      _ensureFocusNodes();

      _showSnackBar(
        'Imported "$playlistName" (${parseResult.channels.length} channels)',
        isError: false,
      );
    } catch (e) {
      _showSnackBar('Failed to import file: $e');
    }
  }

  /// Normalize a user-entered Xtream server URL: add a scheme when missing,
  /// strip a trailing get.php/player_api.php endpoint and any query, and drop a
  /// trailing slash — keeping a base path so panels behind a path prefix still
  /// work. Returns null when the input has no valid host. Shared by add and
  /// edit so both accept the same pasted forms.
  String? _normalizeXtreamServerUrl(String raw) {
    var serverUrl = raw.trim();
    if (serverUrl.isEmpty) return null;
    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      serverUrl = 'http://$serverUrl';
    }
    final serverUri = Uri.tryParse(serverUrl);
    if (serverUri == null || serverUri.host.isEmpty) return null;
    final pathSegments = serverUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    if (pathSegments.isNotEmpty && pathSegments.last.endsWith('.php')) {
      pathSegments.removeLast();
    }
    serverUrl = Uri(
      scheme: serverUri.scheme,
      // Keep basic-auth credentials if the pasted URL carried them.
      userInfo: serverUri.userInfo.isEmpty ? null : serverUri.userInfo,
      host: serverUri.host,
      port: serverUri.hasPort ? serverUri.port : null,
      pathSegments: pathSegments,
    ).toString();
    if (serverUrl.endsWith('/')) {
      serverUrl = serverUrl.substring(0, serverUrl.length - 1);
    }
    return serverUrl;
  }

  Future<void> _addXtreamCodes() async {
    // Same double-submission guard as _addPlaylist (fields' onSubmitted).
    if (_isXcAdding) return;
    final server = _xcServerController.text.trim();
    final username = _xcUsernameController.text.trim();
    final password = _xcPasswordController.text.trim();

    if (server.isEmpty) {
      _showSnackBar('Please enter a server URL');
      return;
    }
    if (username.isEmpty) {
      _showSnackBar('Please enter a username');
      return;
    }
    if (password.isEmpty) {
      _showSnackBar('Please enter a password');
      return;
    }

    final serverUrl = _normalizeXtreamServerUrl(server);
    if (serverUrl == null) {
      _showSnackBar('Please enter a valid server URL');
      return;
    }

    // Check for duplicate
    if (_playlists.any(
      (p) =>
          p.isXtreamCodes && p.serverUrl == serverUrl && p.username == username,
    )) {
      _showSnackBar('This Xtream Codes login already exists');
      return;
    }

    setState(() => _isXcAdding = true);

    final result = await XtreamCodesService.instance.authenticate(
      serverUrl,
      username,
      password,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() => _isXcAdding = false);
      _showSnackBar(result.error ?? 'Authentication failed');
      return;
    }

    // Create playlist with XC fields. Honor a user-supplied name; fall back to
    // the username@host label when the optional name field is left blank.
    final customName = _xcNameController.text.trim();
    final playlist = IptvPlaylist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: customName.isEmpty ? '$username@${Uri.parse(serverUrl).host}' : customName,
      url: '',
      serverUrl: serverUrl,
      username: username,
      password: password,
      addedAt: DateTime.now(),
    );

    final newPlaylists = [..._playlists, playlist];
    await StorageService.setIptvPlaylists(newPlaylists);

    setState(() {
      _playlists = newPlaylists;
      _xcNameController.clear();
      _xcServerController.clear();
      _xcUsernameController.clear();
      _xcPasswordController.clear();
      _isXcAdding = false;
    });
    _ensureFocusNodes();

    // Build status message
    String statusMsg = 'Added Xtream Codes login';
    if (result.status != null) statusMsg += ' (${result.status}';
    if (result.expDate != null) {
      statusMsg +=
          ', expires ${result.expDate!.year}-${result.expDate!.month.toString().padLeft(2, '0')}-${result.expDate!.day.toString().padLeft(2, '0')}';
    }
    if (result.status != null) statusMsg += ')';
    _showSnackBar(statusMsg, isError: false);
  }

  Future<void> _removePlaylist(IptvPlaylist playlist) async {
    final removedIndex = _playlists.indexWhere((p) => p.id == playlist.id);
    final newPlaylists = _playlists.where((p) => p.id != playlist.id).toList();
    await StorageService.setIptvPlaylists(newPlaylists);

    // If removed playlist was the default, clear default
    if (_defaultPlaylistId == playlist.id) {
      await StorageService.setIptvDefaultPlaylist(null);
      setState(() => _defaultPlaylistId = null);
    }

    // Clear cache for this playlist
    if (playlist.isXtreamCodes) {
      XtreamCodesService.instance.clearCache(playlist.serverUrl);
    } else if (!playlist.isLocalFile && playlist.url.isNotEmpty) {
      IptvService.instance.clearCache(playlist.url);
    }

    // Remove favorites and watch history that belonged to this playlist —
    // both replay from stored metadata, so either would otherwise keep
    // offering streams that no longer authenticate.
    await StorageService.removeIptvFavoritesByPlaylistId(playlist.id);
    await StorageService.removeIptvWatchHistoryByPlaylistId(playlist.id);

    setState(() => _playlists = newPlaylists);
    // _ensureFocusNodes disposes the trailing nodes — including the one the
    // focused delete button was using — so reseed DPAD focus on the same row
    // slot of a surviving playlist (or the tab bar when the list empties).
    _ensureFocusNodes();
    if (PlatformUtil.isAndroidTvCached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_playlistFocusNodes.isEmpty) {
          _focusAndReveal(switch (_tabController.index) {
            1 => _fileTabFocusNode,
            2 => _xcTabFocusNode,
            _ => _urlTabFocusNode,
          });
        } else {
          final row = removedIndex.clamp(0, _playlists.length - 1);
          _focusAndReveal(_playlistFocusNodes[row * 4]);
        }
      });
    }
    _showSnackBar('Removed "${playlist.name}"', isError: false);
  }

  Future<void> _setDefaultPlaylist(IptvPlaylist? playlist) async {
    await StorageService.setIptvDefaultPlaylist(playlist?.id);
    setState(() => _defaultPlaylistId = playlist?.id);
    _showSnackBar(
      playlist != null
          ? 'Default set to "${playlist.name}"'
          : 'Default cleared',
      isError: false,
    );
  }

  /// Re-fetch a URL or Xtream Codes playlist from its source, clearing the
  /// cache first so updated channels are picked up. Local-file playlists are
  /// static snapshots and cannot be refreshed.
  Future<void> _refreshPlaylist(IptvPlaylist playlist) async {
    if (playlist.isLocalFile) return;
    if (_refreshingIds.contains(playlist.id)) return;

    setState(() => _refreshingIds.add(playlist.id));
    _showSnackBar('Refreshing "${playlist.name}"…', isError: false);

    IptvParseResult result;
    if (playlist.isXtreamCodes) {
      XtreamCodesService.instance.clearCache(playlist.serverUrl);
      result = await XtreamCodesService.instance.fetchLiveStreams(
        playlist.serverUrl!,
        playlist.username!,
        playlist.password!,
      );
    } else {
      IptvService.instance.clearCache(playlist.url);
      result = await IptvService.instance.fetchPlaylist(
        playlist.url,
        forceRefresh: true,
      );
    }

    if (!mounted) return;
    setState(() => _refreshingIds.remove(playlist.id));

    if (result.hasError) {
      _showSnackBar('Failed to refresh "${playlist.name}": ${result.error}');
    } else {
      final suffix = result.warning != null ? ' (${result.warning})' : '';
      _showSnackBar(
        'Updated "${playlist.name}" — ${result.channels.length} channels$suffix',
        isError: false,
      );
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? kSettingsRed : kSettingsGreen,
      ),
    );
  }

  List<Widget> _buildPlaylistsList() {
    final items = <Widget>[];

    for (int i = 0; i < _playlists.length; i++) {
      final playlist = _playlists[i];
      final isDefault = _defaultPlaylistId == playlist.id;
      final starFocusIndex = i * 4;
      final refreshFocusIndex = i * 4 + 1;
      final editFocusIndex = i * 4 + 2;
      final deleteFocusIndex = i * 4 + 3;
      // URL and Xtream Codes playlists can be re-fetched; local files cannot.
      final canRefresh = !playlist.isLocalFile;

      items.add(
        FocusTraversalOrder(
          order: NumericFocusOrder(5.0 + i),
          child: _FocusablePlaylistTile(
            playlist: playlist,
            isDefault: isDefault,
            isRefreshing: _refreshingIds.contains(playlist.id),
            starFocusNode: starFocusIndex < _playlistFocusNodes.length
                ? _playlistFocusNodes[starFocusIndex]
                : null,
            refreshFocusNode: refreshFocusIndex < _playlistFocusNodes.length
                ? _playlistFocusNodes[refreshFocusIndex]
                : null,
            editFocusNode: editFocusIndex < _playlistFocusNodes.length
                ? _playlistFocusNodes[editFocusIndex]
                : null,
            deleteFocusNode: deleteFocusIndex < _playlistFocusNodes.length
                ? _playlistFocusNodes[deleteFocusIndex]
                : null,
            onSetDefault: () =>
                _setDefaultPlaylist(isDefault ? null : playlist),
            onRefresh: canRefresh ? () => _refreshPlaylist(playlist) : null,
            onEdit: () => _editPlaylist(playlist),
            onDelete: () => _removePlaylist(playlist),
          ),
        ),
      );
    }

    return items;
  }

  /// Edit an existing playlist in place: rename it, change its guide (EPG) URL,
  /// and — depending on type — its source URL (M3U URL playlists) or its
  /// server/username/password (Xtream logins). The id and added-at are
  /// preserved so favorites and watch history stay attached. When the source
  /// actually changes, the stale fetch cache is cleared so the next load picks
  /// up the new source; the user can Refresh to re-verify.
  Future<void> _editPlaylist(IptvPlaylist playlist) async {
    final result = await showDialog<_PlaylistEdit>(
      context: context,
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: _EditPlaylistDialog(
          playlist: playlist,
          // Exclude this playlist from the duplicate checks — keeping its own
          // name/URL must not read as a collision.
          existingNames: _playlists
              .where((p) => p.id != playlist.id)
              .map((p) => p.name)
              .toSet(),
          existingUrls: _playlists
              .where((p) =>
                  p.id != playlist.id && !p.isXtreamCodes && !p.isLocalFile)
              .map((p) => p.url)
              .toSet(),
        ),
      ),
    );
    if (result == null) return; // cancelled

    // Normalize an edited Xtream server URL the same way add does.
    String? newServerUrl = playlist.serverUrl;
    if (playlist.isXtreamCodes) {
      newServerUrl = _normalizeXtreamServerUrl(result.serverUrl ?? '');
      if (newServerUrl == null) {
        _showSnackBar('Please enter a valid server URL');
        return;
      }
    }

    final epg = (result.epgUrl ?? '').trim();
    final updated = IptvPlaylist(
      id: playlist.id,
      name: result.name,
      // URL playlists take the edited URL; Xtream/local keep their existing
      // url field (empty / snapshot-bound respectively).
      url: playlist.isXtreamCodes || playlist.isLocalFile
          ? playlist.url
          : result.url,
      content: playlist.content,
      serverUrl: playlist.isXtreamCodes ? newServerUrl : playlist.serverUrl,
      username: playlist.isXtreamCodes ? result.username : playlist.username,
      password: playlist.isXtreamCodes ? result.password : playlist.password,
      epgUrl: epg.isEmpty ? null : epg,
      addedAt: playlist.addedAt,
    );

    // Drop the stale fetch cache when the source changed so the next load
    // doesn't serve the old channels.
    if (playlist.isXtreamCodes) {
      final credsChanged = playlist.serverUrl != updated.serverUrl ||
          playlist.username != updated.username ||
          playlist.password != updated.password;
      if (credsChanged) {
        XtreamCodesService.instance.clearCache(playlist.serverUrl);
        XtreamCodesService.instance.clearCache(updated.serverUrl);
      }
    } else if (!playlist.isLocalFile && playlist.url != updated.url) {
      IptvService.instance.clearCache(playlist.url);
    }

    final newPlaylists = [
      for (final p in _playlists)
        if (p.id == playlist.id) updated else p,
    ];
    await StorageService.setIptvPlaylists(newPlaylists);
    if (!mounted) return;
    setState(() => _playlists = newPlaylists);
    _showSnackBar('Updated "${updated.name}"', isError: false);
  }

  Widget _buildUrlTabContent() {
    return Column(
      children: [
        // Name input
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: TvTextField(
            controller: _nameController,
            focusNode: _nameInputFocusNode,
            labelText: 'Playlist Name',
            hintText: 'e.g., My IPTV',
            prefixIcon: const Icon(Icons.label_outline),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _focusAndReveal(_urlInputFocusNode),
            // Explicit exits: UP targets the SELECTED tab (geometric search
            // from a full-width field center-lands on the middle tab).
            onUpArrow: () => _focusAndReveal(_urlTabFocusNode),
            onDownArrow: () => _focusAndReveal(_urlInputFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // URL input
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: TvTextField(
            controller: _urlController,
            focusNode: _urlInputFocusNode,
            labelText: 'Playlist URL',
            hintText: 'https://example.com/playlist.m3u',
            prefixIcon: const Icon(Icons.link),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _focusAndReveal(_epgUrlInputFocusNode),
            onUpArrow: () => _focusAndReveal(_nameInputFocusNode),
            onDownArrow: () => _focusAndReveal(_epgUrlInputFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // EPG URL input (optional). Playlists that declare url-tvg in their
        // own header don't need it; this overrides when both exist.
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: TvTextField(
            controller: _epgUrlController,
            focusNode: _epgUrlInputFocusNode,
            labelText: 'EPG URL (XMLTV, optional)',
            hintText: 'https://example.com/guide.xml.gz',
            prefixIcon: const Icon(Icons.calendar_view_day_outlined),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              // IME "done" unfocuses the field — park DPAD on the button so
              // focus isn't stranded on the bare scope while the add runs.
              _addButtonFocusNode.requestFocus();
              _addPlaylist();
            },
            onUpArrow: () => _focusAndReveal(_urlInputFocusNode),
            onDownArrow: () => _focusAndReveal(_addButtonFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Add button
        FocusTraversalOrder(
          // 4.5: after the EPG field, before the playlist tiles at 5.0 + i.
          order: const NumericFocusOrder(4.5),
          child: Align(
            alignment: Alignment.centerRight,
            child: _TvFocusableButton(
              focusNode: _addButtonFocusNode,
              icon: _isAdding ? Icons.hourglass_empty : Icons.add,
              label: _isAdding ? 'Adding...' : 'Add Playlist',
              onPressed: _isAdding ? () {} : _addPlaylist,
              onUpArrow: () => _focusAndReveal(_epgUrlInputFocusNode),
              onDownArrow:
                  _playlists.isNotEmpty && _playlistFocusNodes.isNotEmpty
                  ? () => _focusAndReveal(_playlistFocusNodes[0])
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileTabContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.folder_open,
          size: 48,
          color: kSettingsAccent2.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 16),
        Text(
          'Select an M3U or M3U8 file from your device',
          style: TextStyle(fontSize: 14, color: kSettingsDim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: _TvFocusableButton(
            focusNode: _importFileButtonFocusNode,
            icon: Icons.file_open,
            label: 'Browse Files',
            onPressed: _importFromFile,
            onUpArrow: () => _focusAndReveal(_fileTabFocusNode),
            onDownArrow: _playlists.isNotEmpty && _playlistFocusNodes.isNotEmpty
                ? () => _focusAndReveal(_playlistFocusNodes[0])
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildXcTabContent() {
    return Column(
      children: [
        // Playlist name input (optional). Blank falls back to username@host.
        FocusTraversalOrder(
          order: const NumericFocusOrder(1.9),
          child: TvTextField(
            controller: _xcNameController,
            focusNode: _xcNameFocusNode,
            labelText: 'Playlist Name (optional)',
            hintText: 'e.g., My Provider',
            prefixIcon: const Icon(Icons.label_outline),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _focusAndReveal(_xcServerFocusNode),
            // UP targets the SELECTED tab (geometric search from a full-width
            // field center-lands on the middle tab).
            onUpArrow: () => _focusAndReveal(_xcTabFocusNode),
            onDownArrow: () => _focusAndReveal(_xcServerFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Server URL input
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: TvTextField(
            controller: _xcServerController,
            focusNode: _xcServerFocusNode,
            labelText: 'Server URL',
            hintText: 'http://example.com:8080',
            prefixIcon: const Icon(Icons.dns),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _focusAndReveal(_xcUsernameFocusNode),
            onUpArrow: () => _focusAndReveal(_xcNameFocusNode),
            onDownArrow: () => _focusAndReveal(_xcUsernameFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Username input
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: TvTextField(
            controller: _xcUsernameController,
            focusNode: _xcUsernameFocusNode,
            labelText: 'Username',
            hintText: 'your username',
            prefixIcon: const Icon(Icons.person),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _focusAndReveal(_xcPasswordFocusNode),
            onUpArrow: () => _focusAndReveal(_xcServerFocusNode),
            onDownArrow: () => _focusAndReveal(_xcPasswordFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Password input
        FocusTraversalOrder(
          order: const NumericFocusOrder(3.5),
          child: TvTextField(
            controller: _xcPasswordController,
            focusNode: _xcPasswordFocusNode,
            labelText: 'Password',
            hintText: 'your password',
            prefixIcon: const Icon(Icons.lock),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              // IME "done" unfocuses the field — park DPAD on the button so
              // focus isn't stranded on the bare scope while the login runs.
              _xcLoginButtonFocusNode.requestFocus();
              _addXtreamCodes();
            },
            onUpArrow: () => _focusAndReveal(_xcUsernameFocusNode),
            onDownArrow: () => _focusAndReveal(_xcLoginButtonFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Login button
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: Align(
            alignment: Alignment.centerRight,
            child: _TvFocusableButton(
              focusNode: _xcLoginButtonFocusNode,
              icon: _isXcAdding ? Icons.hourglass_empty : Icons.login,
              label: _isXcAdding ? 'Logging in...' : 'Login & Add',
              onPressed: _isXcAdding ? () {} : _addXtreamCodes,
              onUpArrow: () => _focusAndReveal(_xcPasswordFocusNode),
              onDownArrow:
                  _playlists.isNotEmpty && _playlistFocusNodes.isNotEmpty
                  ? () => _focusAndReveal(_playlistFocusNodes[0])
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SettingsPageScaffold(
        title: 'IPTV Playlists',
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'IPTV Playlists',
      leading: _TvFocusableBackButton(
        focusNode: _backButtonFocusNode,
        // Land on the currently-selected tab, not always the first one.
        onDownArrow: () => _focusAndReveal(switch (_tabController.index) {
          1 => _fileTabFocusNode,
          2 => _xcTabFocusNode,
          _ => _urlTabFocusNode,
        }),
      ),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SettingsPageHeader(
              icon: Icons.live_tv_rounded,
              title: 'IPTV Playlists',
              subtitle:
                  'Add M3U playlists from a URL, import from a file, or login with Xtream Codes.',
            ),
            const SizedBox(height: 24),

            // Add Playlist section with Tabs
            const SettingsSectionLabel('Add Playlist'),
            const SizedBox(height: 6),

            // Tab bar
            _TvFocusableTabBar(
              tabController: _tabController,
              urlTabFocusNode: _urlTabFocusNode,
              fileTabFocusNode: _fileTabFocusNode,
              xcTabFocusNode: _xcTabFocusNode,
              onUpArrow: () => _backButtonFocusNode.requestFocus(),
              onDownArrowFromUrlTab: () =>
                  _focusContentAfterTabSwitch(_nameInputFocusNode),
              onDownArrowFromFileTab: () =>
                  _focusContentAfterTabSwitch(_importFileButtonFocusNode),
              onDownArrowFromXcTab: () =>
                  _focusContentAfterTabSwitch(_xcNameFocusNode),
            ),
            const SizedBox(height: 16),

            // Tab content (fixed height container). Sized for the tallest
            // tab — Xtream Login's four fields + button since the optional
            // name field joined (From URL has three fields + button); at 260
            // the button overflowed the box (painted-but-unclipped in release,
            // overlapping the section below).
            SizedBox(
              height: 410,
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Off-screen tab pages stay built by TabBarView, so exclude
                  // them from focus or DPAD traversal can land on invisible
                  // fields/buttons (a dead zone on TV).
                  ExcludeFocus(
                    excluding: _tabController.index != 0,
                    child: _buildUrlTabContent(),
                  ),
                  ExcludeFocus(
                    excluding: _tabController.index != 1,
                    child: _buildFileTabContent(),
                  ),
                  ExcludeFocus(
                    excluding: _tabController.index != 2,
                    child: _buildXcTabContent(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Playlists list
            const SettingsSectionLabel('Your Playlists'),
            Text(
              'Tap the star to set a default playlist.',
              style: TextStyle(fontSize: 12, color: kSettingsDim),
            ),
            const SizedBox(height: 16),

            if (_playlists.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.playlist_add, size: 48, color: kSettingsDim2),
                      const SizedBox(height: 12),
                      Text(
                        'No playlists yet',
                        style: TextStyle(fontSize: 14, color: kSettingsDim),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add an M3U playlist URL above',
                        style: TextStyle(fontSize: 12, color: kSettingsDim2),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(child: Column(children: _buildPlaylistsList())),
            const SizedBox(height: 24),

            // Default Playlist Info
            if (_defaultPlaylistId != null)
              const SettingsInfoBanner(
                text:
                    'Your default playlist will load automatically when you select IPTV.',
              ),
          ],
        ),
      ),
    );
  }
}

/// TV-focusable button with icon and label
class _TvFocusableButton extends StatefulWidget {
  const _TvFocusableButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onUpArrow,
    this.onDownArrow,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onUpArrow;
  final VoidCallback? onDownArrow;

  @override
  State<_TvFocusableButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<_TvFocusableButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TvFocusableButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            widget.onUpArrow != null) {
          widget.onUpArrow!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.onDownArrow != null) {
          widget.onDownArrow!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      // Snap, don't tween — animated focus decorations jank weak TV GPUs.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _isFocused
              ? Border.all(color: kSettingsAccent2, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: kSettingsAccent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        // One DPAD stop per control: the outer Focus owns DPAD (OK is handled
        // above). Without this the inner Material button is a SECOND,
        // invisible traversal stop — an arrow press moves focus "into" the
        // button and the custom ring vanishes for a beat.
        child: ExcludeFocus(
          child: FilledButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon),
            label: Text(widget.label),
            style: FilledButton.styleFrom(
              backgroundColor: _isFocused ? kSettingsAccent2 : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// TV-focusable tab bar with DPAD navigation
class _TvFocusableTabBar extends StatefulWidget {
  const _TvFocusableTabBar({
    required this.tabController,
    required this.urlTabFocusNode,
    required this.fileTabFocusNode,
    this.xcTabFocusNode,
    this.onUpArrow,
    this.onDownArrowFromUrlTab,
    this.onDownArrowFromFileTab,
    this.onDownArrowFromXcTab,
  });

  final TabController tabController;
  final FocusNode urlTabFocusNode;
  final FocusNode fileTabFocusNode;
  final FocusNode? xcTabFocusNode;
  final VoidCallback? onUpArrow;
  final VoidCallback? onDownArrowFromUrlTab;
  final VoidCallback? onDownArrowFromFileTab;
  final VoidCallback? onDownArrowFromXcTab;

  @override
  State<_TvFocusableTabBar> createState() => _TvFocusableTabBarState();
}

class _TvFocusableTabBarState extends State<_TvFocusableTabBar> {
  bool _urlTabFocused = false;
  bool _fileTabFocused = false;
  bool _xcTabFocused = false;

  @override
  void initState() {
    super.initState();
    widget.urlTabFocusNode.addListener(_onUrlTabFocusChange);
    widget.fileTabFocusNode.addListener(_onFileTabFocusChange);
    widget.xcTabFocusNode?.addListener(_onXcTabFocusChange);
  }

  @override
  void dispose() {
    widget.urlTabFocusNode.removeListener(_onUrlTabFocusChange);
    widget.fileTabFocusNode.removeListener(_onFileTabFocusChange);
    widget.xcTabFocusNode?.removeListener(_onXcTabFocusChange);
    super.dispose();
  }

  void _onUrlTabFocusChange() {
    if (mounted) {
      setState(() => _urlTabFocused = widget.urlTabFocusNode.hasFocus);
    }
  }

  void _onFileTabFocusChange() {
    if (mounted) {
      setState(() => _fileTabFocused = widget.fileTabFocusNode.hasFocus);
    }
  }

  void _onXcTabFocusChange() {
    if (mounted) {
      setState(() => _xcTabFocused = widget.xcTabFocusNode?.hasFocus ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: kSettingsPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSettingsLine),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          // URL Tab
          Expanded(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: Focus(
                focusNode: widget.urlTabFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;

                  if (isActivateKey(event.logicalKey)) {
                    // OK selects the tab AND enters its form — after OK the
                    // user's next instinct is to continue downward.
                    widget.tabController.animateTo(0);
                    widget.onDownArrowFromUrlTab?.call();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    widget.fileTabFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                      widget.onUpArrow != null) {
                    widget.onUpArrow!();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                      widget.onDownArrowFromUrlTab != null) {
                    widget.tabController.animateTo(0);
                    widget.onDownArrowFromUrlTab!();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: GestureDetector(
                  onTap: () => widget.tabController.animateTo(0),
                  child: AnimatedBuilder(
                    animation: widget.tabController,
                    builder: (context, child) {
                      final isSelected = widget.tabController.index == 0;
                      // Snap, don't tween — TV GPU rule.
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? kSettingsAccent.withValues(alpha: 0.22)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: _urlTabFocused
                              ? Border.all(color: kSettingsAccent, width: 2)
                              : null,
                          boxShadow: _urlTabFocused
                              ? [
                                  BoxShadow(
                                    color: kSettingsAccent.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.link,
                              size: 18,
                              color: isSelected
                                  ? kSettingsAccent2
                                  : kSettingsDim,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'From URL',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isSelected ? Colors.white : kSettingsDim,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // File Tab
          Expanded(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(1.5),
              child: Focus(
                focusNode: widget.fileTabFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;

                  if (isActivateKey(event.logicalKey)) {
                    // OK = select + enter the form (see the URL tab).
                    widget.tabController.animateTo(1);
                    widget.onDownArrowFromFileTab?.call();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    widget.urlTabFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                      widget.xcTabFocusNode != null) {
                    widget.xcTabFocusNode!.requestFocus();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                      widget.onUpArrow != null) {
                    widget.onUpArrow!();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                      widget.onDownArrowFromFileTab != null) {
                    widget.tabController.animateTo(1);
                    widget.onDownArrowFromFileTab!();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: GestureDetector(
                  onTap: () => widget.tabController.animateTo(1),
                  child: AnimatedBuilder(
                    animation: widget.tabController,
                    builder: (context, child) {
                      final isSelected = widget.tabController.index == 1;
                      // Snap, don't tween — TV GPU rule.
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? kSettingsAccent.withValues(alpha: 0.22)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: _fileTabFocused
                              ? Border.all(color: kSettingsAccent, width: 2)
                              : null,
                          boxShadow: _fileTabFocused
                              ? [
                                  BoxShadow(
                                    color: kSettingsAccent.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 18,
                              color: isSelected
                                  ? kSettingsAccent2
                                  : kSettingsDim,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'From File',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isSelected ? Colors.white : kSettingsDim,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          // Xtream Codes Tab
          if (widget.xcTabFocusNode != null) ...[
            const SizedBox(width: 4),
            Expanded(
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1.75),
                child: Focus(
                  focusNode: widget.xcTabFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;

                    if (isActivateKey(event.logicalKey)) {
                      // OK = select + enter the form (see the URL tab).
                      widget.tabController.animateTo(2);
                      widget.onDownArrowFromXcTab?.call();
                      return KeyEventResult.handled;
                    }

                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      widget.fileTabFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }

                    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                        widget.onUpArrow != null) {
                      widget.onUpArrow!();
                      return KeyEventResult.handled;
                    }

                    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                        widget.onDownArrowFromXcTab != null) {
                      widget.tabController.animateTo(2);
                      widget.onDownArrowFromXcTab!();
                      return KeyEventResult.handled;
                    }

                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                    onTap: () => widget.tabController.animateTo(2),
                    child: AnimatedBuilder(
                      animation: widget.tabController,
                      builder: (context, child) {
                        final isSelected = widget.tabController.index == 2;
                        // Snap, don't tween — TV GPU rule.
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? kSettingsAccent.withValues(alpha: 0.22)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: _xcTabFocused
                                ? Border.all(color: kSettingsAccent, width: 2)
                                : null,
                            boxShadow: _xcTabFocused
                                ? [
                                    BoxShadow(
                                      color: kSettingsAccent.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.login,
                                size: 18,
                                color: isSelected
                                    ? kSettingsAccent2
                                    : kSettingsDim,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Xtream Login',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: isSelected
                                        ? Colors.white
                                        : kSettingsDim,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Focusable playlist tile with star and delete buttons
class _FocusablePlaylistTile extends StatefulWidget {
  const _FocusablePlaylistTile({
    required this.playlist,
    required this.isDefault,
    this.isRefreshing = false,
    this.starFocusNode,
    this.refreshFocusNode,
    this.editFocusNode,
    this.deleteFocusNode,
    required this.onSetDefault,
    this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });

  final IptvPlaylist playlist;
  final bool isDefault;
  final bool isRefreshing;
  final FocusNode? starFocusNode;
  final FocusNode? refreshFocusNode;
  final FocusNode? editFocusNode;
  final FocusNode? deleteFocusNode;
  final VoidCallback onSetDefault;
  // Null when the playlist cannot be refreshed (local-file playlists).
  final VoidCallback? onRefresh;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_FocusablePlaylistTile> createState() => _FocusablePlaylistTileState();
}

class _FocusablePlaylistTileState extends State<_FocusablePlaylistTile> {
  bool _starFocused = false;
  bool _refreshFocused = false;
  bool _editFocused = false;
  bool _deleteFocused = false;

  @override
  void initState() {
    super.initState();
    widget.starFocusNode?.addListener(_onStarFocusChange);
    widget.refreshFocusNode?.addListener(_onRefreshFocusChange);
    widget.editFocusNode?.addListener(_onEditFocusChange);
    widget.deleteFocusNode?.addListener(_onDeleteFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusablePlaylistTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.starFocusNode != widget.starFocusNode) {
      oldWidget.starFocusNode?.removeListener(_onStarFocusChange);
      widget.starFocusNode?.addListener(_onStarFocusChange);
    }
    if (oldWidget.refreshFocusNode != widget.refreshFocusNode) {
      oldWidget.refreshFocusNode?.removeListener(_onRefreshFocusChange);
      widget.refreshFocusNode?.addListener(_onRefreshFocusChange);
    }
    if (oldWidget.editFocusNode != widget.editFocusNode) {
      oldWidget.editFocusNode?.removeListener(_onEditFocusChange);
      widget.editFocusNode?.addListener(_onEditFocusChange);
    }
    if (oldWidget.deleteFocusNode != widget.deleteFocusNode) {
      oldWidget.deleteFocusNode?.removeListener(_onDeleteFocusChange);
      widget.deleteFocusNode?.addListener(_onDeleteFocusChange);
    }
  }

  @override
  void dispose() {
    widget.starFocusNode?.removeListener(_onStarFocusChange);
    widget.refreshFocusNode?.removeListener(_onRefreshFocusChange);
    widget.editFocusNode?.removeListener(_onEditFocusChange);
    widget.deleteFocusNode?.removeListener(_onDeleteFocusChange);
    super.dispose();
  }

  void _onStarFocusChange() {
    if (mounted) {
      final hasFocus = widget.starFocusNode?.hasFocus ?? false;
      setState(() => _starFocused = hasFocus);
      if (hasFocus) _ensureVisible();
    }
  }

  void _onRefreshFocusChange() {
    if (mounted) {
      final hasFocus = widget.refreshFocusNode?.hasFocus ?? false;
      setState(() => _refreshFocused = hasFocus);
      if (hasFocus) _ensureVisible();
    }
  }

  void _onEditFocusChange() {
    if (mounted) {
      final hasFocus = widget.editFocusNode?.hasFocus ?? false;
      setState(() => _editFocused = hasFocus);
      if (hasFocus) _ensureVisible();
    }
  }

  void _onDeleteFocusChange() {
    if (mounted) {
      final hasFocus = widget.deleteFocusNode?.hasFocus ?? false;
      setState(() => _deleteFocused = hasFocus);
      if (hasFocus) _ensureVisible();
    }
  }

  void _ensureVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) {
        // Minimal, not centering: alignment 0.5 re-scrolled the page on
        // EVERY tile-button focus even when the tile was fully visible.
        tvRevealMinimal(context, duration: const Duration(milliseconds: 200));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAnyFocused =
        _starFocused || _refreshFocused || _editFocused || _deleteFocused;
    final canRefresh = widget.onRefresh != null;

    // Snap, don't tween — TV GPU rule.
    return Container(
      decoration: BoxDecoration(
        color: isAnyFocused ? kSettingsPanel2 : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          widget.isDefault
              ? Icons.star
              : widget.playlist.isXtreamCodes
              ? Icons.login
              : (widget.playlist.isLocalFile
                    ? Icons.folder
                    : Icons.playlist_play),
          color: widget.isDefault ? kSettingsAmber : null,
        ),
        title: Text(widget.playlist.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.playlist.isXtreamCodes) ...[
                  Icon(Icons.login, size: 12, color: kSettingsDim),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Xtream Codes - ${widget.playlist.serverUrl}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: kSettingsDim),
                    ),
                  ),
                ] else if (widget.playlist.isLocalFile) ...[
                  Icon(Icons.sd_card, size: 12, color: kSettingsDim),
                  const SizedBox(width: 4),
                  Text(
                    'Local file',
                    style: TextStyle(fontSize: 12, color: kSettingsDim),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      widget.playlist.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: kSettingsDim),
                    ),
                  ),
              ],
            ),
            if ((widget.playlist.epgUrl ?? '').isNotEmpty)
              Text(
                'Custom EPG URL set',
                style: TextStyle(color: kSettingsDim, fontSize: 12),
              ),
            if (widget.isDefault)
              const Text(
                'Default playlist',
                style: TextStyle(color: kSettingsAmber, fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FocusableIconButton(
              focusNode: widget.starFocusNode,
              icon: widget.isDefault ? Icons.star : Icons.star_border,
              color: widget.isDefault ? kSettingsAmber : null,
              tooltip: widget.isDefault ? 'Remove default' : 'Set as default',
              onPressed: widget.onSetDefault,
              onRightArrow: () =>
                  (canRefresh ? widget.refreshFocusNode : widget.editFocusNode)
                      ?.requestFocus(),
            ),
            if (canRefresh)
              _FocusableIconButton(
                focusNode: widget.refreshFocusNode,
                icon: Icons.refresh,
                tooltip: 'Refresh playlist',
                isBusy: widget.isRefreshing,
                onPressed: widget.onRefresh!,
                onLeftArrow: () => widget.starFocusNode?.requestFocus(),
                onRightArrow: () => widget.editFocusNode?.requestFocus(),
              ),
            _FocusableIconButton(
              focusNode: widget.editFocusNode,
              icon: Icons.edit_outlined,
              tooltip: 'Edit playlist',
              onPressed: widget.onEdit,
              onLeftArrow: () =>
                  (canRefresh ? widget.refreshFocusNode : widget.starFocusNode)
                      ?.requestFocus(),
              onRightArrow: () => widget.deleteFocusNode?.requestFocus(),
            ),
            _FocusableIconButton(
              focusNode: widget.deleteFocusNode,
              icon: Icons.delete_outline,
              tooltip: 'Remove playlist',
              onPressed: widget.onDelete,
              onLeftArrow: () => widget.editFocusNode?.requestFocus(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The edited values a [_EditPlaylistDialog] returns. Only the fields relevant
/// to the playlist's type are populated; the caller rebuilds the playlist.
class _PlaylistEdit {
  const _PlaylistEdit({
    required this.name,
    required this.url,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.epgUrl,
  });

  final String name;
  final String url; // M3U URL playlists only
  final String? serverUrl; // Xtream only
  final String? username; // Xtream only
  final String? password; // Xtream only
  final String? epgUrl;
}

/// Edit an existing playlist: rename, change the EPG URL, and — by type — the
/// source URL (M3U URL playlists) or server/username/password (Xtream logins).
///
/// TV DPAD: each field is a shell with no explicit arrow wiring, so vertical
/// moves fall through to the framework's directional traversal (the same way
/// the single-field dialogs walk field↔buttons). The name field seeds focus so
/// DOWN steps through the fields to the actions; OK on a field starts editing.
class _EditPlaylistDialog extends StatefulWidget {
  const _EditPlaylistDialog({
    required this.playlist,
    required this.existingNames,
    required this.existingUrls,
  });

  final IptvPlaylist playlist;
  final Set<String> existingNames;
  final Set<String> existingUrls;

  @override
  State<_EditPlaylistDialog> createState() => _EditPlaylistDialogState();
}

class _EditPlaylistDialogState extends State<_EditPlaylistDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _epgController;

  // One shell node per field so DPAD can be wired field-to-field explicitly —
  // this screen wires arrows rather than trusting directional traversal.
  final FocusNode _nameFocusNode = FocusNode(debugLabel: 'iptv-edit-name');
  final FocusNode _urlFocusNode = FocusNode(debugLabel: 'iptv-edit-url');
  final FocusNode _serverFocusNode = FocusNode(debugLabel: 'iptv-edit-server');
  final FocusNode _usernameFocusNode =
      FocusNode(debugLabel: 'iptv-edit-username');
  final FocusNode _passwordFocusNode =
      FocusNode(debugLabel: 'iptv-edit-password');
  final FocusNode _epgFocusNode = FocusNode(debugLabel: 'iptv-edit-epg');

  bool get _isXtream => widget.playlist.isXtreamCodes;
  bool get _isUrl =>
      !widget.playlist.isXtreamCodes && !widget.playlist.isLocalFile;

  @override
  void initState() {
    super.initState();
    final p = widget.playlist;
    _nameController = TextEditingController(text: p.name);
    _urlController = TextEditingController(text: p.url);
    _serverController = TextEditingController(text: p.serverUrl ?? '');
    _usernameController = TextEditingController(text: p.username ?? '');
    _passwordController = TextEditingController(text: p.password ?? '');
    _epgController = TextEditingController(text: p.epgUrl ?? '');
    for (final c in [
      _nameController,
      _urlController,
      _serverController,
      _usernameController,
      _passwordController,
    ]) {
      c.addListener(_revalidate);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _epgController.dispose();
    _nameFocusNode.dispose();
    _urlFocusNode.dispose();
    _serverFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _epgFocusNode.dispose();
    super.dispose();
  }

  void _revalidate() => setState(() {});

  /// The blocking error for the current values, or null when saveable. Drives
  /// both the Save button's enabled state and the inline field errors.
  String? get _nameError {
    final name = _nameController.text.trim();
    if (name.isEmpty) return 'Please enter a name';
    // Keeping this playlist's own name is always fine, even if another
    // playlist already happens to share it (the add paths don't enforce
    // unique names) — only block CHANGING to a name that collides.
    if (name != widget.playlist.name.trim() &&
        widget.existingNames.contains(name)) {
      return 'A playlist with this name already exists';
    }
    return null;
  }

  String? get _urlError {
    if (!_isUrl) return null;
    final url = _urlController.text.trim();
    if (url.isEmpty) return 'Please enter a playlist URL';
    if (!IptvService.isValidPlaylistUrl(url)) {
      return 'Please enter a valid HTTP/HTTPS URL';
    }
    if (url != widget.playlist.url.trim() &&
        widget.existingUrls.contains(url)) {
      return 'This playlist URL already exists';
    }
    return null;
  }

  String? get _serverError {
    if (!_isXtream) return null;
    return _serverController.text.trim().isEmpty
        ? 'Please enter a server URL'
        : null;
  }

  String? get _usernameError {
    if (!_isXtream) return null;
    return _usernameController.text.trim().isEmpty
        ? 'Please enter a username'
        : null;
  }

  String? get _passwordError {
    if (!_isXtream) return null;
    return _passwordController.text.trim().isEmpty
        ? 'Please enter a password'
        : null;
  }

  bool get _canSave =>
      _nameError == null &&
      _urlError == null &&
      _serverError == null &&
      _usernameError == null &&
      _passwordError == null;

  void _submit() {
    if (!_canSave) {
      // IME "done" unfocused the field; park DPAD back on the name field so TV
      // users aren't stranded on the dialog scope with errors showing.
      _nameFocusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop(
      _PlaylistEdit(
        name: _nameController.text.trim(),
        url: _urlController.text.trim(),
        serverUrl: _isXtream ? _serverController.text.trim() : null,
        username: _isXtream ? _usernameController.text.trim() : null,
        password: _isXtream ? _passwordController.text.trim() : null,
        epgUrl: _epgController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The field shells in the order they're shown, so each field's UP/DOWN can
    // point at its real neighbour regardless of type. First-field UP and
    // last-field DOWN stay null: those hops (field↔action-buttons) go through
    // the framework's directional traversal, exactly like the single-field
    // dialogs on this screen already do.
    final sequence = <FocusNode>[
      _nameFocusNode,
      if (_isUrl) _urlFocusNode,
      if (_isXtream) ...[
        _serverFocusNode,
        _usernameFocusNode,
        _passwordFocusNode,
      ],
      _epgFocusNode,
    ];
    VoidCallback? up(FocusNode n) {
      final i = sequence.indexOf(n);
      return i > 0 ? () => sequence[i - 1].requestFocus() : null;
    }

    VoidCallback? down(FocusNode n) {
      final i = sequence.indexOf(n);
      return i >= 0 && i < sequence.length - 1
          ? () => sequence[i + 1].requestFocus()
          : null;
    }

    final fields = <Widget>[
      TvTextField(
        controller: _nameController,
        focusNode: _nameFocusNode,
        labelText: 'Playlist Name',
        hintText: 'Enter a name for this playlist',
        errorText: _nameError,
        prefixIcon: const Icon(Icons.label_outline),
        // Off-TV only: on TV the action buttons seed DPAD focus (see the
        // Save/Cancel autofocus below), matching the import-name dialog — a
        // field autofocus in TV passthrough mode pops the broken system IME.
        autofocus: !PlatformUtil.isAndroidTvCached,
        textInputAction: TextInputAction.next,
        onUpArrow: up(_nameFocusNode),
        onDownArrow: down(_nameFocusNode),
      ),
      if (_isUrl) ...[
        const SizedBox(height: 12),
        TvTextField(
          controller: _urlController,
          focusNode: _urlFocusNode,
          labelText: 'Playlist URL',
          hintText: 'https://example.com/playlist.m3u',
          errorText: _urlError,
          prefixIcon: const Icon(Icons.link),
          textInputAction: TextInputAction.next,
          onUpArrow: up(_urlFocusNode),
          onDownArrow: down(_urlFocusNode),
        ),
      ],
      if (_isXtream) ...[
        const SizedBox(height: 12),
        TvTextField(
          controller: _serverController,
          focusNode: _serverFocusNode,
          labelText: 'Server URL',
          hintText: 'http://example.com:8080',
          errorText: _serverError,
          prefixIcon: const Icon(Icons.dns),
          textInputAction: TextInputAction.next,
          onUpArrow: up(_serverFocusNode),
          onDownArrow: down(_serverFocusNode),
        ),
        const SizedBox(height: 12),
        TvTextField(
          controller: _usernameController,
          focusNode: _usernameFocusNode,
          labelText: 'Username',
          hintText: 'your username',
          errorText: _usernameError,
          prefixIcon: const Icon(Icons.person),
          textInputAction: TextInputAction.next,
          onUpArrow: up(_usernameFocusNode),
          onDownArrow: down(_usernameFocusNode),
        ),
        const SizedBox(height: 12),
        TvTextField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          labelText: 'Password',
          hintText: 'your password',
          errorText: _passwordError,
          prefixIcon: const Icon(Icons.lock),
          obscureText: true,
          textInputAction: TextInputAction.next,
          onUpArrow: up(_passwordFocusNode),
          onDownArrow: down(_passwordFocusNode),
        ),
      ],
      const SizedBox(height: 12),
      TvTextField(
        controller: _epgController,
        focusNode: _epgFocusNode,
        labelText: 'EPG URL (XMLTV, optional)',
        hintText: 'https://example.com/guide.xml.gz',
        prefixIcon: const Icon(Icons.calendar_view_day_outlined),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onUpArrow: up(_epgFocusNode),
        onDownArrow: down(_epgFocusNode),
      ),
    ];

    return AlertDialog(
      title: const Text('Edit Playlist'),
      // No fixed width — let AlertDialog size to the screen (a hard width
      // overflows narrow phone dialogs). Scrollable so the taller Xtream form
      // (four fields + EPG) never overflows vertically on short screens.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isXtream)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Changing the server or credentials won\'t be re-checked '
                  'here — use Refresh afterwards to verify the login.',
                  style: TextStyle(fontSize: 12, color: kSettingsDim),
                ),
              ),
            ...fields,
          ],
        ),
      ),
      actions: [
        TextButton(
          style: _dialogButtonFocusStyle,
          // TV: seed DPAD focus on Cancel only when Save opens disabled, so
          // focus is never stranded on the dialog scope.
          autofocus: PlatformUtil.isAndroidTvCached && !_canSave,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: _dialogButtonFocusStyle,
          autofocus: PlatformUtil.isAndroidTvCached && _canSave,
          onPressed: _canSave ? _submit : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Focusable icon button for TV navigation
class _FocusableIconButton extends StatefulWidget {
  const _FocusableIconButton({
    this.focusNode,
    required this.icon,
    this.color,
    this.tooltip,
    this.isBusy = false,
    required this.onPressed,
    this.onLeftArrow,
    this.onRightArrow,
  });

  final FocusNode? focusNode;
  final IconData icon;
  final Color? color;
  final String? tooltip;
  final bool isBusy;
  final VoidCallback onPressed;
  final VoidCallback? onLeftArrow;
  final VoidCallback? onRightArrow;

  @override
  State<_FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<_FocusableIconButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusableIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      widget.focusNode?.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode?.hasFocus ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          if (!widget.isBusy) widget.onPressed();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.onLeftArrow != null) {
          widget.onLeftArrow!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
            widget.onRightArrow != null) {
          widget.onRightArrow!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      // Snap, don't tween — TV GPU rule.
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: _isFocused
              ? Border.all(color: kSettingsAccent, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: kSettingsAccent.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        // One DPAD stop per control — see _TvFocusableButton's ExcludeFocus.
        child: ExcludeFocus(
          child: IconButton(
            icon: widget.isBusy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _isFocused ? kSettingsAccent2 : widget.color,
                    ),
                  )
                : Icon(
                    widget.icon,
                    color: _isFocused ? kSettingsAccent2 : widget.color,
                  ),
            tooltip: widget.tooltip,
            onPressed: widget.isBusy ? null : widget.onPressed,
            style: IconButton.styleFrom(
              backgroundColor: _isFocused
                  ? kSettingsAccent.withValues(alpha: 0.16)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// TV-focusable back button for AppBar
class _TvFocusableBackButton extends StatefulWidget {
  const _TvFocusableBackButton({required this.focusNode, this.onDownArrow});

  final FocusNode focusNode;
  final VoidCallback? onDownArrow;

  @override
  State<_TvFocusableBackButton> createState() => _TvFocusableBackButtonState();
}

class _TvFocusableBackButtonState extends State<_TvFocusableBackButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TvFocusableBackButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
    }
  }

  void _goBack() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // Select/Enter to go back
        if (isActivateKey(event.logicalKey)) {
          _goBack();
          return KeyEventResult.handled;
        }

        // Back button to go back
        if (event.logicalKey == LogicalKeyboardKey.goBack ||
            event.logicalKey == LogicalKeyboardKey.browserBack ||
            event.logicalKey == LogicalKeyboardKey.escape) {
          _goBack();
          return KeyEventResult.handled;
        }

        // Down arrow to go to name field
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.onDownArrow != null) {
          widget.onDownArrow!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      // Snap, don't tween — TV GPU rule.
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: _isFocused
              ? Border.all(color: kSettingsAccent, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: kSettingsAccent.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        // One DPAD stop per control — see _TvFocusableButton's ExcludeFocus.
        child: ExcludeFocus(
          child: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: _isFocused ? kSettingsAccent2 : null,
            ),
            tooltip: 'Go back',
            onPressed: _goBack,
            style: IconButton.styleFrom(
              backgroundColor: _isFocused
                  ? kSettingsAccent.withValues(alpha: 0.16)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog for entering playlist name when importing from file
class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.defaultName,
    required this.channelCount,
    required this.existingNames,
  });

  final String defaultName;
  final int channelCount;
  final Set<String> existingNames;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller;
  final FocusNode _fieldFocusNode = FocusNode(
    debugLabel: 'iptv-import-name-field',
  );
  String? _errorText;
  // Whether the default name was valid on open — decides which action button
  // gets the TV autofocus (autofocus only counts on the first frame).
  late final bool _initialNameValid;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
    _controller.addListener(_validateName);
    // Validate synchronously so the Import button's enabled state is right
    // before the first frame — a post-frame validate could disable an
    // already-autofocused Import, leaving nothing focused on TV.
    _errorText = _errorFor(_controller.text);
    _initialNameValid = _errorText == null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocusNode.dispose();
    super.dispose();
  }

  String? _errorFor(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return 'Please enter a name';
    if (widget.existingNames.contains(name)) {
      return 'A playlist with this name already exists';
    }
    return null;
  }

  void _validateName() {
    setState(() => _errorText = _errorFor(_controller.text));
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty || widget.existingNames.contains(name)) {
      _validateName();
      // IME "done" just unfocused the field; put DPAD back on it so TV
      // users aren't stranded on the dialog scope with an error showing.
      _fieldFocusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name Your Playlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kSettingsGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kSettingsGreen.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: kSettingsGreen, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${widget.channelCount} channels found',
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Shared TV field idiom: on TV this is a non-editing shell (DPAD
          // landing never pops the keyboard; OK starts editing). Off-TV it
          // autofocuses with the keyboard ready, as before.
          TvTextField(
            controller: _controller,
            focusNode: _fieldFocusNode,
            labelText: 'Playlist Name',
            hintText: 'Enter a name for this playlist',
            errorText: _errorText,
            prefixIcon: const Icon(Icons.label_outline),
            // Off-TV only: on TV the dialog's action buttons seed DPAD focus
            // (below), matching the old clone which never autofocused on TV.
            autofocus: !PlatformUtil.isAndroidTvCached,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: _dialogButtonFocusStyle,
          // TV: when the default name is invalid Import opens disabled, so
          // seed DPAD focus here instead.
          autofocus: PlatformUtil.isAndroidTvCached && !_initialNameValid,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: _dialogButtonFocusStyle,
          autofocus: PlatformUtil.isAndroidTvCached && _initialNameValid,
          onPressed: _errorText == null ? _submit : null,
          child: const Text('Import'),
        ),
      ],
    );
  }

}

/// Snap accent border on DPAD focus for the dialog's action buttons — the
/// stock Material focus overlay is too faint to spot on TV.
final ButtonStyle _dialogButtonFocusStyle = ButtonStyle(
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: kSettingsAccent, width: 2)
        : null,
  ),
);
