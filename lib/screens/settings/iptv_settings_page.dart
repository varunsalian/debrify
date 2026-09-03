import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/iptv_playlist.dart';
import '../../models/profiles/profile_policy.dart';
import '../../services/iptv_catalog_key.dart';
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_service.dart';
import '../../services/xtream_codes_service.dart';
import '../../services/storage_service.dart';
import '../../services/analytics_service.dart';
import '../../utils/m3u_parser.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../../utils/tv_reveal.dart';
import '../../services/desktop_schedule_service.dart';
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/live_recording_service.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_collection_resource_facade.dart';
import '../../services/webdav_sync/webdav_sync_library_models.dart';
import '../../widgets/iptv/iptv_list_name_dialog.dart';
import 'iptv_category_order_page.dart';
import 'iptv_hidden_categories_page.dart';
import 'iptv_channel_order_page.dart';
import 'iptv_style_page.dart';
import 'player_guide_style_page.dart';
import 'recordings_page.dart';
import '../../widgets/recording_limit_dialogs.dart';
import '../../widgets/iptv/iptv_startup_channel_picker.dart';
import '../../widgets/tv_text_field.dart';
import 'iptv_settings_two_pane.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// The narrow (phone / small-window) layout's destinations. The wide layout
/// keeps its rail + pane; this is the phone-native equivalent — a hub page of
/// section rows, each opening a focused sub-view inside the SAME route (back
/// returns to the hub via PopScope, so section state and the add-form
/// controllers survive the trip).
enum _PhoneSection {
  hub,
  sources,
  lists,
  categoryOrder,
  hidden,
  startup,
  channelPreview,
  continueWatching,
  recording,
}

class IptvSettingsPage extends StatefulWidget {
  const IptvSettingsPage({super.key, this.openAddSource = false});

  /// Opened by an "Add playlist" affordance rather than from the settings
  /// list: land on the add form itself instead of making the user find it.
  /// The wide layout opens its Add pane (see [IptvSettingsTwoPane]); the
  /// single column already puts Add Playlist first, so it needs nothing.
  final bool openAddSource;

  @override
  State<IptvSettingsPage> createState() => _IptvSettingsPageState();
}

