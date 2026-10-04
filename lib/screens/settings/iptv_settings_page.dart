import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_list_row.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sections.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_composition.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart';
export 'package:debrify/features/iptv_settings/presentation/iptv_shared_source_delete_dialog.dart'
    show IptvSharedSourceDeleteDialog;
import 'package:debrify/features/iptv_settings/presentation/iptv_settings_tv_button.dart';
import 'package:debrify/features/iptv_settings/presentation/iptv_settings_tv_tab_bar.dart';
import 'package:debrify/features/iptv_settings/presentation/iptv_settings_playlist_tile.dart';
import 'package:debrify/features/iptv_settings/presentation/iptv_settings_back_button.dart';
import 'package:debrify/features/iptv_settings/presentation/iptv_settings_focusable_tile.dart';
import 'package:debrify/features/iptv_settings/models/iptv_settings_phone_section.dart';
import 'package:debrify/features/iptv_settings/application/normalize_xtream_server_url.dart';
import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';
import '../../utils/platform_util.dart';
import '../../services/live_recording_service.dart';
import 'iptv_style_page.dart';
import 'player_guide_style_page.dart';
import '../../widgets/tv_text_field.dart';
import 'iptv_settings_two_pane.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

class IptvSettingsPage extends StatefulWidget {
  const IptvSettingsPage({super.key, this.openAddSource = false});

  @visibleForTesting
  static bool showsAppearance({
    required bool isTelevision,
    required bool isDesktop,
  }) => isTelevision || isDesktop;

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
  final _focus = IptvSettingsFocusOwner();
  final _input = IptvSettingsInputOwner();
  final _sources = IptvSettingsSourcesOwner();
  final _preferences = IptvSettingsPreferencesOwner();
  final r = IptvSettingsRecordingOwner();
  final l = IptvSettingsLayoutOwner();
  IptvSettingsSections? _sectionCache;
  IptvSettingsSections get _sections =>
      _sectionCache ??= createIptvSettingsSections(
        (
          mounted: () => mounted,
          setState: setState,
          twoPaneKey: _twoPaneKey,
          openAddSource: () => widget.openAddSource,
          context: () => context,
        ),
        (
          focusOwner: _focus,
          inputOwner: _input,
          sourcesOwner: _sources,
          preferencesOwner: _preferences,
          recordingOwner: r,
          layoutOwner: l,
        ),
      );

  final GlobalKey<IptvSettingsTwoPaneState> _twoPaneKey = GlobalKey();
  static final bool _isDesktopPlatform =
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  bool get _appearanceVisible => IptvSettingsPage.showsAppearance(
    isTelevision: PlatformUtil.isTelevision,
    isDesktop: _isDesktopPlatform,
  );

