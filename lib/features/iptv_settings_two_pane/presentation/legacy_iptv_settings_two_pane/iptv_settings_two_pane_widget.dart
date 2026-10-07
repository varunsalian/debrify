import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_destination.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_dependencies.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/storage/iptv_appearance_storage.dart'
    show IptvAppearanceStorage;
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Two-pane IPTV settings for TV and desktop ("Concept A"): a rail of the
/// user's actual sources on the left, the selected source's detail on the
/// right, with Add / Lists / Startup / Channel preview as rail destinations
/// below them.
///
/// Why this shape — the single-column page it replaces put the *rarest*
/// action (adding a playlist) at the top in a fixed 410px block, buried
/// Startup at the bottom of a long scroll, and gave every playlist row FOUR
/// DPAD stops (star, refresh, edit, delete) in a horizontal strip. Three
/// playlists cost twelve stops to walk past. Here a source is one stop and
/// its actions live in the pane.
///
/// DPAD model, hand-wired to match [SettingsTvLayout] so the two pages feel
/// like one app:
///   • Rail: Up/Down move between entries AND update the pane live, so
///     focusing a source previews it. Right / OK enter the pane.
///   • Pane: Up/Down move between rows. Left returns to the *selected* rail
///     entry, never a different one.
///
/// Presentation and focus only — every action still lives in the parent
/// State, handed in as callbacks.
class IptvSettingsTwoPane extends StatefulWidget {
  const IptvSettingsTwoPane({
    super.key,
    required this.playlists,
    required this.defaultPlaylistId,
    required this.refreshingIds,
    this.autoRefreshHours = 24,
    this.onPickAutoRefresh,
    required this.customLists,
    required this.startupEnabled,
    required this.startupMode,
    required this.startupChannelLabel,
    required this.lastLiveChannelLabel,
    required this.hasStartupChannel,
    required this.hasLastLiveChannel,
    required this.addMethod,
    required this.onAddMethodChanged,
    required this.urlFormBuilder,
    required this.fileFormBuilder,
    required this.xtreamFormBuilder,
    required this.urlMethodFocusNode,
    required this.fileMethodFocusNode,
    required this.xtreamMethodFocusNode,
    required this.onSetDefault,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
    required this.onCreateList,
    required this.onManageChannelOrder,
    this.onManageCategoryOrder,
    this.onManageHidden,
    this.hiddenCounts = const {},
    required this.onFocusFirstFormField,
    required this.onListActions,
    required this.onToggleStartup,
    required this.onStartupModeChanged,
    required this.onPickStartupChannel,
    required this.channelPreviewEnabled,
    required this.onToggleChannelPreview,
    required this.trackContinueWatching,
    required this.onToggleTrackContinueWatching,
    this.showAppearanceSection = false,
    this.iptvStyle = IptvAppearanceStorage.kIptvStyleDefault,
    this.onIptvStyleChanged,
    this.playerGuideStyle = 'classic',
    this.onPlayerGuideStyleChanged,
    this.showRecordingSection = false,
    this.showEngineToggle = true,
    this.recordingEngineEnabled = true,
    this.scheduledCount = 0,
    this.onToggleRecordingEngine,
    this.onOpenScheduledRecordings,
    this.maxConcurrentRecordings = 2,
    this.onPickMaxConcurrent,
    this.batteryExempt,
    this.onRequestBatteryExemption,
    this.openAddSource = false,
  });

  /// The page was opened by an "Add playlist" affordance (the IPTV page's
  /// source dropdown, its empty state), not by a plain visit to settings — so
  /// open ON the Add pane instead of the source the page normally lands on.
  final bool openAddSource;

  final List<IptvPlaylist> playlists;
  final String? defaultPlaylistId;
  final Set<String> refreshingIds;
  final int autoRefreshHours;
  final VoidCallback? onPickAutoRefresh;
  final List<IptvListMeta> customLists;