class _IptvSettingsPageState extends State<IptvSettingsPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  final FocusNode _epgUrlInputFocusNode = FocusNode(
    debugLabel: 'iptv-epg-url-input',
  );
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

  /// Focus nodes for the Lists section — its OWN array rather than an
  /// extension of [_playlistFocusNodes], whose every index is `row * 4`
  /// arithmetic that a second section would silently break.
  /// 4 per list: rename + move-up + move-down + delete.
  final List<FocusNode> _listFocusNodes = [];
  final FocusNode _createListFocusNode = FocusNode(
    debugLabel: 'iptv-create-list',
  );

  /// Focus nodes for the Hidden-categories section — one per catalog-backed
  /// source. Its own array for the same reason [_listFocusNodes] is: the
  /// arrays above are index arithmetic that a third section would break.
  final List<FocusNode> _hiddenFocusNodes = [];

  /// Hidden-category counts per playlist id, for the section's row subtitles.
  /// Read from the catalog DB on load rather than per build — a settings
  /// rebuild must not query once per source.
  Map<String, int> _hiddenCounts = const {};

  List<IptvListMeta> _lists = [];

  List<IptvPlaylist> _playlists = [];
  String? _defaultPlaylistId;

  /// True while the wide rail+pane layout is mounted. Read by the DPAD
  /// hand-offs that target the single-column layout's playlist tiles — those
  /// nodes exist but are attached to nothing here, and requesting focus on an
  /// unattached node silently strands DPAD.
  bool _twoPaneActive = false;
  final GlobalKey<IptvSettingsTwoPaneState> _twoPaneKey = GlobalKey();

  // Recording engine + scheduled recordings. The section exists where SOME
  // recorder can run: Android 10+ (engine + toggle) or desktop (in-app
  // scheduler, no toggle). On iOS/pre-Q the page must not promise recording
  // that native methods will just refuse.
  bool _recordingSectionVisible = false;
  bool _engineToggleVisible = false;
  bool _recordingEngineOn = true;
  int _scheduledCount = 0;
  int _maxConcurrent = LiveRecordingService.maxConcurrentDefault;

  /// Null while unknown / non-Android; battery exemption drives the row's
  /// label so users can see at a glance whether long recordings are safe.
  bool? _batteryExempt;
  final FocusNode _scheduledRecordingsFocusNode = FocusNode(
    debugLabel: 'iptv-scheduled-recordings',
  );
  final FocusNode _maxConcurrentFocusNode = FocusNode(
    debugLabel: 'iptv-max-concurrent',
  );
  final FocusNode _batteryFocusNode = FocusNode(
    debugLabel: 'iptv-battery-exemption',
  );

  // Startup channel
  bool _startupEnabled = false;
  String _startupMode = StorageService.startupIptvModeLast;
  Map<String, dynamic>? _startupChannel;
  Map<String, dynamic>? _lastLiveChannel;
  final FocusNode _startupChannelFocusNode = FocusNode(
    debugLabel: 'iptv-startup-channel',
  );

  // Continue watching
  bool _trackContinueWatching = true;

  // Embedded side preview while browsing channels. Providers count this as a
  // real stream, so users with tight connection limits can keep the stage's
  // artwork/details while preventing it from tuning.
  bool _channelPreviewEnabled = true;

  Future<void> _runProfileAction(Future<void> Function() body) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.iptv,
    );
    if (!mounted) return;
    if (authorization == null) {
      await body();
    } else {
      await authorization.runIfCurrent(body);
    }
  }

  // Cockpit appearance (`iptv_style`). Shown only where the cockpit exists —
  // Android TV and desktop; a phone or touch tablet would be picking a look
  // it can never see.
  String _iptvStyle = 'command';

  // In-player guide look (`iptv_player_guide_style`). Ungated: every
  // platform has a player — phones/desktop the Dart one, Android TV the
  // native one — and both read this pref at launch.
  String _playerGuideStyle = 'classic';
  static final bool _isDesktopPlatform =
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  bool get _appearanceVisible =>
      PlatformUtil.isAndroidTvCached || _isDesktopPlatform;

  bool _loading = true;
  bool _isAdding = false;
  // Ids of playlists currently being refreshed (re-fetched from source)
  final Set<String> _refreshingIds = {};

  /// Where the narrow layout is (see [_PhoneSection]). The wide layout never
  /// reads it and forces it back to [_PhoneSection.hub] so a resize can't
  /// strand back-handling in a sub-view that no longer renders.
  _PhoneSection _phoneSection = _PhoneSection.hub;

  /// The hub's first row (Sources) — DOWN from the back button and the
  /// narrow TV entry both land here, mirroring how the old single column
  /// landed on the add-form tabs.
  final FocusNode _hubSourcesFocusNode = FocusNode(
    debugLabel: 'iptv-hub-sources',
  );

  /// Non-focusable marker around whichever narrow view is showing — the
  /// picker pages' idiom: section transitions unmount the focused row, so
  /// DPAD re-seeds on the new view's first traversal descendant.
  final FocusNode _phoneViewMarker = FocusNode(
    debugLabel: 'iptv-phone-view',
    skipTraversal: true,
    canRequestFocus: false,
  );

  /// Switch the narrow layout's view. On TV-class input the old view's
  /// focused row is about to unmount, which would strand DPAD on the bare
  /// FocusScope — hand it to the new view's first control instead. Touch
  /// keeps its no-focus-ring behavior (the guard below never fires there).
  void _enterPhoneSection(_PhoneSection section) {
    setState(() => _phoneSection = section);
    if (!PlatformUtil.isAndroidTvCached) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _twoPaneActive) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary is! FocusScopeNode) return;
      _phoneViewMarker.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.screenView('iptv_settings');
    _tabController = TabController(length: 3, vsync: this);
    // Rebuild on tab change so the inactive tabs' ExcludeFocus updates —
    // otherwise DPAD traversal can wander into off-screen tab content.
    _tabController.addListener(_onTabChanged);
    // An "Add playlist" deep-link lands on the Sources sub-view, where the
    // add forms live — the hub would be an extra hop the user didn't ask for.
    if (widget.openAddSource) _phoneSection = _PhoneSection.sources;
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
    _hubSourcesFocusNode.dispose();
    _phoneViewMarker.dispose();
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
    _scheduledRecordingsFocusNode.dispose();
    _maxConcurrentFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _batteryFocusNode.dispose();
    for (final node in _playlistFocusNodes) {
      node.dispose();
    }
    for (final node in _listFocusNodes) {
      node.dispose();
    }
    for (final node in _hiddenFocusNodes) {
      node.dispose();
    }
    _createListFocusNode.dispose();
    _startupChannelFocusNode.dispose();
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

    // 4 per custom list (rename + up + down + delete). Favorites is built in
    // and has no row of its own here.
    final listsNeeded = _customLists.length * 4;
    while (_listFocusNodes.length > listsNeeded) {
      _listFocusNodes.removeLast().dispose();
    }
    while (_listFocusNodes.length < listsNeeded) {
      final index = _listFocusNodes.length;
      _listFocusNodes.add(FocusNode(debugLabel: 'iptv-list-$index'));
    }

    // One per source that can have hidden categories.
    final hiddenNeeded = _hideableSources.length;
    while (_hiddenFocusNodes.length > hiddenNeeded) {
      _hiddenFocusNodes.removeLast().dispose();
    }
    while (_hiddenFocusNodes.length < hiddenNeeded) {
      final index = _hiddenFocusNodes.length;
      _hiddenFocusNodes.add(FocusNode(debugLabel: 'iptv-hidden-$index'));
    }
  }

  /// Sources whose categories can be hidden: the ones stored as catalogs.
  /// Imported files and (elsewhere) virtual shelves never become one, so
  /// there is nothing to hide against.
  List<IptvPlaylist> get _hideableSources => [
    for (final p in _playlists)
      if (!p.isLocalFile) p,
  ];

  /// Category ordering also works for imported files: they have no catalog
  /// rows, but their saved playlist id is a stable profile-local order key.
  List<IptvPlaylist> get _categoryOrderSources => List.unmodifiable(_playlists);

  /// Every catalog key a source can store under — an Xtream login has one per
  /// content type, everything else exactly one.
  List<String> _catalogKeysFor(IptvPlaylist playlist) {
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

  Map<String, WebDavSyncCatalogOwnerReference> _catalogOwnerReferencesFor(
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
  Future<void> _openHiddenCategories(IptvPlaylist playlist) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IptvHiddenCategoriesPage(playlist: playlist),
      ),
    );
    if (!mounted) return;
    setState(_reloadHiddenCounts);
  }

  Future<void> _openCategoryOrder(IptvPlaylist playlist) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.iptv,
    );
    if (!mounted) return;
    try {
      await authorization?.runIfCurrent(() async {});
    } on StateError {
      _showSnackBar(
        'The active profile changed. Category order was not opened.',
        isError: true,
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IptvCategoryOrderPage(
          playlist: playlist,
          authorization: authorization,
        ),
      ),
    );
  }

  Future<void> _openChannelOrder() async {
    await pushSettingsPage<void>(context, const IptvChannelOrderPage());
  }

  /// Re-read how many categories each source hides. One query for every key,
  /// then summed per source.
  void _reloadHiddenCounts() {
    if (!IptvCatalogDb.isOpen) return;
    final keysBySource = <String, List<String>>{
      for (final p in _hideableSources) p.id: _catalogKeysFor(p),
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
    _hiddenCounts = out;
  }

  List<IptvListMeta> get _customLists => [
    for (final list in _lists)
      if (!list.isBuiltin) list,
  ];

  /// Subtitle for the "specific channel" row — names the pinned channel so the
  /// setting is readable without opening the picker.
  String get _startupChannelLabel {
    final channel = _startupChannel;
    if (channel == null) return 'None chosen yet';
    final name = channel['name'];
    final number = channel['channelNumber'];
    if (name is! String || name.isEmpty) return 'None chosen yet';
    return number is num ? 'CH $number  ·  $name' : name;
  }

  /// Names the remembered channel, so "last watched" is verifiable at a glance
  /// rather than a promise the user has to reboot to test.
  String get _lastLiveChannelLabel {
    final channel = _lastLiveChannel;
    final name = channel?['name'];
    if (name is! String || name.isEmpty) return 'unknown';
    final number = channel?['channelNumber'];
    return number is num ? 'CH $number  ·  $name' : name;
  }

  Future<void> _setStartupMode(String? mode) =>
      _runProfileAction(() => _setStartupModeForProfile(mode));

  Future<void> _setStartupModeForProfile(String? mode) async {
    if (mode == null) return;
    await StorageService.setStartupIptvMode(mode);
    if (mounted) setState(() => _startupMode = mode);
    // Choosing "a specific channel" with none set yet goes straight to the
    // picker — otherwise the mode is selected but inert, which reads as broken.
    if (mode == StorageService.startupIptvModePinned &&
        _startupChannel == null) {
      await _pickStartupChannel();
    }
  }

  Future<void> _setStartupEnabled(bool enabled) => _runProfileAction(() async {
    await StorageService.setStartupIptvEnabled(enabled);
    if (mounted) setState(() => _startupEnabled = enabled);
  });

  Future<void> _setTrackContinueWatching(bool value) =>
      _runProfileAction(() => _setTrackContinueWatchingForProfile(value));

  Future<void> _setTrackContinueWatchingForProfile(bool value) async {
    await StorageService.setIptvTrackContinueWatching(value);
    if (mounted) setState(() => _trackContinueWatching = value);
  }

  Future<void> _setChannelPreviewEnabled(bool value) =>
      _runProfileAction(() => _setChannelPreviewEnabledForProfile(value));

  Future<void> _setChannelPreviewEnabledForProfile(bool value) async {
    await StorageService.setIptvChannelPreviewEnabled(value);
    if (mounted) setState(() => _channelPreviewEnabled = value);
  }

  Future<void> _setIptvStyle(String style) =>
      _runProfileAction(() => _setIptvStyleForProfile(style));

  Future<void> _setIptvStyleForProfile(String style) async {
    // Persist BEFORE reflecting the choice: the IPTV page re-reads the pref
    // the moment this route pops, and an unawaited write could lose that race.
    await StorageService.setIptvStyle(style);
    if (mounted) setState(() => _iptvStyle = style);
  }

  Future<void> _setPlayerGuideStyle(String style) =>
      _runProfileAction(() => _setPlayerGuideStyleForProfile(style));

  Future<void> _setPlayerGuideStyleForProfile(String style) async {
    // Same persist-before-setState contract as [_setIptvStyle]: the player
    // reads the pref at launch, which can happen the moment this route pops.
    await StorageService.setIptvPlayerGuideStyle(style);
    if (mounted) setState(() => _playerGuideStyle = style);
  }

  Future<void> _pickStartupChannel() =>
      _runProfileAction(_pickStartupChannelForProfile);

  Future<void> _pickStartupChannelForProfile() async {
    final choice = await showIptvStartupChannelPicker(context);
    if (choice == null || !mounted) return;
    await StorageService.setStartupIptvChannel(
      choice.url,
      name: choice.name,
      playlistId: choice.playlistId,
      channelNumber: choice.channelNumber,
      group: choice.group,
      logoUrl: choice.logoUrl,
      httpHeaders: choice.httpHeaders.isEmpty ? null : choice.httpHeaders,
    );
    final stored = await StorageService.getStartupIptvChannel();
    if (mounted) setState(() => _startupChannel = stored);
  }

  Future<void> _loadSettings() async {
    // The wide layout reports per-source counts and freshness straight from
    // the catalog. Opening once here keeps every row's read synchronous —
    // a DPAD move must never await.
    try {
      await IptvCatalogDb.open();
    } catch (_) {
      // A catalog that won't open just means "no stats"; the page still works.
    }
    final playlists = await StorageService.getIptvPlaylists(forSettings: true);
    final defaultId = await StorageService.getIptvDefaultPlaylist();
    final lists = await StorageService.getIptvLists();
    final startupEnabled = await StorageService.getStartupIptvEnabled();
    final startupMode = await StorageService.getStartupIptvMode();
    final startupChannel = await StorageService.getStartupIptvChannel();
    final lastLive = await StorageService.getIptvLastLiveChannel();
    final trackCw = await StorageService.getIptvTrackContinueWatching();
    final channelPreviewEnabled =
        await StorageService.getIptvChannelPreviewEnabled();
    final iptvStyle = await StorageService.getIptvStyle();
    final playerGuideStyle = await StorageService.getIptvPlayerGuideStyle();
    final engineSupported =
        !kIsWeb &&
        Platform.isAndroid &&
        (await LiveRecordingService.engineSupport()) != 'unsupported';
    final desktopSched = DesktopScheduleService.instance.isSupported;
    final recordingEngineOn =
        engineSupported && await LiveRecordingService.engineEnabled();
    final scheduleCount = engineSupported
        ? (await LiveRecordingService.listSchedules()).length
        : desktopSched
        ? (await DesktopScheduleService.instance.list()).length
        : 0;
    final maxConcurrent = await LiveRecordingService.maxConcurrent();
    final batteryExempt = engineSupported && !PlatformUtil.isTelevision
        ? await LiveRecordingService.isIgnoringBatteryOptimizations()
        : null;

    if (!mounted) return;

    setState(() {
      _playlists = playlists;
      _defaultPlaylistId = defaultId;
      _lists = lists;
      _startupEnabled = startupEnabled;
      _startupMode = startupMode;
      _startupChannel = startupChannel;
      _lastLiveChannel = lastLive;
      _trackContinueWatching = trackCw;
      _channelPreviewEnabled = channelPreviewEnabled;
      _iptvStyle = iptvStyle;
      _playerGuideStyle = playerGuideStyle;
      _recordingSectionVisible = engineSupported || desktopSched;
      _engineToggleVisible = engineSupported;
      _recordingEngineOn = recordingEngineOn;
      _scheduledCount = scheduleCount;
      _maxConcurrent = maxConcurrent;
      _batteryExempt = batteryExempt;
      _loading = false;
    });
    _ensureFocusNodes();
    _reloadHiddenCounts();

    // TV entry focus: land on the first tab (not a TextField, so no keyboard
    // pops) so DPAD users are never stranded on nothing.
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Only a bare FocusScopeNode as primary focus means DPAD is
        // stranded — don't steal focus the user already placed somewhere.
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        // In the wide layout the tab nodes belong to the Add pane, which is
        // not what the page opens on — requesting focus on an unmounted node
        // would leave DPAD exactly as stranded as doing nothing. Ask the rail
        // instead. Keyed off the mounted widget rather than _twoPaneActive:
        // that flag is set by a later post-frame than this one.
        final twoPane = _twoPaneKey.currentState;
        if (twoPane != null) {
          // Arrived from an "Add playlist" button: hand DPAD to the add method
          // chooser, not to the rail — the user already chose the destination.
          if (widget.openAddSource) {
            twoPane.focusAddPane();
          } else {
            twoPane.focusRail();
          }
          return;
        }
        // Narrow: an add-source deep-link opened straight onto the Sources
        // sub-view where the URL tab is mounted; a normal entry sits on the
        // hub, whose first row is the landing.
        if (_phoneSection == _PhoneSection.sources) {
          _urlTabFocusNode.requestFocus();
        } else {
          _hubSourcesFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _addPlaylist() => _runProfileAction(_addPlaylistForProfile);

  Future<void> _addPlaylistForProfile() async {
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
    final playlistId = DateTime.now().microsecondsSinceEpoch.toString();
    final result = await IptvService.instance.fetchPlaylist(
      url,
      numberingSourceKey: playlistId,
      allowUnbound: true,
    );

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
      id: playlistId,
      name: name,
      url: url,
      epgUrl: epgUrl.isEmpty ? null : epgUrl,
      addedAt: DateTime.now(),
    );

    final newPlaylists = [..._playlists, playlist];
    final savedPlaylists = await StorageService.setIptvPlaylistsAndReload(
      newPlaylists,
      forSettings: true,
    );
    if (!mounted) return;

    setState(() {
      _playlists = savedPlaylists;
      _nameController.clear();
      _urlController.clear();
      _epgUrlController.clear();
      _isAdding = false;
    });
    _ensureFocusNodes();

    _showSnackBar(
      // DB-catalog mode returns an ingest receipt with empty channels — the
      // count lives on the receipt.
      'Added "$name" '
      '(${result.ingest?.channelCount ?? result.channels.length} channels)',
      isError: false,
    );
  }

  Future<void> _importFromFile() =>
      _runProfileAction(_importFromFileForProfile);

  Future<void> _importFromFileForProfile() async {
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
      if (playlistName == null || playlistName.isEmpty || !mounted) {
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
      final savedPlaylists = await StorageService.setIptvPlaylistsAndReload(
        newPlaylists,
        forSettings: true,
      );
      if (!mounted) return;

      setState(() {
        _playlists = savedPlaylists;
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

  Future<void> _addXtreamCodes() =>
      _runProfileAction(_addXtreamCodesForProfile);

  Future<void> _addXtreamCodesForProfile() async {
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
      name: customName.isEmpty
          ? '$username@${Uri.parse(serverUrl).host}'
          : customName,
      url: '',
      serverUrl: serverUrl,
      username: username,
      password: password,
      addedAt: DateTime.now(),
    );

    final newPlaylists = [..._playlists, playlist];
    final savedPlaylists = await StorageService.setIptvPlaylistsAndReload(
      newPlaylists,
      forSettings: true,
    );
    if (!mounted) return;

    setState(() {
      _playlists = savedPlaylists;
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
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.iptv,
      );
      if (!mounted) return;
      if (authorization == null) {
        await _removePlaylistForProfile(playlist);
      } else {
        await authorization.runIfCurrent(
          () => _removePlaylistForProfile(
            playlist,
            initiatingAuthorization: authorization,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar(
        'Could not remove "${playlist.name}". Please try again.',
        isError: true,
      );
    }
  }

  Future<void> _removePlaylistForProfile(
    IptvPlaylist playlist, {
    ProfileAsyncAuthorization? initiatingAuthorization,
  }) async {
    var revokeBorrowers = false;
    final resourceId = playlist.connectionResourceId;
    if (ProfileCollectionResourceFacade.active && resourceId != null) {
      final borrowerCount =
          await ProfileCollectionResourceFacade.ownedBorrowerCount(
            resourceId: resourceId,
            feature: ProfileFeature.manageConnections,
          );
      if (borrowerCount > 0) {
        final registry = ProfileBootstrap.registry;
        var authorization = await ProfileAuthorizationContext.capture(registry);
        var actor = await authorization.validate(registry);
        if (!actor.isAdmin || !actor.allows(ProfileFeature.manageProfiles)) {
          if (mounted) {
            _showSnackBar(
              'Only an Admin can remove a source shared with other profiles.',
              isError: true,
            );
          }
          return;
        }
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => IptvSharedSourceDeleteDialog(
            playlistName: playlist.name,
            borrowerCount: borrowerCount,
          ),
        );
        if (confirmed != true || !mounted) return;
        try {
          await initiatingAuthorization?.runIfCurrent(() async {});
        } on StateError {
          _showSnackBar(
            'The active profile changed. Nothing was removed.',
            isError: true,
          );
          return;
        }

        // The dialog is an async authorization boundary. Capture and verify
        // the visible actor again so an Admin confirmation cannot be replayed
        // after a profile switch, lock, or role/policy change.
        authorization = await ProfileAuthorizationContext.capture(registry);
        actor = await authorization.validate(registry);
        if (!actor.isAdmin || !actor.allows(ProfileFeature.manageProfiles)) {
          _showSnackBar(
            'Admin authorization changed. Nothing was removed.',
            isError: true,
          );
          return;
        }
        revokeBorrowers = true;
      }
    }

    final removedIndex = _playlists.indexWhere((p) => p.id == playlist.id);
    final newPlaylists = _playlists.where((p) => p.id != playlist.id).toList();
    final savedPlaylists = await StorageService.setIptvPlaylistsAndReload(
      newPlaylists,
      forSettings: true,
      revokeBorrowers: revokeBorrowers,
    );
    await IptvCatalogDb.archiveNumberingSource(playlist.id);

    // If removed playlist was the default, clear default
    if (_defaultPlaylistId == playlist.id) {
      await StorageService.setIptvDefaultPlaylist(null);
      _defaultPlaylistId = null;
    }

    // Clear caches for this playlist — the in-memory fetch cache and the
    // catalog DB rows.
    if (playlist.isXtreamCodes) {
      XtreamCodesService.instance.clearCache(playlist.serverUrl);
      await IptvCatalogDb.removeCatalogsByKeys(
        IptvCatalogKey.allForXtream(
          playlist.serverUrl!,
          playlist.username ?? '',
        ),
        forgetChannelOrders: true,
        ownerReferences: _catalogOwnerReferencesFor(playlist),
      );
    } else if (!playlist.isLocalFile && playlist.url.isNotEmpty) {
      IptvService.instance.clearCache(playlist.url);
      await IptvCatalogDb.removeCatalogsByKeys(
        [IptvCatalogKey.forUrl(playlist.url)],
        forgetChannelOrders: true,
        ownerReferences: _catalogOwnerReferencesFor(playlist),
      );
    }
    // The source's hidden categories go with it. Deliberately here and not
    // inside the catalog delete: a manual REFRESH also drops and re-ingests
    // the catalog under the same keys, and user rules must survive that.
    IptvCatalogDb.forgetHiddenGroups(
      _catalogKeysFor(playlist),
      origin: WebDavSyncMutationOrigin.user,
      ownerReferences: _catalogOwnerReferencesFor(playlist),
    );
    if (playlist.isLocalFile) {
      try {
        await IptvCatalogDb.forgetCategoryOrders([
          IptvCatalogKey.forLocalCategoryOrder(playlist.id),
        ], ownerReferences: _catalogOwnerReferencesFor(playlist));
      } catch (error) {
        // Category order is optional catalog metadata. Failure to open a
        // damaged cache must not prevent the source itself being removed.
        debugPrint(
          'IPTV settings: local category-order cleanup skipped ($error)',
        );
      }
    }
    await StorageService.removeIptvCategoryOrdersForSource(playlist.id);

    // Remove list memberships and watch history that belonged to this
    // playlist — both replay from stored metadata, so either would otherwise
    // keep offering streams that no longer authenticate. The sweep covers
    // EVERY list, not just Favorites: the provider is gone, so its channels
    // have nowhere left to play from. The lists themselves survive, possibly
    // empty.
    await StorageService.removeIptvListChannelsByPlaylistId(playlist.id);
    await StorageService.removeIptvWatchHistoryByPlaylistId(playlist.id);

    if (!mounted) return;
    setState(() => _playlists = savedPlaylists);
    // _ensureFocusNodes disposes the trailing nodes — including the one the
    // focused delete button was using — so reseed DPAD focus on the same row
    // slot of a surviving playlist (or the tab bar when the list empties).
    _ensureFocusNodes();
    if (PlatformUtil.isTelevision) {
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

  Future<void> _setDefaultPlaylist(IptvPlaylist? playlist) =>
      _runProfileAction(() => _setDefaultPlaylistForProfile(playlist));

  Future<void> _setDefaultPlaylistForProfile(IptvPlaylist? playlist) async {
    await StorageService.setIptvDefaultPlaylist(playlist?.id);
    if (!mounted) return;
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
  Future<void> _refreshPlaylist(IptvPlaylist playlist) =>
      _runProfileAction(() => _refreshPlaylistForProfile(playlist));

  Future<void> _refreshPlaylistForProfile(IptvPlaylist playlist) async {
    if (playlist.isLocalFile) return;
    if (_refreshingIds.contains(playlist.id)) return;

    setState(() => _refreshingIds.add(playlist.id));
    _showSnackBar('Refreshing "${playlist.name}"…', isError: false);

    // Drop the disk snapshots too: Refresh doubles as the user's escape
    // hatch from a stale catalog (expired login, provider emptied a
    // category) — without a snapshot the IPTV page falls back to a real
    // blocking fetch on next open, so a genuinely dead source finally shows
    // its error instead of ghost rows served from disk.
    //
    // Whole-catalog work (the delete here, the parse+ingest inside the
    // fetch) runs behind the process-wide catalog gate — but the NETWORK
    // download deliberately does not. Wrapping the whole refresh used to
    // hold the gate for up to the fetch timeout, queueing every other
    // catalog job (page maintenance, EPG scans, deletions) behind one slow
    // panel. Maintenance that interleaves during the download re-checks its
    // preconditions inside the gate, per the runExclusive contract.
    IptvParseResult result;
    try {
      if (playlist.isXtreamCodes) {
        XtreamCodesService.instance.clearCache(playlist.serverUrl);
        await IptvCatalogDb.runExclusive(
          () => IptvCatalogDb.removeCatalogsByKeys(
            IptvCatalogKey.allForXtream(
              playlist.serverUrl!,
              playlist.username ?? '',
            ),
          ),
        );
        result = await XtreamCodesService.instance.fetchLiveStreams(
          playlist.serverUrl!,
          playlist.username ?? '',
          playlist.password ?? '',
          numberingSourceKey: playlist.id,
          connectionResourceId: playlist.connectionResourceId,
          connectionResourceRevision: playlist.connectionResourceRevision,
        );
      } else {
        IptvService.instance.clearCache(playlist.url);
        await IptvCatalogDb.runExclusive(
          () => IptvCatalogDb.removeCatalogsByKeys([
            IptvCatalogKey.forUrl(playlist.url),
          ]),
        );
        result = await IptvService.instance.fetchPlaylist(
          playlist.url,
          forceRefresh: true,
          numberingSourceKey: playlist.id,
          connectionResourceId: playlist.connectionResourceId,
          connectionResourceRevision: playlist.connectionResourceRevision,
        );
      }
    } catch (e) {
      // A throw from the catalog delete (corrupt DB, locked file) used to be
      // an unhandled async error with the row stuck on its spinner.
      result = IptvParseResult(channels: [], categories: [], error: '$e');
    }

    if (!mounted) return;
    setState(() => _refreshingIds.remove(playlist.id));

    if (result.hasError) {
      _showSnackBar('Failed to refresh "${playlist.name}": ${result.error}');
    } else {
      final suffix = result.warning != null ? ' (${result.warning})' : '';
      final count = result.ingest?.channelCount ?? result.channels.length;
      _showSnackBar(
        'Updated "${playlist.name}" — $count channels$suffix',
        isError: false,
      );
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    final t = AppThemeScope.of(context).settings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? t.danger : t.success,
      ),
    );
  }

  // ── Channel lists ────────────────────────────────────────────────────────

  Future<void> _reloadLists() async {
    final lists = await StorageService.getIptvLists();
    if (!mounted) return;
    setState(() => _lists = lists);
    _ensureFocusNodes();
  }

  Future<void> _createList() => _runProfileAction(_createListForProfile);

  Future<void> _createListForProfile() async {
    final name = await showIptvListNameDialog(
      context: context,
      title: 'New list',
      confirmLabel: 'Create',
      existingNames: [for (final list in _lists) list.name],
    );
    if (name == null || !mounted) return;
    await StorageService.createIptvList(name);
    await _reloadLists();
    if (!mounted) return;
    _showSnackBar('Created "$name"', isError: false);
  }

  Future<void> _renameList(IptvListMeta list) =>
      _runProfileAction(() => _renameListForProfile(list));

  Future<void> _renameListForProfile(IptvListMeta list) async {
    final name = await showIptvListNameDialog(
      context: context,
      title: 'Rename list',
      confirmLabel: 'Save',
      initialValue: list.name,
      existingNames: [for (final entry in _lists) entry.name],
    );
    if (name == null || name == list.name || !mounted) return;
    await StorageService.renameIptvList(list.id, name);
    await _reloadLists();
  }

  Future<void> _deleteList(IptvListMeta list) =>
      _runProfileAction(() => _deleteListForProfile(list));

  Future<void> _deleteListForProfile(IptvListMeta list) async {
    final confirmed = await showDialog<bool>(
      context: context,
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
    if (confirmed != true || !mounted) return;
    await StorageService.deleteIptvList(list.id);
    await _reloadLists();
    if (!mounted) return;
    // The deleted row's focus node is gone with it; land DPAD on the same
    // slot of a surviving list, or on Create when the section empties.
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_listFocusNodes.isEmpty) {
          _focusAndReveal(_createListFocusNode);
        } else {
          _focusAndReveal(_listFocusNodes.first);
        }
      });
    }
    _showSnackBar('Deleted "${list.name}"', isError: false);
  }

  Future<void> _moveList(IptvListMeta list, int delta) =>
      _runProfileAction(() => _moveListForProfile(list, delta));

  Future<void> _moveListForProfile(IptvListMeta list, int delta) async {
    final order = [for (final entry in _customLists) entry.id];
    final index = order.indexOf(list.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= order.length) return;
    order.removeAt(index);
    order.insert(target, list.id);
    await StorageService.reorderIptvLists(order);
    await _reloadLists();
  }

  /// Rename / reorder / delete for one list, as a sheet.
  ///
  /// The single-column layout spends four DPAD stops per list on an icon
  /// strip; the wide layout spends one and opens this. Move up/down are
  /// omitted at the ends rather than shown disabled — a focusable dead
  /// control is worse than an absent one on a remote.
  Future<void> _showListActions(IptvListMeta list) async {
    final t = AppThemeScope.of(context).settings;
    final lists = _customLists;
    final index = lists.indexWhere((l) => l.id == list.id);
    if (index < 0) return;

    final action = await showModalBottomSheet<String>(
      context: context,
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

    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        await _renameList(list);
      case 'up':
        await _moveList(list, -1);
      case 'down':
        await _moveList(list, 1);
      case 'delete':
        await _deleteList(list);
    }
  }

  /// One row per catalog-backed source, each opening its own manager. Per
  /// source rather than one combined screen: the hidden set is stored per
  /// catalog, and two providers' identically-named categories are unrelated.
  List<Widget> _buildHiddenCategoriesSection() {
    final t = AppThemeScope.of(context).settings;
    final sources = _hideableSources;
    return [
      for (var i = 0; i < sources.length; i++)
        ListTile(
          focusNode: i < _hiddenFocusNodes.length ? _hiddenFocusNodes[i] : null,
          leading: Icon(
            (_hiddenCounts[sources[i].id] ?? 0) > 0
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            color: (_hiddenCounts[sources[i].id] ?? 0) > 0 ? t.accent : t.dim2,
          ),
          title: Text(
            sources[i].name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(switch (_hiddenCounts[sources[i].id] ?? 0) {
            0 => 'Nothing hidden',
            1 => '1 category hidden',
            final n => '$n categories hidden',
          }, style: TextStyle(fontSize: 12, color: t.dim)),
          trailing: Icon(Icons.chevron_right_rounded, color: t.dim2),
          onTap: () => unawaited(_openHiddenCategories(sources[i])),
        ),
    ];
  }

  List<Widget> _buildListsSection() {
    final t = AppThemeScope.of(context).settings;
    final lists = _customLists;
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
        _IptvListSettingsRow(
          list: lists[i],
          isFirst: i == 0,
          isLast: i == lists.length - 1,
          renameFocusNode: _listNodeAt(i * 4),
          upFocusNode: _listNodeAt(i * 4 + 1),
          downFocusNode: _listNodeAt(i * 4 + 2),
          deleteFocusNode: _listNodeAt(i * 4 + 3),
          onRename: () => _renameList(lists[i]),
          onMoveUp: () => _moveList(lists[i], -1),
          onMoveDown: () => _moveList(lists[i], 1),
          onDelete: () => _deleteList(lists[i]),
        ),
    ];
  }

  FocusNode? _listNodeAt(int index) =>
      index < _listFocusNodes.length ? _listFocusNodes[index] : null;

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
      final canRefresh = !playlist.isLocalFile && !playlist.connectionReadOnly;

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
            onEdit: playlist.connectionReadOnly
                ? null
                : () => _editPlaylist(playlist),
            onDelete: playlist.connectionReadOnly
                ? null
                : () => _removePlaylist(playlist),
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
  Future<void> _editPlaylist(IptvPlaylist playlist) =>
      _runProfileAction(() => _editPlaylistForProfile(playlist));

  Future<void> _editPlaylistForProfile(IptvPlaylist playlist) async {
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
              .where(
                (p) =>
                    p.id != playlist.id && !p.isXtreamCodes && !p.isLocalFile,
              )
              .map((p) => p.url)
              .toSet(),
        ),
      ),
    );
    if (result == null || !mounted) return; // cancelled or profile switched

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
      connectionResourceId: playlist.connectionResourceId,
      connectionResourceRevision: playlist.connectionResourceRevision,
      connectionReadOnly: playlist.connectionReadOnly,
      credentialsRedacted: playlist.credentialsRedacted,
    );

    final unreachableKeys = _catalogKeysFor(
      playlist,
    ).toSet().difference(_catalogKeysFor(updated).toSet());

    // Drop the stale caches when the source changed so the next load doesn't
    // serve the old channels — the in-memory fetch cache and the on-disk
    // catalog snapshots (the new source's snapshots rebuild on next load).
    if (playlist.isXtreamCodes) {
      final credsChanged =
          playlist.serverUrl != updated.serverUrl ||
          playlist.username != updated.username ||
          playlist.password != updated.password;
      if (credsChanged) {
        XtreamCodesService.instance.clearCache(playlist.serverUrl);
        XtreamCodesService.instance.clearCache(updated.serverUrl);
        await IptvCatalogDb.removeCatalogsByKeys(
          IptvCatalogKey.allForXtream(
            playlist.serverUrl!,
            playlist.username ?? '',
          ),
          forgetChannelOrders: unreachableKeys.isNotEmpty,
          ownerReferences: _catalogOwnerReferencesFor(playlist),
        );
      }
    } else if (!playlist.isLocalFile && playlist.url != updated.url) {
      IptvService.instance.clearCache(playlist.url);
      await IptvCatalogDb.removeCatalogsByKeys(
        [IptvCatalogKey.forUrl(playlist.url)],
        forgetChannelOrders: true,
        ownerReferences: _catalogOwnerReferencesFor(playlist),
      );
    }

    // Hidden-category rules follow the source's IDENTITY, not its catalogs:
    // clear only the keys this edit makes unreachable, or they sit orphaned
    // and silently reattach if that endpoint/account is ever added again.
    //
    // Set difference rather than "did anything change": a PASSWORD-only edit
    // deletes and re-ingests the catalogs above, but the key is
    // server+username+type, so its keys are unchanged and its rules must
    // survive. Same for a rename.
    IptvCatalogDb.forgetHiddenGroups(
      unreachableKeys,
      origin: WebDavSyncMutationOrigin.user,
      ownerReferences: _catalogOwnerReferencesFor(playlist),
    );

    final newPlaylists = [
      for (final p in _playlists)
        if (p.id == playlist.id) updated else p,
    ];
    final savedPlaylists = await StorageService.setIptvPlaylistsAndReload(
      newPlaylists,
      forSettings: true,
    );
    if (!mounted) return;
    setState(() => _playlists = savedPlaylists);
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
                  !_twoPaneActive &&
                      _playlists.isNotEmpty &&
                      _playlistFocusNodes.isNotEmpty
                  ? () => _focusAndReveal(_playlistFocusNodes[0])
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileTabContent() {
    final t = AppThemeScope.of(context).settings;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.folder_open,
          size: 48,
          color: t.accent2.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 16),
        Text(
          'Select an M3U or M3U8 file from your device',
          style: TextStyle(fontSize: 14, color: t.dim),
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
            onDownArrow:
                !_twoPaneActive &&
                    _playlists.isNotEmpty &&
                    _playlistFocusNodes.isNotEmpty
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
                  !_twoPaneActive &&
                      _playlists.isNotEmpty &&
                      _playlistFocusNodes.isNotEmpty
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

    return PopScope(
      // Sub-views pop back to the hub, not off the page — both the system
      // back and the AppBar back go through maybePop, so one gesture
      // contract covers both. The wide layout always sits on `hub` (the
      // LayoutBuilder below forces it), so it pops normally.
      canPop: _phoneSection == _PhoneSection.hub,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        _enterPhoneSection(_PhoneSection.hub);
      },
      child: SettingsPageScaffold(
        title: switch (_phoneSection) {
          _PhoneSection.hub => 'IPTV Playlists',
          _PhoneSection.sources => 'Sources',
          _PhoneSection.lists => 'Channel Lists',
          _PhoneSection.categoryOrder => 'Category Order',
          _PhoneSection.hidden => 'Hidden Categories',
          _PhoneSection.startup => 'Startup',
          _PhoneSection.channelPreview => 'Channel Preview',
          _PhoneSection.continueWatching => 'Continue Watching',
          _PhoneSection.recording => 'Recording',
        },
        leading: _TvFocusableBackButton(
          focusNode: _backButtonFocusNode,
          // Two-pane hands DOWN to the rail; the single column lands on the
          // currently-selected tab, not always the first one — but only the
          // Sources sub-view mounts the tabs at all; everywhere else default
          // traversal owns DOWN.
          onDownArrow: () {
            if (_twoPaneActive) {
              _twoPaneKey.currentState?.focusRail();
              return;
            }
            if (_phoneSection != _PhoneSection.sources) {
              // The back button swallows DOWN whenever a handler exists, so
              // hand focus somewhere real: whichever view is up, its first
              // focusable row (on the hub that's the Sources row).
              _phoneViewMarker.traversalDescendants.firstOrNull?.requestFocus();
              return;
            }
            _focusAndReveal(switch (_tabController.index) {
              1 => _fileTabFocusNode,
              2 => _xcTabFocusNode,
              _ => _urlTabFocusNode,
            });
          },
        ),
        // TV and desktop get the rail + detail layout; phones and narrow
        // windows keep the single column, which is the only thing that fits.
        body: LayoutBuilder(
          builder: (context, c) {
            final twoPane = c.maxWidth >= 900 && c.maxHeight >= 420;
            // Assigned synchronously, and it has to be: _buildSingleColumn
            // reads this flag *in this same pass* to decide whether the add
            // forms' DOWN key should hand off to the playlist tiles. Deferring
            // it to a post-frame meant the just-narrowed layout was built with
            // the wide layout's answer, and nothing scheduled a rebuild to
            // correct it — so DOWN stayed broken until some unrelated
            // setState. Safe because no rebuild is needed: the only other
            // readers are key handlers, which run on user input, never during
            // layout.
            _twoPaneActive = twoPane;
            // The wide layout renders no sub-views, so a resize mid-sub-view
            // must land back on the hub. Unlike _twoPaneActive this one IS
            // read by widgets built before this LayoutBuilder runs (the
            // PopScope's canPop and the scaffold title), so a bare field
            // assignment would leave them stale indefinitely — schedule a
            // rebuild for them.
            if (twoPane && _phoneSection != _PhoneSection.hub) {
              _phoneSection = _PhoneSection.hub;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }
            return twoPane ? _buildTwoPane() : _buildSingleColumn();
          },
        ),
      ),
    );
  }

  Widget _buildTwoPane() {
    return IptvSettingsTwoPane(
      key: _twoPaneKey,
      openAddSource: widget.openAddSource,
      playlists: _playlists,
      defaultPlaylistId: _defaultPlaylistId,
      refreshingIds: _refreshingIds,
      customLists: _customLists,
      startupEnabled: _startupEnabled,
      startupMode: _startupMode,
      startupChannelLabel: _startupChannelLabel,
      lastLiveChannelLabel: _lastLiveChannelLabel,
      hasStartupChannel: _startupChannel != null,
      hasLastLiveChannel: _lastLiveChannel != null,
      addMethod: _tabController.index,
      // Kept on the shared TabController so the two layouts agree about which
      // method is chosen across a resize.
      onAddMethodChanged: (i) {
        if (_tabController.index == i) return;
        setState(() => _tabController.index = i);
      },
      urlFormBuilder: (_) => _buildUrlTabContent(),
      fileFormBuilder: (_) => _buildFileTabContent(),
      xtreamFormBuilder: (_) => _buildXcTabContent(),
      // The forms' own up-arrow targets are these nodes, so reusing them for
      // the method chooser keeps every hand-off inside them valid here.
      urlMethodFocusNode: _urlTabFocusNode,
      fileMethodFocusNode: _fileTabFocusNode,
      xtreamMethodFocusNode: _xcTabFocusNode,
      onSetDefault: (p) =>
          _setDefaultPlaylist(_defaultPlaylistId == p.id ? null : p),
      onRefresh: _refreshPlaylist,
      onEdit: _editPlaylist,
      onDelete: _removePlaylist,
      onCreateList: _createList,
      onManageChannelOrder: () => unawaited(_openChannelOrder()),
      onManageCategoryOrder: (playlist) =>
          unawaited(_openCategoryOrder(playlist)),
      onManageHidden: (playlist) => unawaited(_openHiddenCategories(playlist)),
      hiddenCounts: _hiddenCounts,
      onFocusFirstFormField: () =>
          _focusAndReveal(switch (_tabController.index) {
            1 => _importFileButtonFocusNode,
            2 => _xcNameFocusNode,
            _ => _nameInputFocusNode,
          }),
      onListActions: _showListActions,
      onToggleStartup: _setStartupEnabled,
      onStartupModeChanged: _setStartupMode,
      onPickStartupChannel: _pickStartupChannel,
      channelPreviewEnabled: _channelPreviewEnabled,
      onToggleChannelPreview: _setChannelPreviewEnabled,
      trackContinueWatching: _trackContinueWatching,
      onToggleTrackContinueWatching: _setTrackContinueWatching,
      showAppearanceSection: _appearanceVisible,
      iptvStyle: _iptvStyle,
      onIptvStyleChanged: (v) => unawaited(_setIptvStyle(v)),
      playerGuideStyle: _playerGuideStyle,
      onPlayerGuideStyleChanged: (v) => unawaited(_setPlayerGuideStyle(v)),
      showRecordingSection: _recordingSectionVisible,
      showEngineToggle: _engineToggleVisible,
      recordingEngineEnabled: _recordingEngineOn,
      scheduledCount: _scheduledCount,
      onToggleRecordingEngine: (enabled) async {
        await LiveRecordingService.setEngineEnabled(enabled);
        if (mounted) setState(() => _recordingEngineOn = enabled);
      },
      onOpenScheduledRecordings: () => unawaited(_openScheduledRecordings()),
      maxConcurrentRecordings: _maxConcurrent,
      onPickMaxConcurrent: () => unawaited(_pickMaxConcurrent()),
      batteryExempt: _batteryExempt,
      onRequestBatteryExemption: () => unawaited(_requestBatteryExemption()),
    );
  }

  Widget _buildSingleColumn() {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Focus(
        focusNode: _phoneViewMarker,
        canRequestFocus: false,
        skipTraversal: true,
        child: switch (_phoneSection) {
          _PhoneSection.hub => _buildPhoneHub(),
          _PhoneSection.sources => _buildSourcesView(),
          _PhoneSection.lists => _buildListsView(),
          _PhoneSection.categoryOrder => _buildCategoryOrderView(),
          _PhoneSection.hidden => _buildHiddenView(),
          _PhoneSection.startup => _buildStartupView(),
          _PhoneSection.channelPreview => _buildChannelPreviewView(),
          _PhoneSection.continueWatching => _buildContinueWatchingView(),
          _PhoneSection.recording => _buildRecordingView(),
        },
      ),
    );
  }

  /// The narrow layout's first screen: one row per destination, mirroring
  /// the wide layout's rail. Every row quotes its live state so the hub
  /// reads as a summary, not a menu.
  Widget _buildPhoneHub() {
    // Sum only sources that still exist — a deleted source's cached count
    // must not haunt the subtitle.
    final hideableIds = {for (final p in _hideableSources) p.id};
    final hiddenTotal = _hiddenCounts.entries
        .where((e) => hideableIds.contains(e.key))
        .fold(0, (a, e) => a + e.value);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsPageHeader(
          icon: Icons.live_tv_rounded,
          title: 'IPTV Playlists',
          subtitle:
              'Sources, lists, startup and looks — everything IPTV in one '
              'place.',
        ),
        const SizedBox(height: 24),
        SettingsSection(
          title: '',
          children: [
            SettingsTile(
              focusNode: _hubSourcesFocusNode,
              icon: Icons.playlist_play_rounded,
              title: 'Sources',
              subtitle: _playlists.isEmpty
                  ? 'None yet — add your first playlist'
                  : '${_playlists.length} '
                        '${_playlists.length == 1 ? 'source' : 'sources'}',
              onTap: () async => _enterPhoneSection(_PhoneSection.sources),
            ),
            SettingsTile(
              icon: Icons.video_library_rounded,
              title: 'Channel lists',
              subtitle: _customLists.isEmpty
                  ? 'Favorites only'
                  : 'Favorites + ${_customLists.length} '
                        '${_customLists.length == 1 ? 'list' : 'lists'}',
              onTap: () async => _enterPhoneSection(_PhoneSection.lists),
            ),
            SettingsTile(
              icon: Icons.reorder_rounded,
              title: 'Channel order',
              subtitle: 'Arrange Favorites and saved lists',
              onTap: _openChannelOrder,
            ),
            if (_categoryOrderSources.isNotEmpty)
              SettingsTile(
                icon: Icons.swap_vert_rounded,
                title: 'Category order',
                subtitle: 'Arrange categories by source',
                onTap: () async =>
                    _enterPhoneSection(_PhoneSection.categoryOrder),
              ),
            if (_hideableSources.isNotEmpty)
              SettingsTile(
                icon: Icons.visibility_off_rounded,
                title: 'Hidden categories',
                subtitle: hiddenTotal == 0
                    ? 'Nothing hidden'
                    : '$hiddenTotal '
                          '${hiddenTotal == 1 ? 'category' : 'categories'} '
                          'hidden',
                onTap: () async => _enterPhoneSection(_PhoneSection.hidden),
              ),
            SettingsTile(
              icon: Icons.rocket_launch_rounded,
              title: 'Startup',
              subtitle: !_startupEnabled
                  ? 'Off'
                  : _startupMode == StorageService.startupIptvModeLast
                  ? 'Last watched channel'
                  : _startupChannelLabel,
              onTap: () async => _enterPhoneSection(_PhoneSection.startup),
            ),
            SettingsTile(
              icon: Icons.ondemand_video_rounded,
              title: 'Channel preview',
              subtitle: _channelPreviewEnabled
                  ? 'On · uses a provider stream while browsing'
                  : 'Off · no stream until you press Watch',
              onTap: () async =>
                  _enterPhoneSection(_PhoneSection.channelPreview),
            ),
            SettingsTile(
              icon: Icons.history_toggle_off_rounded,
              title: 'Continue watching',
              subtitle: _trackContinueWatching
                  ? 'Tracking movies and series'
                  : 'Off',
              onTap: () async =>
                  _enterPhoneSection(_PhoneSection.continueWatching),
            ),
            // The looks land on the same standalone pickers the Appearance
            // settings section uses — one implementation per pref.
            if (_appearanceVisible)
              SettingsTile(
                icon: Icons.style_rounded,
                title: 'Appearance',
                subtitle: iptvStyleLabel(_iptvStyle),
                onTap: () async => unawaited(_openIptvStylePicker()),
              ),
            SettingsTile(
              icon: Icons.smart_display_rounded,
              title: 'Player guide',
              subtitle: playerGuideStyleLabel(_playerGuideStyle),
              onTap: () async => unawaited(_openPlayerGuidePicker()),
            ),
            if (_recordingSectionVisible)
              SettingsTile(
                icon: Icons.fiber_manual_record_rounded,
                title: 'Recording',
                subtitle: !_engineToggleVisible
                    ? (_scheduledCount == 0
                          ? 'Recordings'
                          : '$_scheduledCount scheduled')
                    : _recordingEngineOn
                    ? (_scheduledCount == 0
                          ? 'Engine on'
                          : 'Engine on · $_scheduledCount scheduled')
                    : 'Player-tied',
                onTap: () async => _enterPhoneSection(_PhoneSection.recording),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (_defaultPlaylistId != null)
          const SettingsInfoBanner(
            text:
                'Your default playlist will load automatically when you select IPTV.',
          ),
      ],
    );
  }

  /// Same persist-then-reflect contract as the root settings screen's
  /// Appearance rows: the picker page owns the write; re-read on the way
  /// back so the hub caption matches.
  Future<void> _openIptvStylePicker() async {
    await pushSettingsPage(context, const IptvStylePage());
    if (!mounted) return;
    final style = await StorageService.getIptvStyle();
    if (mounted) setState(() => _iptvStyle = style);
  }

  Future<void> _openPlayerGuidePicker() async {
    await pushSettingsPage(context, const PlayerGuideStylePage());
    if (!mounted) return;
    final style = await StorageService.getIptvPlayerGuideStyle();
    if (mounted) setState(() => _playerGuideStyle = style);
  }

  Widget _buildSourcesView() {
    final t = AppThemeScope.of(context).settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
          style: TextStyle(fontSize: 12, color: t.dim),
        ),
        const SizedBox(height: 16),

        if (_playlists.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.playlist_add, size: 48, color: t.dim2),
                  const SizedBox(height: 12),
                  Text(
                    'No playlists yet',
                    style: TextStyle(fontSize: 14, color: t.dim),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add an M3U playlist URL above',
                    style: TextStyle(fontSize: 12, color: t.dim2),
                  ),
                ],
              ),
            ),
          )
        else
          Card(child: Column(children: _buildPlaylistsList())),
        const SizedBox(height: 24),
        if (_defaultPlaylistId != null)
          const SettingsInfoBanner(
            text:
                'Your default playlist will load automatically when you select IPTV.',
          ),
      ],
    );
  }

  Widget _buildListsView() {
    final t = AppThemeScope.of(context).settings;
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
              ..._buildListsSection(),
              _FocusableSettingsTile(
                focusNode: _createListFocusNode,
                icon: Icons.add_rounded,
                label: 'Create list',
                onTap: _createList,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryOrderView() {
    final t = AppThemeScope.of(context).settings;
    final sources = _categoryOrderSources;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Category order'),
        Text(
          'Choose a source, then arrange its category chips and guide '
          'sections. Channels inside each category keep provider order.',
          style: TextStyle(fontSize: 12, color: t.dim),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              for (final source in sources)
                ListTile(
                  leading: Icon(Icons.swap_vert_rounded, color: t.accent),
                  title: Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    source.isXtreamCodes
                        ? 'Live TV, Movies and Series'
                        : 'Playlist categories',
                    style: TextStyle(fontSize: 12, color: t.dim),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: t.dim2),
                  onTap: () => unawaited(_openCategoryOrder(source)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // One row per source that stores a catalog. The hub hides its row when no
  // source qualifies, so this view never renders empty.
  Widget _buildHiddenView() {
    final t = AppThemeScope.of(context).settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Hidden categories'),
        Text(
          'Open a category\'s menu (or long-press it) in the IPTV page\'s '
          'category picker, then choose Hide category. Nothing is deleted — '
          'bring it back here any time.',
          style: TextStyle(fontSize: 12, color: t.dim),
        ),
        const SizedBox(height: 16),
        Card(child: Column(children: _buildHiddenCategoriesSection())),
      ],
    );
  }

  Widget _buildStartupView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Startup'),
        const SizedBox(height: 6),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Start on a channel'),
                subtitle: const Text(
                  'Open straight into a live channel when the app starts. '
                  'Press BACK while it is tuning to stop.',
                ),
                value: _startupEnabled,
                onChanged: _setStartupEnabled,
              ),
              if (_startupEnabled) ...[
                const Divider(height: 1),
                RadioListTile<String>(
                  title: const Text('Last watched channel'),
                  subtitle: Text(
                    _lastLiveChannel == null
                        // Honest about the bootstrap: the first boot after
                        // enabling this has nothing to resume, and silently
                        // doing nothing reads as broken.
                        ? 'Nothing watched yet — starts on the first '
                              'channel, then remembers what you watch.'
                        : 'Currently: $_lastLiveChannelLabel',
                  ),
                  value: StorageService.startupIptvModeLast,
                  groupValue: _startupMode,
                  onChanged: _setStartupMode,
                ),
                RadioListTile<String>(
                  title: const Text('A specific channel'),
                  subtitle: Text(_startupChannelLabel),
                  value: StorageService.startupIptvModePinned,
                  groupValue: _startupMode,
                  onChanged: _setStartupMode,
                ),
                if (_startupMode == StorageService.startupIptvModePinned)
                  _FocusableSettingsTile(
                    focusNode: _startupChannelFocusNode,
                    icon: Icons.live_tv_rounded,
                    label: _startupChannel == null
                        ? 'Choose channel'
                        : 'Change channel',
                    onTap: _pickStartupChannel,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContinueWatchingView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Continue watching'),
        const SizedBox(height: 6),
        Card(
          child: SwitchListTile(
            title: const Text('Track movies and series'),
            subtitle: const Text(
              'Keeps a Continue watching shelf of the on-demand items you '
              'start, on Home and in IPTV. Off hides it and stops adding to '
              'it — nothing is deleted, and playback still resumes where '
              'you left off.',
            ),
            value: _trackContinueWatching,
            onChanged: _setTrackContinueWatching,
          ),
        ),
      ],
    );
  }

  Widget _buildChannelPreviewView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Channel preview'),
        const SizedBox(height: 6),
        Card(
          child: SwitchListTile(
            title: const Text('Play channel previews'),
            subtitle: const Text(
              'Plays the focused channel in the side panel while you browse. '
              'This opens a provider stream and may count toward your '
              'connection limit. Fullscreen playback still works when off.',
            ),
            value: _channelPreviewEnabled,
            onChanged: _setChannelPreviewEnabled,
          ),
        ),
      ],
    );
  }

  // The Appearance and Player guide looks are NOT sub-views: their hub rows
  // push the same standalone picker pages the root Appearance section uses,
  // so each pref keeps exactly one narrow-layout picker implementation.

  // Gated by the hub row (engine support / desktop scheduler), so this view
  // never renders where recording can't run.
  Widget _buildRecordingView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsSectionLabel('Recording'),
        const SizedBox(height: 6),
        Card(
          child: Column(
            children: [
              if (_engineToggleVisible)
                SwitchListTile(
                  title: const Text('Background recording engine'),
                  subtitle: const Text(
                    'Recordings keep running when you zap or leave the '
                    'app, and programmes can be scheduled from the TV '
                    'guide. Off returns to player-tied recording. Uses an '
                    'extra connection to your provider.',
                  ),
                  value: _recordingEngineOn,
                  onChanged: (enabled) async {
                    await LiveRecordingService.setEngineEnabled(enabled);
                    if (mounted) {
                      setState(() => _recordingEngineOn = enabled);
                    }
                  },
                ),
              if (!_engineToggleVisible || _recordingEngineOn) ...[
                if (_engineToggleVisible) const Divider(height: 1),
                _FocusableSettingsTile(
                  focusNode: _maxConcurrentFocusNode,
                  icon: Icons.filter_none_rounded,
                  label: 'Simultaneous recordings ($_maxConcurrent)',
                  onTap: _pickMaxConcurrent,
                ),
                if (_batteryExempt != null) ...[
                  const Divider(height: 1),
                  _FocusableSettingsTile(
                    focusNode: _batteryFocusNode,
                    icon: Icons.battery_alert_rounded,
                    label: _batteryExempt == true
                        ? 'Battery optimization — excluded ✓'
                        : 'Battery optimization — tap to exclude',
                    onTap: _requestBatteryExemption,
                  ),
                ],
                const Divider(height: 1),
                _FocusableSettingsTile(
                  focusNode: _scheduledRecordingsFocusNode,
                  icon: Icons.fiber_manual_record_rounded,
                  label: _scheduledCount == 0
                      ? 'Recordings'
                      : 'Recordings ($_scheduledCount scheduled)',
                  onTap: _openScheduledRecordings,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The exemption dialog is a separate activity: the request call returns
  /// the moment it LAUNCHES, so reading state right after it sees the old
  /// value. The truth arrives when this app resumes.
  bool _recheckBatteryOnResume = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_recheckBatteryOnResume) return;
    _recheckBatteryOnResume = false;
    unawaited(
      LiveRecordingService.isIgnoringBatteryOptimizations().then((exempt) {
        if (mounted) setState(() => _batteryExempt = exempt);
      }),
    );
  }

  Future<void> _requestBatteryExemption() async {
    _recheckBatteryOnResume = true;
    await LiveRecordingService.requestIgnoreBatteryOptimizations();
  }

  Future<void> _pickMaxConcurrent() async {
    final picked = await showRecordingLimitPicker(context);
    if (picked != null && mounted) setState(() => _maxConcurrent = picked);
  }

  Future<void> _openScheduledRecordings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RecordingsPage()));
    // Additions/cancellations on the page change the count shown here.
    final count = DesktopScheduleService.instance.isSupported
        ? (await DesktopScheduleService.instance.list()).length
        : (await LiveRecordingService.listSchedules()).length;
    if (mounted) setState(() => _scheduledCount = count);
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
  /// Live, never cached — Flutter can skip the falling edge of a focus
  /// notification, and a remembered flag then survives the change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `widgets/settings_widgets.dart`.
  bool get _isFocused => widget.focusNode.hasFocus;

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
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
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
          border: _isFocused ? Border.all(color: t.accent2, width: 2) : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.3),
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
              backgroundColor: _isFocused ? t.accent2 : null,
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
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: app.shape.br(12),
        border: Border.all(color: t.line),
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
                              ? t.accent.withValues(alpha: 0.22)
                              : Colors.transparent,
                          borderRadius: app.shape.br(8),
                          border: _urlTabFocused
                              ? Border.all(color: t.accent, width: 2)
                              : null,
                          boxShadow: _urlTabFocused
                              ? [
                                  BoxShadow(
                                    color: t.accent.withValues(alpha: 0.3),
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
                              color: isSelected ? t.accent2 : t.dim,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'From URL',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isSelected ? app.core.tx : t.dim,
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
                              ? t.accent.withValues(alpha: 0.22)
                              : Colors.transparent,
                          borderRadius: app.shape.br(8),
                          border: _fileTabFocused
                              ? Border.all(color: t.accent, width: 2)
                              : null,
                          boxShadow: _fileTabFocused
                              ? [
                                  BoxShadow(
                                    color: t.accent.withValues(alpha: 0.3),
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
                              color: isSelected ? t.accent2 : t.dim,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'From File',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isSelected ? app.core.tx : t.dim,
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
                                ? t.accent.withValues(alpha: 0.22)
                                : Colors.transparent,
                            borderRadius: app.shape.br(8),
                            border: _xcTabFocused
                                ? Border.all(color: t.accent, width: 2)
                                : null,
                            boxShadow: _xcTabFocused
                                ? [
                                    BoxShadow(
                                      color: t.accent.withValues(alpha: 0.3),
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
                                color: isSelected ? t.accent2 : t.dim,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Xtream Login',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: isSelected ? app.core.tx : t.dim,
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
    this.onEdit,
    this.onDelete,
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
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
    final t = AppThemeScope.of(context).settings;
    final isAnyFocused =
        _starFocused || _refreshFocused || _editFocused || _deleteFocused;
    final canRefresh = widget.onRefresh != null;

    // Snap, don't tween — TV GPU rule.
    return Container(
      decoration: BoxDecoration(
        color: isAnyFocused ? t.panel2 : null,
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
          color: widget.isDefault ? t.warning : null,
        ),
        title: Text(widget.playlist.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.playlist.credentialsRedacted) ...[
                  Icon(Icons.lock_outline, size: 12, color: t.dim),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Shared connection • credentials hidden',
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ),
                ] else if (widget.playlist.isXtreamCodes) ...[
                  Icon(Icons.login, size: 12, color: t.dim),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Xtream Codes - ${widget.playlist.serverUrl}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ),
                ] else if (widget.playlist.isLocalFile) ...[
                  Icon(Icons.sd_card, size: 12, color: t.dim),
                  const SizedBox(width: 4),
                  Text(
                    'Local file',
                    style: TextStyle(fontSize: 12, color: t.dim),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      widget.playlist.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ),
              ],
            ),
            if ((widget.playlist.epgUrl ?? '').isNotEmpty)
              Text(
                'Custom EPG URL set',
                style: TextStyle(color: t.dim, fontSize: 12),
              ),
            if (widget.isDefault)
              Text(
                'Default playlist',
                style: TextStyle(color: t.warning, fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FocusableIconButton(
              focusNode: widget.starFocusNode,
              icon: widget.isDefault ? Icons.star : Icons.star_border,
              color: widget.isDefault ? t.warning : null,
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
            if (widget.onEdit != null)
              _FocusableIconButton(
                focusNode: widget.editFocusNode,
                icon: Icons.edit_outlined,
                tooltip: 'Edit playlist',
                onPressed: widget.onEdit,
                onLeftArrow: () =>
                    (canRefresh
                            ? widget.refreshFocusNode
                            : widget.starFocusNode)
                        ?.requestFocus(),
                onRightArrow: () => widget.deleteFocusNode?.requestFocus(),
              ),
            if (widget.onDelete != null)
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

/// Confirmation used when an Admin removes a source granted to other profiles.
/// Public so its remote-key contract can be covered without bootstrapping the
/// entire profile-backed settings page in a widget test.
class IptvSharedSourceDeleteDialog extends StatefulWidget {
  const IptvSharedSourceDeleteDialog({
    super.key,
    required this.playlistName,
    required this.borrowerCount,
  });

  final String playlistName;
  final int borrowerCount;

  @override
  State<IptvSharedSourceDeleteDialog> createState() =>
      _SharedIptvSourceDeleteDialogState();
}

class _SharedIptvSourceDeleteDialogState
    extends State<IptvSharedSourceDeleteDialog> {
  final FocusNode _cancelFocusNode = FocusNode(
    debugLabel: 'shared-iptv-delete-cancel',
  );
  final FocusNode _okFocusNode = FocusNode(debugLabel: 'shared-iptv-delete-ok');

  @override
  void dispose() {
    _cancelFocusNode.dispose();
    _okFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent && isActivateOrSpaceKey(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _cancelFocusNode.requestFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _okFocusNode.requestFocus();
        return KeyEventResult.handled;
    }
    if (!isActivateOrSpaceKey(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    Navigator.of(context).pop(_okFocusNode.hasFocus);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.borrowerCount == 1
        ? '1 other profile'
        : '${widget.borrowerCount} other profiles';
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onKeyEvent,
      child: AlertDialog(
        title: const Text('Remove shared source?'),
        content: Text(
          '"${widget.playlistName}" is shared with $profiles. Removing it '
          'will also remove access to this source from those profiles.',
        ),
        actions: [
          TextButton(
            focusNode: _cancelFocusNode,
            autofocus: true,
            style: _dialogButtonFocusStyle,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            focusNode: _okFocusNode,
            style: _dialogButtonFocusStyle,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
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
  final FocusNode _usernameFocusNode = FocusNode(
    debugLabel: 'iptv-edit-username',
  );
  final FocusNode _passwordFocusNode = FocusNode(
    debugLabel: 'iptv-edit-password',
  );
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
    final t = AppThemeScope.of(context).settings;
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
        autofocus: !PlatformUtil.isTelevision,
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
                  style: TextStyle(fontSize: 12, color: t.dim),
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
          autofocus: PlatformUtil.isTelevision && !_canSave,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: _dialogButtonFocusStyle,
          autofocus: PlatformUtil.isTelevision && _canSave,
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
  final VoidCallback? onPressed;
  final VoidCallback? onLeftArrow;
  final VoidCallback? onRightArrow;

  @override
  State<_FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<_FocusableIconButton> {
  /// Live, never cached — Flutter can skip the falling edge of a focus
  /// notification, and a remembered flag then survives the change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `widgets/settings_widgets.dart`.
  bool get _isFocused => widget.focusNode?.hasFocus ?? false;

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
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          if (!widget.isBusy) widget.onPressed?.call();
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
          border: _isFocused ? Border.all(color: t.accent, width: 2) : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.3),
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
                      color: _isFocused ? t.accent2 : widget.color,
                    ),
                  )
                : Icon(
                    widget.icon,
                    color: _isFocused ? t.accent2 : widget.color,
                  ),
            tooltip: widget.tooltip,
            onPressed: widget.isBusy ? null : widget.onPressed,
            style: IconButton.styleFrom(
              backgroundColor: _isFocused
                  ? t.accent.withValues(alpha: 0.16)
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
  /// Live, never cached — Flutter can skip the falling edge of a focus
  /// notification, and a remembered flag then survives the change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `widgets/settings_widgets.dart`.
  bool get _isFocused => widget.focusNode.hasFocus;

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
      setState(() {});
    }
  }

  void _goBack() {
    if (mounted) {
      // maybePop, not pop: the page's PopScope turns a sub-view back press
      // into "return to the hub" — a direct pop would bypass it and close
      // the whole page from anywhere.
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
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
          border: _isFocused ? Border.all(color: t.accent, width: 2) : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        // One DPAD stop per control — see _TvFocusableButton's ExcludeFocus.
        child: ExcludeFocus(
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: _isFocused ? t.accent2 : null),
            tooltip: 'Go back',
            onPressed: _goBack,
            style: IconButton.styleFrom(
              backgroundColor: _isFocused
                  ? t.accent.withValues(alpha: 0.16)
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
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return AlertDialog(
      title: const Text('Name Your Playlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.success.withValues(alpha: 0.08),
              borderRadius: app.shape.br(8),
              border: Border.all(color: t.success.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: t.success, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${widget.channelCount} channels found',
                  style: TextStyle(fontSize: 14, color: app.core.tx),
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
            autofocus: !PlatformUtil.isTelevision,
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
          autofocus: PlatformUtil.isTelevision && !_initialNameValid,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: _dialogButtonFocusStyle,
          autofocus: PlatformUtil.isTelevision && _initialNameValid,
          onPressed: _errorText == null ? _submit : null,
          child: const Text('Import'),
        ),
      ],
    );
  }
}

/// Snap accent border on DPAD focus for the dialog's action buttons — the
/// stock Material focus overlay is too faint to spot on TV.
/// TOP-LEVEL final, so it cannot read a BuildContext: this one keeps the
/// `kSettingsAccent` constant until it becomes a function of context.
final ButtonStyle _dialogButtonFocusStyle = ButtonStyle(
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: kSettingsAccent, width: 2)
        : null,
  ),
);

/// One custom list in the Settings "Your Lists" section: name, count, and the
/// four actions. Each action carries its own focus node so DPAD walks them in
/// reading order.
class _IptvListSettingsRow extends StatelessWidget {
  final IptvListMeta list;
  final bool isFirst;
  final bool isLast;
  final FocusNode? renameFocusNode;
  final FocusNode? upFocusNode;
  final FocusNode? downFocusNode;
  final FocusNode? deleteFocusNode;
  final VoidCallback onRename;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  const _IptvListSettingsRow({
    required this.list,
    required this.isFirst,
    required this.isLast,
    required this.renameFocusNode,
    required this.upFocusNode,
    required this.downFocusNode,
    required this.deleteFocusNode,
    required this.onRename,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.bookmark_rounded, size: 20, color: t.dim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  list.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  list.channelCount == 1
                      ? '1 channel'
                      : '${list.channelCount} channels',
                  style: TextStyle(fontSize: 12, color: t.dim2),
                ),
              ],
            ),
          ),
          _FocusableIconButton(
            focusNode: renameFocusNode,
            icon: Icons.edit_outlined,
            tooltip: 'Rename',
            onPressed: onRename,
          ),
          // The ends of the list keep their arrows for a stable focus order,
          // but a no-op move would just be a dead keypress — skip it.
          _FocusableIconButton(
            focusNode: upFocusNode,
            icon: Icons.keyboard_arrow_up_rounded,
            color: isFirst ? t.dim2 : null,
            tooltip: 'Move up',
            onPressed: isFirst ? () {} : onMoveUp,
          ),
          _FocusableIconButton(
            focusNode: downFocusNode,
            icon: Icons.keyboard_arrow_down_rounded,
            color: isLast ? t.dim2 : null,
            tooltip: 'Move down',
            onPressed: isLast ? () {} : onMoveDown,
          ),
          _FocusableIconButton(
            focusNode: deleteFocusNode,
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Plain focusable action row for the Lists section header actions.
class _FocusableSettingsTile extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FocusableSettingsTile({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return ListTile(
      focusNode: focusNode,
      leading: Icon(icon, color: t.accent),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