  /// Switch the narrow layout's view. On TV-class input the old view's
  /// focused row is about to unmount, which would strand DPAD on the bare
  /// FocusScope — hand it to the new view's first control instead. Touch
  /// keeps its no-focus-ring behavior (the guard below never fires there).
  void _enterPhoneSection(IptvSettingsPhoneSection section) {
    setState(() => l.phoneSection = section);
    if (!PlatformUtil.isAndroidTvCached) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || l.twoPaneActive) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary is! FocusScopeNode) return;
      _focus.phoneViewMarker.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.screenView('iptv_settings');
    _input.tabController = TabController(length: 3, vsync: this);
    // Rebuild on tab change so the inactive tabs' ExcludeFocus updates —
    // otherwise DPAD traversal can wander into off-screen tab content.
    _input.tabController.addListener(_onTabChanged);
    // An "Add playlist" deep-link lands on the Sources sub-view, where the
    // add forms live — the hub would be an extra hop the user didn't ask for.
    if (widget.openAddSource) l.phoneSection = IptvSettingsPhoneSection.sources;
    _sections.loadSettings.loadSettings();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _input.tabController.removeListener(_onTabChanged);
    _input.tabController.dispose();
    _input.nameController.dispose();
    _input.urlController.dispose();
    _input.epgUrlController.dispose();
    _focus.backButtonFocusNode.dispose();
    _focus.hubSourcesFocusNode.dispose();
    _focus.phoneViewMarker.dispose();
    _focus.nameInputFocusNode.dispose();
    _focus.urlInputFocusNode.dispose();
    _focus.epgUrlInputFocusNode.dispose();
    _focus.addButtonFocusNode.dispose();
    _focus.importFileButtonFocusNode.dispose();
    _input.xcNameController.dispose();
    _input.xcServerController.dispose();
    _input.xcUsernameController.dispose();
    _input.xcPasswordController.dispose();
    _focus.xcNameFocusNode.dispose();
    _focus.xcServerFocusNode.dispose();
    _focus.xcUsernameFocusNode.dispose();
    _focus.xcPasswordFocusNode.dispose();
    _focus.xcLoginButtonFocusNode.dispose();
    _focus.urlTabFocusNode.dispose();
    _focus.fileTabFocusNode.dispose();
    _focus.xcTabFocusNode.dispose();
    _focus.scheduledRecordingsFocusNode.dispose();
    _focus.maxConcurrentFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _focus.batteryFocusNode.dispose();
    for (final node in _focus.playlistFocusNodes) {
      node.dispose();
    }
    for (final node in _focus.listFocusNodes) {
      node.dispose();
    }
    for (final node in _focus.hiddenFocusNodes) {
      node.dispose();
    }
    _focus.createListFocusNode.dispose();
    _focus.startupChannelFocusNode.dispose();
    super.dispose();
  }

  /// One row per catalog-backed source, each opening its own manager. Per
  /// source rather than one combined screen: the hidden set is stored per
  /// catalog, and two providers' identically-named categories are unrelated.
  List<Widget> _buildHiddenCategoriesSection() {
    final t = AppThemeScope.of(context).settings;
    final sources = _sections.catalogActions.hideableSources;
    return [
      for (var i = 0; i < sources.length; i++)
        ListTile(
          focusNode: i < _focus.hiddenFocusNodes.length
              ? _focus.hiddenFocusNodes[i]
              : null,
          leading: Icon(
            (_sources.hiddenCounts[sources[i].id] ?? 0) > 0
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            color: (_sources.hiddenCounts[sources[i].id] ?? 0) > 0
                ? t.accent
                : t.dim2,
          ),
          title: Text(
            sources[i].name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(switch (_sources.hiddenCounts[sources[i].id] ?? 0) {
            0 => 'Nothing hidden',
            1 => '1 category hidden',
            final n => '$n categories hidden',
          }, style: TextStyle(fontSize: 12, color: t.dim)),
          trailing: Icon(Icons.chevron_right_rounded, color: t.dim2),
          onTap: () => unawaited(
            _sections.catalogActions.openHiddenCategories(sources[i]),
          ),
        ),
    ];
  }

  List<Widget> _buildListsSection() {
    final t = AppThemeScope.of(context).settings;
    final lists = _sections.listsActions.customLists;
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
        IptvSettingsListRow(
          list: lists[i],
          isFirst: i == 0,
          isLast: i == lists.length - 1,
          renameFocusNode: _sections.listsActions.listNodeAt(i * 4),
          upFocusNode: _sections.listsActions.listNodeAt(i * 4 + 1),
          downFocusNode: _sections.listsActions.listNodeAt(i * 4 + 2),
          deleteFocusNode: _sections.listsActions.listNodeAt(i * 4 + 3),
          onRename: () => _sections.listsActions.renameList(lists[i]),
          onMoveUp: () => _sections.listsActions.moveList(lists[i], -1),
          onMoveDown: () => _sections.listsActions.moveList(lists[i], 1),
          onDelete: () => _sections.listsActions.deleteList(lists[i]),
        ),
    ];
  }

  List<Widget> _buildPlaylistsList() {
    final items = <Widget>[];

    for (int i = 0; i < _sources.playlists.length; i++) {
      final playlist = _sources.playlists[i];
      final isDefault = _sources.defaultPlaylistId == playlist.id;
      final starFocusIndex = i * 4;
      final refreshFocusIndex = i * 4 + 1;
      final editFocusIndex = i * 4 + 2;
      final deleteFocusIndex = i * 4 + 3;
      // URL and Xtream Codes playlists can be re-fetched; local files cannot.
      final canRefresh = !playlist.isLocalFile && !playlist.connectionReadOnly;

      items.add(
        FocusTraversalOrder(
          order: NumericFocusOrder(5.0 + i),
          child: IptvSettingsPlaylistTile(
            playlist: playlist,
            isDefault: isDefault,
            isRefreshing: _sources.refreshingIds.contains(playlist.id),
            starFocusNode: starFocusIndex < _focus.playlistFocusNodes.length
                ? _focus.playlistFocusNodes[starFocusIndex]
                : null,
            refreshFocusNode:
                refreshFocusIndex < _focus.playlistFocusNodes.length
                ? _focus.playlistFocusNodes[refreshFocusIndex]
                : null,
            editFocusNode: editFocusIndex < _focus.playlistFocusNodes.length
                ? _focus.playlistFocusNodes[editFocusIndex]
                : null,
            deleteFocusNode: deleteFocusIndex < _focus.playlistFocusNodes.length
                ? _focus.playlistFocusNodes[deleteFocusIndex]
                : null,
            onSetDefault: () => _sections.sourceRefresh.setDefaultPlaylist(
              isDefault ? null : playlist,
            ),
            onRefresh: canRefresh
                ? () => _sections.sourceRefresh.refreshPlaylist(playlist)
                : null,
            onEdit: playlist.connectionReadOnly
                ? null
                : () => _sections.sourceEdit.editPlaylist(playlist),
            onDelete: playlist.connectionReadOnly
                ? null
                : () => _sections.sourceRemoval.removePlaylist(playlist),
          ),
        ),
      );
    }

    return items;
  }

  Widget _buildUrlTabContent() {
    return Column(
      children: [
        // Name input
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: TvTextField(
            controller: _input.nameController,
            focusNode: _focus.nameInputFocusNode,
            labelText: 'Playlist Name',
            hintText: 'e.g., My IPTV',
            prefixIcon: const Icon(Icons.label_outline),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                _sections.focusActions.focusAndReveal(_focus.urlInputFocusNode),
            // Explicit exits: UP targets the SELECTED tab (geometric search
            // from a full-width field center-lands on the middle tab).
            onUpArrow: () =>
                _sections.focusActions.focusAndReveal(_focus.urlTabFocusNode),
            onDownArrow: () =>
                _sections.focusActions.focusAndReveal(_focus.urlInputFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // URL input
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: TvTextField(
            controller: _input.urlController,
            focusNode: _focus.urlInputFocusNode,
            labelText: 'Playlist URL',
            hintText: 'https://example.com/playlist.m3u',
            prefixIcon: const Icon(Icons.link),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _sections.focusActions.focusAndReveal(
              _focus.epgUrlInputFocusNode,
            ),
            onUpArrow: () => _sections.focusActions.focusAndReveal(
              _focus.nameInputFocusNode,
            ),
            onDownArrow: () => _sections.focusActions.focusAndReveal(
              _focus.epgUrlInputFocusNode,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // EPG URL input (optional). Playlists that declare url-tvg in their
        // own header don't need it; this overrides when both exist.
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: TvTextField(
            controller: _input.epgUrlController,
            focusNode: _focus.epgUrlInputFocusNode,
            labelText: 'EPG URL (XMLTV, optional)',
            hintText: 'https://example.com/guide.xml.gz',
            prefixIcon: const Icon(Icons.calendar_view_day_outlined),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              // IME "done" unfocuses the field — park DPAD on the button so
              // focus isn't stranded on the bare scope while the add runs.
              _focus.addButtonFocusNode.requestFocus();
              _sections.urlAdd.addPlaylist();
            },
            onUpArrow: () =>
                _sections.focusActions.focusAndReveal(_focus.urlInputFocusNode),
            onDownArrow: () => _sections.focusActions.focusAndReveal(
              _focus.addButtonFocusNode,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Add button
        FocusTraversalOrder(
          // 4.5: after the EPG field, before the playlist tiles at 5.0 + i.
          order: const NumericFocusOrder(4.5),
          child: Align(
            alignment: Alignment.centerRight,
            child: IptvSettingsTvButton(
              focusNode: _focus.addButtonFocusNode,
              icon: _input.isAdding ? Icons.hourglass_empty : Icons.add,
              label: _input.isAdding ? 'Adding...' : 'Add Playlist',
              onPressed: _input.isAdding ? () {} : _sections.urlAdd.addPlaylist,
              onUpArrow: () => _sections.focusActions.focusAndReveal(
                _focus.epgUrlInputFocusNode,
              ),
              onDownArrow:
                  !l.twoPaneActive &&
                      _sources.playlists.isNotEmpty &&
                      _focus.playlistFocusNodes.isNotEmpty
                  ? () => _sections.focusActions.focusAndReveal(
                      _focus.playlistFocusNodes[0],
                    )
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
          child: IptvSettingsTvButton(
            focusNode: _focus.importFileButtonFocusNode,
            icon: Icons.file_open,
            label: 'Browse Files',
            onPressed: _sections.fileImport.importFromFile,
            onUpArrow: () =>
                _sections.focusActions.focusAndReveal(_focus.fileTabFocusNode),
            onDownArrow:
                !l.twoPaneActive &&
                    _sources.playlists.isNotEmpty &&
                    _focus.playlistFocusNodes.isNotEmpty
                ? () => _sections.focusActions.focusAndReveal(
                    _focus.playlistFocusNodes[0],
                  )
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
            controller: _input.xcNameController,
            focusNode: _focus.xcNameFocusNode,
            labelText: 'Playlist Name (optional)',
            hintText: 'e.g., My Provider',
            prefixIcon: const Icon(Icons.label_outline),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                _sections.focusActions.focusAndReveal(_focus.xcServerFocusNode),
            // UP targets the SELECTED tab (geometric search from a full-width
            // field center-lands on the middle tab).
            onUpArrow: () =>
                _sections.focusActions.focusAndReveal(_focus.xcTabFocusNode),
            onDownArrow: () =>
                _sections.focusActions.focusAndReveal(_focus.xcServerFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Server URL input
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: TvTextField(
            controller: _input.xcServerController,
            focusNode: _focus.xcServerFocusNode,
            labelText: 'Server URL',
            hintText: 'http://example.com:8080',
            prefixIcon: const Icon(Icons.dns),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _sections.focusActions.focusAndReveal(
              _focus.xcUsernameFocusNode,
            ),
            onUpArrow: () =>
                _sections.focusActions.focusAndReveal(_focus.xcNameFocusNode),
            onDownArrow: () => _sections.focusActions.focusAndReveal(
              _focus.xcUsernameFocusNode,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Username input
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: TvTextField(
            controller: _input.xcUsernameController,
            focusNode: _focus.xcUsernameFocusNode,
            labelText: 'Username',
            hintText: 'your username',
            prefixIcon: const Icon(Icons.person),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _sections.focusActions.focusAndReveal(
              _focus.xcPasswordFocusNode,
            ),
            onUpArrow: () =>
                _sections.focusActions.focusAndReveal(_focus.xcServerFocusNode),
            onDownArrow: () => _sections.focusActions.focusAndReveal(
              _focus.xcPasswordFocusNode,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Password input
        FocusTraversalOrder(
          order: const NumericFocusOrder(3.5),
          child: TvTextField(
            controller: _input.xcPasswordController,
            focusNode: _focus.xcPasswordFocusNode,
            labelText: 'Password',
            hintText: 'your password',
            prefixIcon: const Icon(Icons.lock),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              // IME "done" unfocuses the field — park DPAD on the button so
              // focus isn't stranded on the bare scope while the login runs.
              _focus.xcLoginButtonFocusNode.requestFocus();
              _sections.xtreamAdd.addXtreamCodes();
            },
            onUpArrow: () => _sections.focusActions.focusAndReveal(
              _focus.xcUsernameFocusNode,
            ),
            onDownArrow: () => _sections.focusActions.focusAndReveal(
              _focus.xcLoginButtonFocusNode,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Login button
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: Align(
            alignment: Alignment.centerRight,
            child: IptvSettingsTvButton(
              focusNode: _focus.xcLoginButtonFocusNode,
              icon: _input.isXcAdding ? Icons.hourglass_empty : Icons.login,
              label: _input.isXcAdding ? 'Logging in...' : 'Login & Add',
              onPressed: _input.isXcAdding
                  ? () {}
                  : _sections.xtreamAdd.addXtreamCodes,
              onUpArrow: () => _sections.focusActions.focusAndReveal(
                _focus.xcPasswordFocusNode,
              ),
              onDownArrow:
                  !l.twoPaneActive &&
                      _sources.playlists.isNotEmpty &&
                      _focus.playlistFocusNodes.isNotEmpty
                  ? () => _sections.focusActions.focusAndReveal(
                      _focus.playlistFocusNodes[0],
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sources.loading) {
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
      canPop: l.phoneSection == IptvSettingsPhoneSection.hub,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        _enterPhoneSection(IptvSettingsPhoneSection.hub);
      },
      child: SettingsPageScaffold(
        title: switch (l.phoneSection) {
          IptvSettingsPhoneSection.hub => 'IPTV Playlists',
          IptvSettingsPhoneSection.sources => 'Sources',
          IptvSettingsPhoneSection.lists => 'Channel Lists',
          IptvSettingsPhoneSection.categoryOrder => 'Category Order',
          IptvSettingsPhoneSection.hidden => 'Hidden Categories',
          IptvSettingsPhoneSection.startup => 'Startup',
          IptvSettingsPhoneSection.channelPreview => 'Channel Preview',
          IptvSettingsPhoneSection.continueWatching => 'Continue Watching',
          IptvSettingsPhoneSection.recording => 'Recording',
        },
        leading: IptvSettingsBackButton(
          focusNode: _focus.backButtonFocusNode,
          // Two-pane hands DOWN to the rail; the single column lands on the
          // currently-selected tab, not always the first one — but only the
          // Sources sub-view mounts the tabs at all; everywhere else default
          // traversal owns DOWN.
          onDownArrow: () {
            if (l.twoPaneActive) {
              _twoPaneKey.currentState?.focusRail();
              return;
            }
            if (l.phoneSection != IptvSettingsPhoneSection.sources) {
              // The back button swallows DOWN whenever a handler exists, so
              // hand focus somewhere real: whichever view is up, its first
              // focusable row (on the hub that's the Sources row).
              _focus.phoneViewMarker.traversalDescendants.firstOrNull
                  ?.requestFocus();
              return;
            }
            _sections.focusActions.focusAndReveal(
              switch (_input.tabController.index) {
                1 => _focus.fileTabFocusNode,
                2 => _focus.xcTabFocusNode,
                _ => _focus.urlTabFocusNode,
              },
            );
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
            l.twoPaneActive = twoPane;
            // The wide layout renders no sub-views, so a resize mid-sub-view
            // must land back on the hub. Unlike _twoPaneActive this one IS
            // read by widgets built before this LayoutBuilder runs (the
            // PopScope's canPop and the scaffold title), so a bare field
            // assignment would leave them stale indefinitely — schedule a
            // rebuild for them.
            if (twoPane && l.phoneSection != IptvSettingsPhoneSection.hub) {
              l.phoneSection = IptvSettingsPhoneSection.hub;
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
      playlists: _sources.playlists,
      defaultPlaylistId: _sources.defaultPlaylistId,
      refreshingIds: _sources.refreshingIds,
      autoRefreshHours: _preferences.autoRefreshHours,
      onPickAutoRefresh: _sections.preferencesActions.pickAutoRefresh,
      customLists: _sections.listsActions.customLists,
      startupEnabled: _preferences.startupEnabled,
      startupMode: _preferences.startupMode,
      startupChannelLabel: _sections.preferencesActions.startupChannelLabel,
      lastLiveChannelLabel: _sections.preferencesActions.lastLiveChannelLabel,
      hasStartupChannel: _preferences.startupChannel != null,
      hasLastLiveChannel: _preferences.lastLiveChannel != null,
      addMethod: _input.tabController.index,
      // Kept on the shared TabController so the two layouts agree about which
      // method is chosen across a resize.
      onAddMethodChanged: (i) {
        if (_input.tabController.index == i) return;
        setState(() => _input.tabController.index = i);
      },
      urlFormBuilder: (_) => _buildUrlTabContent(),
      fileFormBuilder: (_) => _buildFileTabContent(),
      xtreamFormBuilder: (_) => _buildXcTabContent(),
      // The forms' own up-arrow targets are these nodes, so reusing them for
      // the method chooser keeps every hand-off inside them valid here.
      urlMethodFocusNode: _focus.urlTabFocusNode,
      fileMethodFocusNode: _focus.fileTabFocusNode,
      xtreamMethodFocusNode: _focus.xcTabFocusNode,
      onSetDefault: (p) => _sections.sourceRefresh.setDefaultPlaylist(
        _sources.defaultPlaylistId == p.id ? null : p,
      ),
      onRefresh: _sections.sourceRefresh.refreshPlaylist,
      onEdit: _sections.sourceEdit.editPlaylist,
      onDelete: _sections.sourceRemoval.removePlaylist,
      onCreateList: _sections.listsActions.createList,
      onManageChannelOrder: () =>
          unawaited(_sections.catalogActions.openChannelOrder()),
      onManageCategoryOrder: (playlist) =>
          unawaited(_sections.catalogActions.openCategoryOrder(playlist)),
      onManageHidden: (playlist) =>
          unawaited(_sections.catalogActions.openHiddenCategories(playlist)),
      hiddenCounts: _sources.hiddenCounts,
      onFocusFirstFormField: () => _sections.focusActions.focusAndReveal(
        switch (_input.tabController.index) {
          1 => _focus.importFileButtonFocusNode,
          2 => _focus.xcNameFocusNode,
          _ => _focus.nameInputFocusNode,
        },
      ),
      onListActions: _sections.listsActions.showListActions,
      onToggleStartup: _sections.preferencesActions.setStartupEnabled,
      onStartupModeChanged: _sections.preferencesActions.setStartupMode,
      onPickStartupChannel: _sections.preferencesActions.pickStartupChannel,
      channelPreviewEnabled: _preferences.channelPreviewEnabled,
      onToggleChannelPreview:
          _sections.preferencesActions.setChannelPreviewEnabled,
      trackContinueWatching: _preferences.trackContinueWatching,
      onToggleTrackContinueWatching:
          _sections.preferencesActions.setTrackContinueWatching,
      showAppearanceSection: _appearanceVisible,
      iptvStyle: _preferences.iptvStyle,
      onIptvStyleChanged: (v) =>
          unawaited(_sections.preferencesActions.setIptvStyle(v)),
      playerGuideStyle: _preferences.playerGuideStyle,
      onPlayerGuideStyleChanged: (v) =>
          unawaited(_sections.preferencesActions.setPlayerGuideStyle(v)),
      showRecordingSection: r.recordingSectionVisible,
      showEngineToggle: r.engineToggleVisible,
      recordingEngineEnabled: r.recordingEngineOn,
      scheduledCount: r.scheduledCount,
      onToggleRecordingEngine: (enabled) async {
        await LiveRecordingService.setEngineEnabled(enabled);
        if (mounted) setState(() => r.recordingEngineOn = enabled);
      },
      onOpenScheduledRecordings: () =>
          unawaited(_sections.recordingActions.openScheduledRecordings()),
      maxConcurrentRecordings: r.maxConcurrent,
      onPickMaxConcurrent: () =>
          unawaited(_sections.recordingActions.pickMaxConcurrent()),
      batteryExempt: r.batteryExempt,
      onRequestBatteryExemption: () =>
          unawaited(_sections.recordingActions.requestBatteryExemption()),
    );
  }

  Widget _buildSingleColumn() {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Focus(
        focusNode: _focus.phoneViewMarker,
        canRequestFocus: false,
        skipTraversal: true,
        child: switch (l.phoneSection) {
          IptvSettingsPhoneSection.hub => _buildPhoneHub(),
          IptvSettingsPhoneSection.sources => _buildSourcesView(),
          IptvSettingsPhoneSection.lists => _buildListsView(),
          IptvSettingsPhoneSection.categoryOrder => _buildCategoryOrderView(),
          IptvSettingsPhoneSection.hidden => _buildHiddenView(),
          IptvSettingsPhoneSection.startup => _buildStartupView(),
          IptvSettingsPhoneSection.channelPreview => _buildChannelPreviewView(),
          IptvSettingsPhoneSection.continueWatching =>
            _buildContinueWatchingView(),
          IptvSettingsPhoneSection.recording => _buildRecordingView(),
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
    final hideableIds = {
      for (final p in _sections.catalogActions.hideableSources) p.id,
    };
    final hiddenTotal = _sources.hiddenCounts.entries
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
              focusNode: _focus.hubSourcesFocusNode,
              icon: Icons.playlist_play_rounded,
              title: 'Sources',
              subtitle: _sources.playlists.isEmpty
                  ? 'None yet — add your first playlist'
                  : '${_sources.playlists.length} '
                        '${_sources.playlists.length == 1 ? 'source' : 'sources'}',
              onTap: () async =>
                  _enterPhoneSection(IptvSettingsPhoneSection.sources),
            ),
            SettingsTile(
              icon: Icons.update_rounded,
              title: 'Auto-refresh',
              subtitle:
                  '${iptvAutoRefreshLabel(_preferences.autoRefreshHours)} · All sources in this profile',
              onTap: _sections.preferencesActions.pickAutoRefresh,
            ),
            SettingsTile(
              icon: Icons.video_library_rounded,
              title: 'Channel lists',
              subtitle: _sections.listsActions.customLists.isEmpty
                  ? 'Favorites only'
                  : 'Favorites + ${_sections.listsActions.customLists.length} '
                        '${_sections.listsActions.customLists.length == 1 ? 'list' : 'lists'}',
              onTap: () async =>
                  _enterPhoneSection(IptvSettingsPhoneSection.lists),
            ),
            SettingsTile(
              icon: Icons.reorder_rounded,
              title: 'Channel order',
              subtitle: 'Arrange Favorites and saved lists',
              onTap: _sections.catalogActions.openChannelOrder,
            ),
            if (_sections.catalogActions.categoryOrderSources.isNotEmpty)
              SettingsTile(
                icon: Icons.swap_vert_rounded,
                title: 'Category order',
                subtitle: 'Arrange categories by source',
                onTap: () async =>
                    _enterPhoneSection(IptvSettingsPhoneSection.categoryOrder),
              ),
            if (_sections.catalogActions.hideableSources.isNotEmpty)
              SettingsTile(
                icon: Icons.visibility_off_rounded,
                title: 'Hidden categories',
                subtitle: hiddenTotal == 0
                    ? 'Nothing hidden'
                    : '$hiddenTotal '
                          '${hiddenTotal == 1 ? 'category' : 'categories'} '
                          'hidden',
                onTap: () async =>
                    _enterPhoneSection(IptvSettingsPhoneSection.hidden),
              ),
            SettingsTile(
              icon: Icons.rocket_launch_rounded,
              title: 'Startup',
              subtitle: !_preferences.startupEnabled
                  ? 'Off'
                  : _preferences.startupMode ==
                        StartupIptvStorage.startupIptvModeLast
                  ? 'Last watched channel'
                  : _sections.preferencesActions.startupChannelLabel,
              onTap: () async =>
                  _enterPhoneSection(IptvSettingsPhoneSection.startup),
            ),
            SettingsTile(
              icon: Icons.ondemand_video_rounded,
              title: 'Channel preview',
              subtitle: _preferences.channelPreviewEnabled
                  ? 'On · uses a provider stream while browsing'
                  : 'Off · no stream until you press Watch',
              onTap: () async =>
                  _enterPhoneSection(IptvSettingsPhoneSection.channelPreview),
            ),
            SettingsTile(
              icon: Icons.history_toggle_off_rounded,
              title: 'Continue watching',
              subtitle: _preferences.trackContinueWatching
                  ? 'Tracking movies and series'
                  : 'Off',
              onTap: () async =>
                  _enterPhoneSection(IptvSettingsPhoneSection.continueWatching),
            ),
            // The looks land on the same standalone pickers the Appearance
            // settings section uses — one implementation per pref.
            if (_appearanceVisible)
              SettingsTile(
                icon: Icons.style_rounded,
                title: 'Appearance',
                subtitle: iptvStyleLabel(_preferences.iptvStyle),
                onTap: () async => unawaited(
                  _sections.preferencesActions.openIptvStylePicker(),
                ),
              ),
            SettingsTile(
              icon: Icons.smart_display_rounded,
              title: 'Player guide',
              subtitle: playerGuideStyleLabel(_preferences.playerGuideStyle),
              onTap: () async => unawaited(
                _sections.preferencesActions.openPlayerGuidePicker(),
              ),
            ),
            if (r.recordingSectionVisible)
              SettingsTile(
                icon: Icons.fiber_manual_record_rounded,
                title: 'Recording',
                subtitle: !r.engineToggleVisible
                    ? (r.scheduledCount == 0
                          ? 'Recordings'
                          : '${r.scheduledCount} scheduled')
                    : r.recordingEngineOn
                    ? (r.scheduledCount == 0
                          ? 'Engine on'
                          : 'Engine on · ${r.scheduledCount} scheduled')
                    : 'Player-tied',
                onTap: () async =>
                    _enterPhoneSection(IptvSettingsPhoneSection.recording),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (_sources.defaultPlaylistId != null)
          const SettingsInfoBanner(
            text:
                'Your default playlist will load automatically when you select IPTV.',
          ),
      ],
    );
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
        IptvSettingsTvTabBar(
          tabController: _input.tabController,
          urlTabFocusNode: _focus.urlTabFocusNode,
          fileTabFocusNode: _focus.fileTabFocusNode,
          xcTabFocusNode: _focus.xcTabFocusNode,
          onUpArrow: () => _focus.backButtonFocusNode.requestFocus(),
          onDownArrowFromUrlTab: () => _sections.focusActions
              .focusContentAfterTabSwitch(_focus.nameInputFocusNode),
          onDownArrowFromFileTab: () => _sections.focusActions
              .focusContentAfterTabSwitch(_focus.importFileButtonFocusNode),
          onDownArrowFromXcTab: () => _sections.focusActions
              .focusContentAfterTabSwitch(_focus.xcNameFocusNode),
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
            controller: _input.tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // Off-screen tab pages stay built by TabBarView, so exclude
              // them from focus or DPAD traversal can land on invisible
              // fields/buttons (a dead zone on TV).
              ExcludeFocus(
                excluding: _input.tabController.index != 0,
                child: _buildUrlTabContent(),
              ),
              ExcludeFocus(
                excluding: _input.tabController.index != 1,
                child: _buildFileTabContent(),
              ),
              ExcludeFocus(
                excluding: _input.tabController.index != 2,
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

        if (_sources.playlists.isEmpty)
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
        if (_sources.defaultPlaylistId != null)
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
              IptvSettingsFocusableTile(
                focusNode: _focus.createListFocusNode,
                icon: Icons.add_rounded,
                label: 'Create list',
                onTap: _sections.listsActions.createList,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryOrderView() {
    final t = AppThemeScope.of(context).settings;
    final sources = _sections.catalogActions.categoryOrderSources;
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
                  onTap: () => unawaited(
                    _sections.catalogActions.openCategoryOrder(source),
                  ),
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
                value: _preferences.startupEnabled,
                onChanged: _sections.preferencesActions.setStartupEnabled,
              ),
              if (_preferences.startupEnabled) ...[
                const Divider(height: 1),
                RadioListTile<String>(
                  title: const Text('Last watched channel'),
                  subtitle: Text(
                    _preferences.lastLiveChannel == null
                        // Honest about the bootstrap: the first boot after
                        // enabling this has nothing to resume, and silently
                        // doing nothing reads as broken.
                        ? 'Nothing watched yet — starts on the first '
                              'channel, then remembers what you watch.'
                        : 'Currently: ${_sections.preferencesActions.lastLiveChannelLabel}',
                  ),
                  value: StartupIptvStorage.startupIptvModeLast,
                  groupValue: _preferences.startupMode,
                  onChanged: _sections.preferencesActions.setStartupMode,
                ),
                RadioListTile<String>(
                  title: const Text('A specific channel'),
                  subtitle: Text(
                    _sections.preferencesActions.startupChannelLabel,
                  ),
                  value: StartupIptvStorage.startupIptvModePinned,
                  groupValue: _preferences.startupMode,
                  onChanged: _sections.preferencesActions.setStartupMode,
                ),
                if (_preferences.startupMode ==
                    StartupIptvStorage.startupIptvModePinned)
                  IptvSettingsFocusableTile(
                    focusNode: _focus.startupChannelFocusNode,
                    icon: Icons.live_tv_rounded,
                    label: _preferences.startupChannel == null
                        ? 'Choose channel'
                        : 'Change channel',
                    onTap: _sections.preferencesActions.pickStartupChannel,
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
            value: _preferences.trackContinueWatching,
            onChanged: _sections.preferencesActions.setTrackContinueWatching,
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
            value: _preferences.channelPreviewEnabled,
            onChanged: _sections.preferencesActions.setChannelPreviewEnabled,
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
              if (r.engineToggleVisible)
                SwitchListTile(
                  title: const Text('Background recording engine'),
                  subtitle: const Text(
                    'Recordings keep running when you zap or leave the '
                    'app, and programmes can be scheduled from the TV '
                    'guide. Off returns to player-tied recording. Uses an '
                    'extra connection to your provider.',
                  ),
                  value: r.recordingEngineOn,
                  onChanged: (enabled) async {
                    await LiveRecordingService.setEngineEnabled(enabled);
                    if (mounted) {
                      setState(() => r.recordingEngineOn = enabled);
                    }
                  },
                ),
              if (!r.engineToggleVisible || r.recordingEngineOn) ...[
                if (r.engineToggleVisible) const Divider(height: 1),
                IptvSettingsFocusableTile(
                  focusNode: _focus.maxConcurrentFocusNode,
                  icon: Icons.filter_none_rounded,
                  label: 'Simultaneous recordings (${r.maxConcurrent})',
                  onTap: _sections.recordingActions.pickMaxConcurrent,
                ),
                if (r.batteryExempt != null) ...[
                  const Divider(height: 1),
                  IptvSettingsFocusableTile(
                    focusNode: _focus.batteryFocusNode,
                    icon: Icons.battery_alert_rounded,
                    label: r.batteryExempt == true
                        ? 'Battery optimization — excluded ✓'
                        : 'Battery optimization — tap to exclude',
                    onTap: _sections.recordingActions.requestBatteryExemption,
                  ),
                ],
                const Divider(height: 1),
                IptvSettingsFocusableTile(
                  focusNode: _focus.scheduledRecordingsFocusNode,
                  icon: Icons.fiber_manual_record_rounded,
                  label: r.scheduledCount == 0
                      ? 'Recordings'
                      : 'Recordings (${r.scheduledCount} scheduled)',
                  onTap: _sections.recordingActions.openScheduledRecordings,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !r.recheckBatteryOnResume) return;
    r.recheckBatteryOnResume = false;
    unawaited(
      LiveRecordingService.isIgnoringBatteryOptimizations().then((exempt) {
        if (mounted) setState(() => r.batteryExempt = exempt);
      }),
    );
  }
}

/// Frozen original-code characterization seam. Each invocation reads the actual
/// owner and action tear-offs; no service, clock or constructor seam is added.
@visibleForTesting
Map<String, dynamic> iptvSettingsTestAccess(State state) {
  final s = state as _IptvSettingsPageState;
  return {
    'twoPaneKey': s._twoPaneKey,
    'tabController': s._input.tabController,
    'nameController': s._input.nameController,
    'urlController': s._input.urlController,
    'epgUrlController': s._input.epgUrlController,
    'xcNameController': s._input.xcNameController,
    'xcServerController': s._input.xcServerController,
    'xcUsernameController': s._input.xcUsernameController,
    'xcPasswordController': s._input.xcPasswordController,
    'playlists': s._sources.playlists,
    'lists': s._sources.lists,
    'hiddenCounts': s._sources.hiddenCounts,
    'defaultPlaylistId': s._sources.defaultPlaylistId,
    'loading': s._sources.loading,
    'twoPaneActive': s.l.twoPaneActive,
    'refreshingIds': s._sources.refreshingIds,
    'isAdding': s._input.isAdding,
    'isXcAdding': s._input.isXcAdding,
    'playlistFocusNodes': s._focus.playlistFocusNodes,
    'listFocusNodes': s._focus.listFocusNodes,
    'hiddenFocusNodes': s._focus.hiddenFocusNodes,
    'startupEnabled': s._preferences.startupEnabled,
    'startupMode': s._preferences.startupMode,
    'startupChannel': s._preferences.startupChannel,
    'lastLiveChannel': s._preferences.lastLiveChannel,
    'channelPreviewEnabled': s._preferences.channelPreviewEnabled,
    'trackContinueWatching': s._preferences.trackContinueWatching,
    'iptvStyle': s._preferences.iptvStyle,
    'playerGuideStyle': s._preferences.playerGuideStyle,
    'autoRefreshHours': s._preferences.autoRefreshHours,
    'recordingSectionVisible': s.r.recordingSectionVisible,
    'engineToggleVisible': s.r.engineToggleVisible,
    'recordingEngineOn': s.r.recordingEngineOn,
    'scheduledCount': s.r.scheduledCount,
    'maxConcurrent': s.r.maxConcurrent,
    'batteryExempt': s.r.batteryExempt,
    'recheckBatteryOnResume': s.r.recheckBatteryOnResume,
    'hubSourcesFocusNode': s._focus.hubSourcesFocusNode,
    'phoneViewMarker': s._focus.phoneViewMarker,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'urlTabFocusNode': s._focus.urlTabFocusNode,
    'fileTabFocusNode': s._focus.fileTabFocusNode,
    'xcTabFocusNode': s._focus.xcTabFocusNode,
    'nameInputFocusNode': s._focus.nameInputFocusNode,
    'urlInputFocusNode': s._focus.urlInputFocusNode,
    'epgUrlInputFocusNode': s._focus.epgUrlInputFocusNode,
    'addButtonFocusNode': s._focus.addButtonFocusNode,
    'importFileButtonFocusNode': s._focus.importFileButtonFocusNode,
    'xcNameFocusNode': s._focus.xcNameFocusNode,
    'xcServerFocusNode': s._focus.xcServerFocusNode,
    'xcUsernameFocusNode': s._focus.xcUsernameFocusNode,
    'xcPasswordFocusNode': s._focus.xcPasswordFocusNode,
    'xcLoginButtonFocusNode': s._focus.xcLoginButtonFocusNode,
    'createListFocusNode': s._focus.createListFocusNode,
    'addPlaylist': s._sections.urlAdd.addPlaylist,
    'importFromFile': s._sections.fileImport.importFromFile,
    'addXtreamCodes': s._sections.xtreamAdd.addXtreamCodes,
    'removePlaylist': s._sections.sourceRemoval.removePlaylist,
    'setDefaultPlaylist': s._sections.sourceRefresh.setDefaultPlaylist,
    'refreshPlaylist': s._sections.sourceRefresh.refreshPlaylist,
    'editPlaylist': s._sections.sourceEdit.editPlaylist,
    'createList': s._sections.listsActions.createList,
    'renameList': s._sections.listsActions.renameList,
    'deleteList': s._sections.listsActions.deleteList,
    'moveList': s._sections.listsActions.moveList,
    'showListActions': s._sections.listsActions.showListActions,
    'setStartupEnabled': s._sections.preferencesActions.setStartupEnabled,
    'setStartupMode': s._sections.preferencesActions.setStartupMode,
    'setChannelPreviewEnabled':
        s._sections.preferencesActions.setChannelPreviewEnabled,
    'setTrackContinueWatching':
        s._sections.preferencesActions.setTrackContinueWatching,
    'setIptvStyle': s._sections.preferencesActions.setIptvStyle,
    'setPlayerGuideStyle': s._sections.preferencesActions.setPlayerGuideStyle,
    'pickAutoRefresh': s._sections.preferencesActions.pickAutoRefresh,
    'pickStartupChannel': s._sections.preferencesActions.pickStartupChannel,
    'pickMaxConcurrent': s._sections.recordingActions.pickMaxConcurrent,
    'openScheduledRecordings':
        s._sections.recordingActions.openScheduledRecordings,
    'requestBatteryExemption':
        s._sections.recordingActions.requestBatteryExemption,
    'runProfileAction': s._sections.profileActions.runProfileAction,
    'normalizeXtreamServerUrl': normalizeXtreamServerUrl,
    'loadSettings': s._sections.loadSettings.loadSettings,
    'catalogKeysFor': s._sections.catalogActions.catalogKeysFor,
    'catalogOwnerReferencesFor':
        s._sections.catalogActions.catalogOwnerReferencesFor,
    'reloadHiddenCounts': s._sections.catalogActions.reloadHiddenCounts,
    'ensureFocusNodes': s._sections.focusActions.ensureFocusNodes,
    'focusContentAfterTabSwitch':
        s._sections.focusActions.focusContentAfterTabSwitch,
    'focusAndReveal': s._sections.focusActions.focusAndReveal,
    'phoneSection': s.l.phoneSection.name,
    'customLists': s._sections.listsActions.customLists,
    'hideableSources': s._sections.catalogActions.hideableSources,
    'categoryOrderSources': s._sections.catalogActions.categoryOrderSources,
    'appearanceVisible': s._appearanceVisible,
    'startupChannelLabel': s._sections.preferencesActions.startupChannelLabel,
    'lastLiveChannelLabel': s._sections.preferencesActions.lastLiveChannelLabel,
    'lifecycle': s.didChangeAppLifecycleState,
    'enterPhoneSection': (String name) =>
        s._enterPhoneSection(IptvSettingsPhoneSection.values.byName(name)),
  };
}