  final bool startupEnabled;
  final String startupMode;
  final String startupChannelLabel;
  final String lastLiveChannelLabel;
  final bool hasStartupChannel;
  final bool hasLastLiveChannel;

  /// The Recording rail entry + pane exist where SOME recorder can run:
  /// Android 10+ (engine + toggle) or desktop (in-app scheduler only). On
  /// iOS/pre-Q the rail ends at Continue watching and nothing promises
  /// recording that cannot run.
  final bool showRecordingSection;

  /// Android only — the engine-vs-tee choice is meaningless on desktop, whose
  /// single recorder has no alternative to toggle to.
  final bool showEngineToggle;
  final bool recordingEngineEnabled;
  final int scheduledCount;
  final ValueChanged<bool>? onToggleRecordingEngine;
  final VoidCallback? onOpenScheduledRecordings;

  /// Simultaneous-recordings limit shown on (and picked from) the Recording
  /// pane; the host page owns persistence.
  final int maxConcurrentRecordings;
  final VoidCallback? onPickMaxConcurrent;

  /// Null hides the row (non-Android / TV); otherwise current exemption
  /// state, label-driving.
  final bool? batteryExempt;
  final VoidCallback? onRequestBatteryExemption;

  /// 0 = from URL, 1 = from file, 2 = Xtream login. Owned by the parent so the
  /// existing TabController (and the phone layout) stay in sync with it.
  final int addMethod;
  final ValueChanged<int> onAddMethodChanged;

  /// The three existing add forms, reused verbatim. They are already
  /// focus-wired against the method nodes below, so handing those in keeps
  /// every onUpArrow/onDownArrow target valid in this layout too.
  final WidgetBuilder urlFormBuilder;
  final WidgetBuilder fileFormBuilder;
  final WidgetBuilder xtreamFormBuilder;
  final FocusNode urlMethodFocusNode;
  final FocusNode fileMethodFocusNode;
  final FocusNode xtreamMethodFocusNode;

  final ValueChanged<IptvPlaylist> onSetDefault;
  final ValueChanged<IptvPlaylist> onRefresh;
  final ValueChanged<IptvPlaylist> onEdit;
  final ValueChanged<IptvPlaylist> onDelete;
  final VoidCallback onCreateList;
  final VoidCallback onManageChannelOrder;

  /// Opens a source's category-list reorder screen. Imported files use their
  /// stable saved-playlist id while remote sources use catalog identity.
  final ValueChanged<IptvPlaylist>? onManageCategoryOrder;

  /// Opens a source's hidden-categories manager. Null on sources that store
  /// no catalog (imported files), which is also what keeps the row off them.
  final ValueChanged<IptvPlaylist>? onManageHidden;

  /// Hidden-category count per playlist id — the row's subtitle. Owned by the
  /// host page, which re-reads it when the manager closes.
  final Map<String, int> hiddenCounts;

  /// DOWN off the method chooser lands on the current form's first field.
  /// Hand-wired rather than left to geometric traversal, which is exactly
  /// the kind of thing that misbehaves on real TV hardware.
  final VoidCallback onFocusFirstFormField;

  /// OK on a list opens rename/move/delete as a sheet — one stop per list
  /// instead of the four-icon strip.
  final ValueChanged<IptvListMeta> onListActions;

  final ValueChanged<bool> onToggleStartup;
  final ValueChanged<String> onStartupModeChanged;
  final VoidCallback onPickStartupChannel;

  final bool channelPreviewEnabled;
  final ValueChanged<bool> onToggleChannelPreview;

  final bool trackContinueWatching;
  final ValueChanged<bool> onToggleTrackContinueWatching;

  /// The Appearance rail entry + pane exist only where the IPTV cockpit does
  /// (television and desktop) — a phone or touch tablet would be picking a look
  /// it can never see.
  final bool showAppearanceSection;

  /// In-player guide look (`iptv_player_guide_style`). ALWAYS present in the
  /// rail — every platform has a player, unlike the cockpit Appearance.
  final String playerGuideStyle;
  final ValueChanged<String>? onPlayerGuideStyleChanged;

  /// Current `iptv_style` value ('command' / 'edition' / 'console' /
  /// 'spotlight'). Owned by the host page, which persists BEFORE reflecting the
  /// change back here.
  final String iptvStyle;
  final ValueChanged<String>? onIptvStyleChanged;

  @override
  State<IptvSettingsTwoPane> createState() => IptvSettingsTwoPaneState();
}

class IptvSettingsTwoPaneState extends State<IptvSettingsTwoPane> {
  final _owners = IptvSettingsTwoPaneOwners();
  IptvSettingsTwoPaneSections? _sectionsCache;
  IptvSettingsTwoPaneSections get _sections =>
      _sectionsCache ??= IptvSettingsTwoPaneSections(
        IptvSettingsTwoPaneDependencies(
          widget: () => widget,
          context: () => context,
          owners: _owners,
          sections: () => _sections,
        ),
      );

  @override
  void initState() {
    super.initState();
    _sections.navigation.syncRailNodes();
    _sections.navigation.syncStats();
    // Land on the default source (or the first one) rather than on "Add" —
    // the common visit is to manage what you already have. Unless the caller
    // came here to add: then "Add" is the whole point of the trip. Deliberately
    // only the OPENING landing — the later re-homing below (a deleted source
    // leaving the pane pointing at a ghost) still goes through _initialDest.
    _owners.dest.value = widget.openAddSource
        ? const IptvTwoPaneAddDest()
        : _sections.navigation.initialDest();
  }

  @override
  void didUpdateWidget(covariant IptvSettingsTwoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sections.navigation.syncRailNodes();
    _sections.navigation.syncStats();
    // A deleted source must not leave the pane pointing at a ghost.
    final dest = _owners.dest.value;
    if (dest is IptvTwoPaneSourceDest &&
        !widget.playlists.any((p) => p.id == dest.playlistId)) {
      _owners.dest.value = _sections.navigation.initialDest();
    }
  }

  @override
  void dispose() {
    for (final node in _owners.railNodes) {
      node.dispose();
    }
    for (final node in _owners.paneNodes) {
      node.dispose();
    }
    _owners.railScroll.dispose();
    _owners.dest.dispose();
    super.dispose();
  }

  /// Entry point for the page's back button: hand DPAD to the rail entry the
  /// pane currently belongs to, never blindly to the first one.
  void focusRail() =>
      _sections.navigation.focusRailAt(_sections.navigation.selectedRailIndex);

  /// TV entry point for an "Add playlist" deep-link: skip the rail entirely and
  /// put DPAD straight on the add method chooser, the way OK on the rail's
  /// "Add a source" entry would. LEFT out of the pane still returns to that
  /// entry, so the rail is one keypress away.
  void focusAddPane() {
    final alreadyThere = _owners.dest.value is IptvTwoPaneAddDest;
    _owners.dest.value = const IptvTwoPaneAddDest();
    if (alreadyThere) {
      _sections.navigation.enterPane();
      return;
    }
    // The pane is still showing something else this frame, so the method
    // chooser's node is attached to nothing — and requesting focus on an
    // unattached node silently strands DPAD. Wait for the switch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sections.navigation.enterPane();
    });
  }

  @override
  Widget build(BuildContext context) {
    // ONE lookup per build, cached for every _buildX helper below: the pane is
    // rebuilt from a ValueListenableBuilder on each rail focus move, so a
    // per-helper lookup would walk the inherited tree on every DPAD step.
    _owners.app = AppThemeScope.of(context);
    final t = _owners.app.settings;
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sections.rail.buildRail(),
          Container(width: 1, color: t.line),
          Expanded(
            child: ValueListenableBuilder<IptvTwoPaneDest>(
              valueListenable: _owners.dest,
              builder: (context, dest, _) => _sections.panes.buildPane(dest),
            ),
          ),
        ],
      ),
    );
  }
}
