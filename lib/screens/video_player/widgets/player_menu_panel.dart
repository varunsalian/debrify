import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/stremio_subtitle.dart';
import '../../../services/stremio_subtitle_service.dart';
import '../../../services/subtitle_font_service.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';
import '../models/gesture_state.dart';
import '../services/subtitle_settings_service.dart';
import 'sleep_timer_sheet.dart';
import 'tracks_sheet.dart' show TracksSheetSubtitleSearchResult;

/// The unified player menu (Spotlight grammar) replaces the tracks sheet,
/// sleep sheet, shuffle dialog and the blind speed/aspect cycles with one
/// right-side glass panel. Flip this off to fall back to all of them.
const bool kUnifiedPlayerMenuEnabled = true;

/// Rail sections, in display order.
enum PlayerMenuSection {
  audio,
  subtitles,
  style,
  sync,
  speed,
  aspect,
  sleep,
  shuffle,
}

/// A selectable track, pre-labelled by the host (LanguageMapper lives there).
class PlayerMenuTrackOption {
  final String id;
  final String label;
  const PlayerMenuTrackOption(this.id, this.label);
}

/// In-player unified menu — one right-sliding glass panel, two panes:
/// a section rail (each row captioned with its current value) and a value
/// column for the focused section.
///
/// The panel is pure UI + subtitle-slot orchestration. Everything that
/// mutates the player goes through host-supplied appliers, so the host owns
/// exactly the same logic it owned for the old sheets.
///
/// DPAD model (virtual focus, house pattern from SourceSheet):
///  - rail: UP/DOWN move, RIGHT/OK enter the value pane, BACK closes
///  - values: UP/DOWN move, OK activates, LEFT or BACK returns to the rail
///  - stepper rows (Style pane): LEFT/RIGHT adjust, BACK returns to the rail
/// tvOS Menu never arrives as a key — the host routes it here via
/// [PlayerMenuPanelState.handleHostBack].
class PlayerMenuPanel extends StatefulWidget {
  final PlayerMenuSection initialSection;
  final VoidCallback onClose;

  // ── Audio ──
  final List<PlayerMenuTrackOption> audioTracks;
  final String selectedAudioId;
  final Future<void> Function(String audioId, String currentSubId)
  onAudioSelected;

  /// Android bitstream passthrough — null hides the row (other platforms).
  final bool? audioPassthrough;
  final Future<void> Function(bool enabled)? onAudioPassthroughChanged;

  // ── Subtitles ──
  final List<PlayerMenuTrackOption> embeddedSubtitles;

  /// 'no' | embedded track id | 'stremio:<id>' | 'auto'.
  final String selectedSubtitleId;
  final Future<void> Function(String currentAudioId) onSubtitlesOff;
  final Future<void> Function(String subId, String currentAudioId)
  onEmbeddedSubtitleSelected;

  /// Returns false when the download/apply failed (selection is kept).
  final Future<bool> Function(StremioSubtitle sub, String currentAudioId)
  onAddonSubtitleSelected;

  /// Fired only on a genuine subtitle switch (sync offset reset).
  final VoidCallback? onSubtitleTrackChanged;
  final String? contentImdbId;
  final String? contentType;
  final int? contentSeason;
  final int? contentEpisode;
  final List<AddonSubtitleSlot>? cachedAddonSlots;
  final void Function(List<AddonSubtitleSlot> slots)? onAddonSlotsFetched;
  final Future<TracksSheetSubtitleSearchResult?> Function()? onIdentifyTitle;
  final String? subtitleIdentityLabel;

  // ── Style ──
  final void Function(SubtitleSettingsData settings)? onSubtitleStyleChanged;

  // ── Sync (action row: closes the panel into the sync overlay) ──
  final VoidCallback? onSyncRequested;

  // ── Speed ──
  final bool showSpeed;
  final double speed;
  final ValueChanged<double> onSpeedSelected;

  // ── Aspect ──
  final AspectMode aspectMode;
  final ValueChanged<AspectMode> onAspectSelected;

  // ── Sleep ──
  final SleepTimerMode sleepMode;
  final int sleepArmedMinutes;
  final int sleepMinutesLeft;
  final bool allowEndOfItem;
  final ValueChanged<SleepTimerSelection> onSleepSelected;

  // ── Shuffle ──
  final bool hasPlaylist;
  final bool continuousShuffle;
  final VoidCallback onShuffleOnce;
  final VoidCallback onShuffleContinuousToggle;

  const PlayerMenuPanel({
    super.key,
    required this.initialSection,
    required this.onClose,
    required this.audioTracks,
    required this.selectedAudioId,
    required this.onAudioSelected,
    this.audioPassthrough,
    this.onAudioPassthroughChanged,
    required this.embeddedSubtitles,
    required this.selectedSubtitleId,
    required this.onSubtitlesOff,
    required this.onEmbeddedSubtitleSelected,
    required this.onAddonSubtitleSelected,
    this.onSubtitleTrackChanged,
    this.contentImdbId,
    this.contentType,
    this.contentSeason,
    this.contentEpisode,
    this.cachedAddonSlots,
    this.onAddonSlotsFetched,
    this.onIdentifyTitle,
    this.subtitleIdentityLabel,
    this.onSubtitleStyleChanged,
    this.onSyncRequested,
    this.showSpeed = true,
    required this.speed,
    required this.onSpeedSelected,
    required this.aspectMode,
    required this.onAspectSelected,
    required this.sleepMode,
    this.sleepArmedMinutes = 0,
    this.sleepMinutesLeft = 0,
    this.allowEndOfItem = true,
    required this.onSleepSelected,
    this.hasPlaylist = false,
    this.continuousShuffle = false,
    required this.onShuffleOnce,
    required this.onShuffleContinuousToggle,
  });

  @override
  State<PlayerMenuPanel> createState() => PlayerMenuPanelState();
}

enum _Zone { rail, pane }

/// One row of a value pane. [focusable] rows carry [onTap] or stepper
/// callbacks; the rest (headers, notes) are skipped by traversal.
class _MenuRow {
  final String label;
  final String? sublabel;
  final String? badge;
  final bool selected;
  final bool header;
  final bool note;
  final bool loading;
  final bool destructiveDim; // low-emphasis action (Reset, Retry)
  final Future<void> Function()? onTap;

  // Stepper rows (Style pane): LEFT/RIGHT adjust.
  final String? stepperValue;
  final Color? stepperValueColor;
  final Future<void> Function()? onDecrease;
  final Future<void> Function()? onIncrease;

  const _MenuRow({
    required this.label,
    this.sublabel,
    this.badge,
    this.selected = false,
    this.header = false,
    this.note = false,
    this.loading = false,
    this.destructiveDim = false,
    this.onTap,
    this.stepperValue,
    this.stepperValueColor,
    this.onDecrease,
    this.onIncrease,
  });

  bool get isStepper => onDecrease != null || onIncrease != null;
  bool get focusable => !header && !note && (onTap != null || isStepper);
}

class _SectionDef {
  final PlayerMenuSection id;
  final IconData icon;
  final String label;

  /// Action sections have no value pane — OK/RIGHT fires them directly.
  final bool isAction;
  const _SectionDef(this.id, this.icon, this.label, {this.isAction = false});
}

class PlayerMenuPanelState extends State<PlayerMenuPanel>
    with TickerProviderStateMixin {
  // Spotlight tokens — white ink at graded alphas over black glass; the
  // focused thing is a solid white pill with black text. No chrome color.
  static const _ink = Colors.white;
  static const _glass = Color(0xFF101012);
  static const _statusRed = Color(0xFFE23D4C);

  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'player-menu-panel',
  );
  final ScrollController _railScroll = ScrollController();
  final ScrollController _valuesScroll = ScrollController();

  /// Scroll-target keys, scoped per section: during the pane crossfade the
  /// outgoing and incoming panes are BOTH in the tree, so sharing keys by
  /// index alone would duplicate GlobalKeys across them.
  final Map<(PlayerMenuSection, int), GlobalKey> _paneRowKeys = {};

  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  _Zone _zone = _Zone.rail;
  int _railIndex = 0;
  int _valueIndex = 0;

  /// Remembered value-pane position per section, so re-entering a pane puts
  /// you back where you were.
  final Map<PlayerMenuSection, int> _valueIndexMemory = {};

  /// Focus visuals only once the DPAD is in play (always on television).
  bool _dpadActive = PlatformUtil.isTelevision;

  // ── Subtitle slot state (ported from TracksSheet.show) ──
  List<AddonSubtitleSlot>? _addonSlots;
  bool _slotsFetchStarted = false;
  int _fetchGeneration = 0;
  final Set<String> _retriedAddonIds = {};
  String? _activeImdbId;
  String? _activeContentType;
  int? _activeSeason;
  int? _activeEpisode;
  String? _identityLabel;
  bool _isIdentifying = false;

  // Local selection mirrors (the host's state lags a frame behind).
  late String _selectedAudio;
  late String _selectedSub;
  bool? _passthrough;

  /// The addon subtitle currently downloading, so the row can show it.
  String? _applyingSubId;

  SubtitleSettingsData? _style;

  @override
  void initState() {
    super.initState();
    _selectedAudio = widget.selectedAudioId;
    _selectedSub = widget.selectedSubtitleId;
    _passthrough = widget.audioPassthrough;
    _activeImdbId = widget.contentImdbId;
    _activeContentType = widget.contentType;
    _activeSeason = widget.contentSeason;
    _activeEpisode = widget.contentEpisode;
    _identityLabel = widget.subtitleIdentityLabel;

    // Cached slots may contain LOADING entries if a previous surface closed
    // mid-fetch — surface them as retriable failures, not stuck spinners.
    final cached = widget.cachedAddonSlots;
    if (cached != null) {
      _addonSlots = [
        for (final s in cached)
          s.status == AddonSubtitleStatus.loading
              ? s.copyWith(
                  status: AddonSubtitleStatus.failed,
                  error: 'Fetch was interrupted',
                )
              : s,
      ];
      _slotsFetchStarted = true;
    }

    _railIndex = _sections
        .indexWhere((s) => s.id == widget.initialSection)
        .clamp(0, _sections.length - 1);

    _animController = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );
    _slideAnim =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    // The player root already holds focus in this scope, so autofocus would
    // be discarded — claim it explicitly once mounted (house pattern).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });

    SubtitleSettingsService.instance.loadAll().then((s) {
      if (mounted) setState(() => _style = s);
    });

    _maybeStartSlotsFetch();
  }

  @override
  void didUpdateWidget(PlayerMenuPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reconcile the selection mirrors with genuine host-side changes (track
    // restoration, addon auto-select finishing behind the menu). Comparing
    // against the OLD prop means an unrelated host rebuild can't clobber an
    // optimistic local update that the host hasn't caught up to yet.
    if (widget.selectedAudioId != oldWidget.selectedAudioId) {
      _selectedAudio = widget.selectedAudioId;
    }
    if (widget.selectedSubtitleId != oldWidget.selectedSubtitleId) {
      _selectedSub = widget.selectedSubtitleId;
    }
    if (widget.audioPassthrough != oldWidget.audioPassthrough) {
      _passthrough = widget.audioPassthrough;
    }

    // Sections can appear/disappear live (zapping into a live channel drops
    // Speed; a playlist ending drops Shuffle): follow the focused section by
    // IDENTITY, not index, so "Sleep" doesn't silently become "Aspect".
    final oldSections = _sectionsFor(oldWidget);
    final currentId = _railIndex < oldSections.length
        ? oldSections[_railIndex].id
        : null;
    final sections = _sections;
    final idx = currentId == null
        ? -1
        : sections.indexWhere((s) => s.id == currentId);
    if (idx >= 0) {
      _railIndex = idx;
    } else {
      _railIndex = _railIndex.clamp(0, sections.length - 1);
      _zone = _Zone.rail;
    }
  }

  @override
  void dispose() {
    // Deliberately NOT bumping _fetchGeneration: like the old sheet, a fetch
    // that settles after the panel closed must still write back to the
    // host's cache (mounted guards keep it away from setState).
    _keyboardFocusNode.dispose();
    _railScroll.dispose();
    _valuesScroll.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ── Host BACK (tvOS Menu arrives via PopScope, not as a key) ──

  /// Steps the DPAD out one level. Returns true when the press was spent on
  /// a pane change; false means the host should close the panel.
  bool handleHostBack() {
    if (_zone == _Zone.pane) {
      setState(() => _zone = _Zone.rail);
      return true;
    }
    return false;
  }

  // ── Sections ──

  List<_SectionDef> get _sections => _sectionsFor(widget);

  static List<_SectionDef> _sectionsFor(PlayerMenuPanel w) => [
    const _SectionDef(PlayerMenuSection.audio, Icons.graphic_eq_rounded, 'Audio'),
    const _SectionDef(
      PlayerMenuSection.subtitles,
      Icons.subtitles_rounded,
      'Subtitles',
    ),
    const _SectionDef(
      PlayerMenuSection.style,
      Icons.text_fields_rounded,
      'Subtitle style',
    ),
    if (w.onSyncRequested != null)
      const _SectionDef(
        PlayerMenuSection.sync,
        Icons.swap_horiz_rounded,
        'Sync',
        isAction: true,
      ),
    if (w.showSpeed)
      const _SectionDef(PlayerMenuSection.speed, Icons.speed_rounded, 'Speed'),
    const _SectionDef(
      PlayerMenuSection.aspect,
      Icons.aspect_ratio_rounded,
      'Aspect',
    ),
    const _SectionDef(
      PlayerMenuSection.sleep,
      Icons.bedtime_rounded,
      'Sleep timer',
    ),
    if (w.hasPlaylist)
      const _SectionDef(
        PlayerMenuSection.shuffle,
        Icons.shuffle_rounded,
        'Shuffle',
      ),
  ];

  _SectionDef get _activeSection => _sections[_railIndex];

  String _railCaption(PlayerMenuSection id) {
    switch (id) {
      case PlayerMenuSection.audio:
        final t = widget.audioTracks
            .where((a) => a.id == _selectedAudio)
            .firstOrNull;
        return t?.label ?? (widget.audioTracks.isEmpty ? '—' : 'Auto');
      case PlayerMenuSection.subtitles:
        if (_selectedSub == 'no') return 'Off';
        if (_selectedSub.startsWith('stremio:')) {
          final id = _selectedSub.substring('stremio:'.length);
          for (final slot in _addonSlots ?? const <AddonSubtitleSlot>[]) {
            final sub = slot.subtitles.where((s) => s.id == id).firstOrNull;
            if (sub != null) return sub.displayName;
          }
          return 'Addon';
        }
        final t = widget.embeddedSubtitles
            .where((s) => s.id == _selectedSub)
            .firstOrNull;
        return t?.label ?? (_selectedSub == 'auto' ? 'Auto' : 'Off');
      case PlayerMenuSection.style:
        return _style?.size.label ?? '';
      case PlayerMenuSection.sync:
        final label = _style?.syncOffsetLabel ?? '0';
        return label == '0' ? 'In sync' : label;
      case PlayerMenuSection.speed:
        return _speedLabel(widget.speed);
      case PlayerMenuSection.aspect:
        return _aspectLabel(widget.aspectMode);
      case PlayerMenuSection.sleep:
        return switch (widget.sleepMode) {
          SleepTimerMode.off => 'Off',
          SleepTimerMode.endOfItem => 'End of episode',
          SleepTimerMode.countdown => '${widget.sleepMinutesLeft} min left',
        };
      case PlayerMenuSection.shuffle:
        return widget.continuousShuffle ? 'Continuous' : 'Off';
    }
  }

  static String _speedLabel(double v) =>
      v == 1.0 ? 'Normal' : '${v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '')}×';

  static String _aspectLabel(AspectMode m) => switch (m) {
    AspectMode.contain => 'Contain',
    AspectMode.cover => 'Cover',
    AspectMode.fitWidth => 'Fit width',
    AspectMode.fitHeight => 'Fit height',
    AspectMode.aspect16_9 => '16:9',
    AspectMode.aspect4_3 => '4:3',
    AspectMode.aspect21_9 => '21:9',
    AspectMode.aspect1_1 => '1:1',
    AspectMode.aspect3_2 => '3:2',
    AspectMode.aspect5_4 => '5:4',
    AspectMode.cinemaZoom => 'Cinema Zoom',
  };

  // ── Subtitle slot fetch (ported from TracksSheet.show) ──

  void _maybeStartSlotsFetch() {
    final imdbId = _activeImdbId;
    final type = _activeContentType;
    if (_slotsFetchStarted || imdbId == null || type == null) return;
    _slotsFetchStarted = true;
    final generation = ++_fetchGeneration;
    StremioSubtitleService.instance
        .fetchSubtitleSlots(
          type: type,
          imdbId: imdbId,
          season: _activeSeason,
          episode: _activeEpisode,
          onUpdate: (slots) {
            if (generation != _fetchGeneration) return;
            // The service snapshot doesn't know about retries — keep the
            // locally newer outcome for any retried addon.
            var next = slots;
            final local = _addonSlots;
            if (local != null && _retriedAddonIds.isNotEmpty) {
              next = [
                for (final s in slots)
                  if (_retriedAddonIds.contains(s.addonId))
                    local.firstWhere(
                      (l) => l.addonId == s.addonId,
                      orElse: () => s,
                    )
                  else
                    s,
              ];
            }
            _cacheSlots(next);
            if (!mounted) return;
            setState(() => _addonSlots = next);
          },
        )
        .catchError((Object e) {
          debugPrint('PlayerMenu: slot fetch failed: $e');
          if (generation == _fetchGeneration && mounted) {
            setState(() => _addonSlots ??= const []);
          }
          return const <AddonSubtitleSlot>[];
        });
  }

  /// Cache only fully-settled snapshots (see TracksSheet for why).
  void _cacheSlots(List<AddonSubtitleSlot> slots) {
    if (slots.any((s) => s.status == AddonSubtitleStatus.loading)) return;
    widget.onAddonSlotsFetched?.call(slots);
  }

  void _retryAddon(String addonId) {
    final slots = _addonSlots;
    final imdbId = _activeImdbId;
    final type = _activeContentType;
    if (slots == null || imdbId == null || type == null) return;
    final idx = slots.indexWhere((s) => s.addonId == addonId);
    if (idx < 0 || slots[idx].status == AddonSubtitleStatus.loading) return;
    final generation = _fetchGeneration;
    _retriedAddonIds.add(addonId);
    setState(() {
      _addonSlots = List.of(slots)
        ..[idx] = slots[idx].copyWith(status: AddonSubtitleStatus.loading);
    });
    StremioSubtitleService.instance
        .fetchSingleAddonSlot(
          addonId: addonId,
          type: type,
          imdbId: imdbId,
          season: _activeSeason,
          episode: _activeEpisode,
        )
        .then((settled) {
          if (generation != _fetchGeneration) return;
          final cur = _addonSlots;
          if (cur == null) return;
          final i = cur.indexWhere((s) => s.addonId == addonId);
          if (i < 0) return;
          final updated = List.of(cur)..[i] = settled;
          _cacheSlots(updated);
          if (!mounted) return;
          setState(() => _addonSlots = updated);
        });
  }

  Future<void> _identifyTitle() async {
    final identify = widget.onIdentifyTitle;
    if (identify == null || _isIdentifying) return;
    setState(() => _isIdentifying = true);
    try {
      // Opens routes (search sheet / season dialog) over the panel. The
      // running slot fetch is NOT invalidated up front: a cancelled or
      // failed identify leaves the current identity — and its fetch — alone
      // (invalidating first wedged the pane on "Searching…" forever).
      final result = await identify();
      if (!mounted) return;
      setState(() {
        if (result != null) {
          if (result.slots != null) {
            _fetchGeneration++; // orphan the old identity's fetch
            _addonSlots = result.slots;
            _slotsFetchStarted = true;
            _retriedAddonIds.clear();
          }
          if (result.imdbId != null) {
            _activeImdbId = result.imdbId;
            _activeContentType = result.contentType;
            _activeSeason = result.season;
            _activeEpisode = result.episode;
            if (result.slots == null) {
              // New identity without pre-fetched slots: refetch under it.
              _fetchGeneration++;
              _addonSlots = null;
              _slotsFetchStarted = false;
              _retriedAddonIds.clear();
            }
          }
          _identityLabel = result.identityLabel ?? _identityLabel;
          final selectedId = result.selectedSubtitleId;
          if (selectedId != null) _selectedSub = 'stremio:$selectedId';
        }
        _isIdentifying = false;
      });
      _maybeStartSlotsFetch();
    } catch (e) {
      debugPrint('PlayerMenu: identify failed: $e');
      if (mounted) setState(() => _isIdentifying = false);
    } finally {
      // The route that just popped stole key focus — take it back.
      if (mounted) _keyboardFocusNode.requestFocus();
    }
  }

  // ── Selection appliers (host owns the player) ──

  /// Fires the sync-reset only on a genuine subtitle switch; 'auto' is the
  /// ambiguous sentinel we bias toward keeping the offset for.
  bool _isRealSubtitleChange(String tappedId) =>
      tappedId != _selectedSub && _selectedSub != 'auto';

  Future<void> _selectAudio(String id) async {
    setState(() => _selectedAudio = id);
    await widget.onAudioSelected(id, _selectedSub);
  }

  Future<void> _selectSubtitlesOff() async {
    final realChange = _isRealSubtitleChange('no');
    setState(() => _selectedSub = 'no');
    await widget.onSubtitlesOff(_selectedAudio);
    if (realChange) widget.onSubtitleTrackChanged?.call();
  }

  Future<void> _selectEmbeddedSub(String id) async {
    final realChange = _isRealSubtitleChange(id);
    setState(() => _selectedSub = id);
    await widget.onEmbeddedSubtitleSelected(id, _selectedAudio);
    if (realChange) widget.onSubtitleTrackChanged?.call();
  }

  Future<void> _selectAddonSub(StremioSubtitle sub) async {
    final subId = 'stremio:${sub.id}';
    if (_applyingSubId != null) return;
    final realChange = _isRealSubtitleChange(subId);
    final previous = _selectedSub;
    setState(() {
      _selectedSub = subId;
      _applyingSubId = subId;
    });
    final ok = await widget.onAddonSubtitleSelected(sub, _selectedAudio);
    // The reset belongs to the APPLY, not the panel: closing the panel while
    // the download was in flight must not leave the old subtitle's sync
    // offset on the newly applied one.
    if (ok && realChange) widget.onSubtitleTrackChanged?.call();
    if (!mounted) return;
    setState(() {
      _applyingSubId = null;
      // Download failed: the current subtitle (and its offset) is untouched.
      if (!ok) _selectedSub = previous;
    });
  }

  // ── Value pane content ──

  List<_MenuRow> _rowsFor(_SectionDef section) {
    switch (section.id) {
      case PlayerMenuSection.audio:
        return _audioRows();
      case PlayerMenuSection.subtitles:
        return _subtitleRows();
      case PlayerMenuSection.style:
        return _styleRows();
      case PlayerMenuSection.sync:
        return const [];
      case PlayerMenuSection.speed:
        return [
          for (final v in const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
            _MenuRow(
              label: _speedLabel(v),
              selected: widget.speed == v,
              onTap: () async => widget.onSpeedSelected(v),
            ),
        ];
      case PlayerMenuSection.aspect:
        return [
          for (final m in AspectMode.values)
            _MenuRow(
              label: _aspectLabel(m),
              selected: widget.aspectMode == m,
              onTap: () async => widget.onAspectSelected(m),
            ),
        ];
      case PlayerMenuSection.sleep:
        return _sleepRows();
      case PlayerMenuSection.shuffle:
        return [
          _MenuRow(
            label: 'Play random once',
            sublabel: 'Pick one random item, then resume normal order',
            onTap: () async => widget.onShuffleOnce(),
          ),
          _MenuRow(
            label: 'Continuous shuffle',
            sublabel: 'Keep picking random items after each one ends',
            selected: widget.continuousShuffle,
            onTap: () async => widget.onShuffleContinuousToggle(),
          ),
        ];
    }
  }

  List<_MenuRow> _audioRows() {
    final rows = <_MenuRow>[];
    if (_passthrough != null && widget.onAudioPassthroughChanged != null) {
      rows.add(
        _MenuRow(
          label: 'Passthrough (AC3 · EAC3 · DTS)',
          sublabel: 'Bitstream to your receiver. If you hear silence, '
              'turn this off.',
          selected: _passthrough == true,
          onTap: () async {
            final next = !(_passthrough ?? false);
            setState(() => _passthrough = next);
            await widget.onAudioPassthroughChanged!(next);
          },
        ),
      );
    }
    if (widget.audioTracks.isEmpty) {
      rows.add(const _MenuRow(label: 'No audio tracks in this file', note: true));
    } else {
      for (final t in widget.audioTracks) {
        rows.add(
          _MenuRow(
            label: t.label,
            selected: t.id == _selectedAudio,
            onTap: () => _selectAudio(t.id),
          ),
        );
      }
    }
    return rows;
  }

  List<_MenuRow> _subtitleRows() {
    final rows = <_MenuRow>[];

    if (widget.onIdentifyTitle != null) {
      final label = _identityLabel?.trim();
      rows.add(
        _MenuRow(
          label: 'Wrong subtitles? Fix the title',
          sublabel: label == null || label.isEmpty
              ? 'Title not detected — fix it to find subtitles'
              : label,
          loading: _isIdentifying,
          destructiveDim: true,
          onTap: _identifyTitle,
        ),
      );
    }

    rows.add(
      _MenuRow(
        label: 'Off',
        selected: _selectedSub == 'no',
        onTap: _selectSubtitlesOff,
      ),
    );

    if (widget.embeddedSubtitles.isEmpty) {
      rows.add(
        const _MenuRow(label: 'No embedded subtitles in this file', note: true),
      );
    } else {
      rows.add(const _MenuRow(label: 'Embedded', header: true));
      for (final t in widget.embeddedSubtitles) {
        rows.add(
          _MenuRow(
            label: t.label,
            selected: t.id == _selectedSub,
            onTap: () => _selectEmbeddedSub(t.id),
          ),
        );
      }
    }

    final slots = _addonSlots;
    if (slots == null && _slotsFetchStarted) {
      rows.add(const _MenuRow(label: 'Searching add-ons…', loading: true, note: true));
    }
    for (final slot in slots ?? const <AddonSubtitleSlot>[]) {
      rows.add(_MenuRow(label: slot.addonName, header: true));
      switch (slot.status) {
        case AddonSubtitleStatus.loading:
          rows.add(const _MenuRow(label: 'Fetching…', loading: true, note: true));
        case AddonSubtitleStatus.failed:
          rows.add(
            _MenuRow(
              label: 'Failed — retry',
              sublabel: slot.error,
              destructiveDim: true,
              onTap: () async => _retryAddon(slot.addonId),
            ),
          );
        case AddonSubtitleStatus.ok:
          if (slot.subtitles.isEmpty) {
            rows.add(
              const _MenuRow(label: 'No subtitles from this add-on', note: true),
            );
          } else {
            for (final sub in slot.subtitles) {
              final subId = 'stremio:${sub.id}';
              rows.add(
                _MenuRow(
                  label: sub.displayName,
                  badge: sub.lang.toUpperCase(),
                  selected: subId == _selectedSub,
                  loading: _applyingSubId == subId,
                  onTap: () => _selectAddonSub(sub),
                ),
              );
            }
          }
      }
    }
    return rows;
  }

  List<_MenuRow> _styleRows() {
    final style = _style;
    if (style == null) {
      return const [_MenuRow(label: 'Loading…', loading: true, note: true)];
    }
    final svc = SubtitleSettingsService.instance;

    Future<void> apply(SubtitleSettingsData next) async {
      // The awaited persistence step means this can land after the panel is
      // gone; the host still needs the change, only setState is off-limits.
      if (mounted) {
        setState(() => _style = next);
      } else {
        _style = next;
      }
      widget.onSubtitleStyleChanged?.call(next);
    }

    _MenuRow clampStepper(
      String label,
      String value, {
      Color? valueColor,
      required int index,
      required int max,
      required Future<void> Function(int) save,
      required SubtitleSettingsData Function(int) copy,
    }) {
      Future<void> step(int d) async {
        final next = (index + d).clamp(0, max);
        if (next == index) return;
        await save(next);
        await apply(copy(next));
      }

      return _MenuRow(
        label: label,
        stepperValue: value,
        stepperValueColor: valueColor,
        onDecrease: () => step(-1),
        onIncrease: () => step(1),
      );
    }

    return [
      clampStepper(
        'Size',
        style.size.label,
        index: style.sizeIndex,
        max: SubtitleSize.options.length - 1,
        save: svc.setSizeIndex,
        copy: (i) => style.copyWith(sizeIndex: i),
      ),
      clampStepper(
        'Style',
        style.style.label,
        index: style.styleIndex,
        max: SubtitleStyle.options.length - 1,
        save: svc.setStyleIndex,
        copy: (i) => style.copyWith(styleIndex: i),
      ),
      clampStepper(
        'Color',
        style.color.label,
        valueColor: style.color.color,
        index: style.colorIndex,
        max: SubtitleColor.options.length - 1,
        save: svc.setColorIndex,
        copy: (i) => style.copyWith(colorIndex: i),
      ),
      clampStepper(
        'Outline',
        style.outlineColor.label,
        valueColor: style.outlineColor.color,
        index: style.outlineColorIndex,
        max: SubtitleOutlineColor.options.length - 1,
        save: svc.setOutlineColorIndex,
        copy: (i) => style.copyWith(outlineColorIndex: i),
      ),
      clampStepper(
        'Background',
        style.background.label,
        index: style.bgIndex,
        max: SubtitleBackground.options.length - 1,
        save: svc.setBgIndex,
        copy: (i) => style.copyWith(bgIndex: i),
      ),
      _MenuRow(
        label: 'Font',
        stepperValue: style.font.label,
        onDecrease: () async {
          final newIndex = await SubtitleFontService.instance.cycleFontDown();
          final font = await SubtitleFontService.instance.getSelectedFont();
          await apply(
            style.copyWith(
              fontIndex: newIndex,
              fontFamily: font.fontFamily,
              fontLabel: font.label,
            ),
          );
        },
        onIncrease: () async {
          final newIndex = await SubtitleFontService.instance.cycleFontUp();
          final font = await SubtitleFontService.instance.getSelectedFont();
          await apply(
            style.copyWith(
              fontIndex: newIndex,
              fontFamily: font.fontFamily,
              fontLabel: font.label,
            ),
          );
        },
      ),
      _MenuRow(
        label: 'Bold',
        stepperValue: style.bold ? 'On' : 'Off',
        onDecrease: () async {
          await svc.setBold(!style.bold);
          await apply(style.copyWith(bold: !style.bold));
        },
        onIncrease: () async {
          await svc.setBold(!style.bold);
          await apply(style.copyWith(bold: !style.bold));
        },
      ),
      clampStepper(
        'Elevation',
        style.elevation.label,
        index: style.elevationIndex,
        max: SubtitleElevation.options.length - 1,
        save: svc.setElevationIndex,
        copy: (i) => style.copyWith(elevationIndex: i),
      ),
      _MenuRow(
        label: 'Reset to defaults',
        destructiveDim: true,
        onTap: () async {
          await SubtitleSettingsService.instance.resetToDefaults();
          final fresh = await SubtitleSettingsService.instance.loadAll();
          await apply(fresh);
        },
      ),
    ];
  }

  List<_MenuRow> _sleepRows() {
    final counting = widget.sleepMode == SleepTimerMode.countdown;
    return [
      _MenuRow(
        label: 'Off',
        selected: widget.sleepMode == SleepTimerMode.off,
        onTap: () async => widget.onSleepSelected(SleepTimerSelection.off),
      ),
      for (final minutes in SleepTimerSheet.minuteOptions)
        _MenuRow(
          label: minutes >= 60
              ? (minutes % 60 == 0
                    ? '${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''}'
                    : '1 hour ${minutes % 60}')
              : '$minutes minutes',
          selected: counting && widget.sleepArmedMinutes == minutes,
          sublabel: counting && widget.sleepArmedMinutes == minutes
              ? '${widget.sleepMinutesLeft} min left'
              : null,
          onTap: () async => widget.onSleepSelected(
            SleepTimerSelection(SleepTimerMode.countdown, minutes),
          ),
        ),
      if (widget.allowEndOfItem)
        _MenuRow(
          label: 'End of episode',
          sublabel: 'Stops after this one finishes',
          selected: widget.sleepMode == SleepTimerMode.endOfItem,
          onTap: () async => widget.onSleepSelected(
            const SleepTimerSelection(SleepTimerMode.endOfItem),
          ),
        ),
    ];
  }

  // ── DPAD ──

  /// CONSUMES every key it recognizes (returns handled). A KeyboardListener
  /// cannot consume, so each arrow press also ran the framework's directional
  /// focus traversal — which could silently move primary focus onto the
  /// opacity-hidden TV bar's buttons (LEFT had targets there), after which
  /// the panel never heard another key. Measured on the Apple TV.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;

    final up = key == LogicalKeyboardKey.arrowUp;
    final down = key == LogicalKeyboardKey.arrowDown;
    final left = key == LogicalKeyboardKey.arrowLeft;
    final right = key == LogicalKeyboardKey.arrowRight;
    final back =
        key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;
    final activate = isActivateKey(key);

    if (!up && !down && !left && !right && !back && !activate) {
      return KeyEventResult.ignored;
    }

    if (up || down || left || right) {
      if (!_dpadActive) setState(() => _dpadActive = true);
    }

    if (back) {
      // Consumed here, so the press never reaches the player root — no
      // TvOverlayBack tail needed (marking would swallow the NEXT back).
      if (!isRepeat && !handleHostBack()) {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }

    if (_zone == _Zone.rail) {
      if (up || down) {
        _moveRail(down ? 1 : -1);
      } else if (right || (!isRepeat && activate)) {
        _enterSection();
      }
      return KeyEventResult.handled;
    }

    // ── values zone ──
    final rows = _rowsFor(_activeSection);
    if (rows.isEmpty) return KeyEventResult.handled;
    // Rows can shrink under the focus (an addon settling with fewer
    // subtitles): re-anchor rather than acting on a visually unfocused row.
    if (_valueIndex >= rows.length || !rows[_valueIndex].focusable) {
      final first = _firstFocusable(rows, -1);
      setState(() {
        if (first == null) {
          _zone = _Zone.rail;
        } else {
          _valueIndex = first;
        }
      });
      return KeyEventResult.handled; // this press was spent on re-anchoring
    }
    final row = rows[_valueIndex];

    if (up || down) {
      _moveValues(rows, down ? 1 : -1);
    } else if (row.isStepper && (left || right)) {
      final fn = left ? row.onDecrease : row.onIncrease;
      fn?.call();
    } else if (left) {
      setState(() => _zone = _Zone.rail);
    } else if (!isRepeat && activate) {
      _activateRow(row);
    }
    return KeyEventResult.handled;
  }

  void _moveRail(int delta) {
    final next = (_railIndex + delta).clamp(0, _sections.length - 1);
    if (next == _railIndex) return;
    setState(() {
      _railIndex = next;
      _valueIndex = _valueIndexMemory[_sections[next].id] ?? 0;
    });
  }

  void _enterSection() {
    final section = _activeSection;
    if (section.isAction) {
      if (section.id == PlayerMenuSection.sync) {
        widget.onClose();
        widget.onSyncRequested?.call();
      }
      return;
    }
    final rows = _rowsFor(section);
    final first = _firstFocusable(rows, _valueIndexMemory[section.id] ?? -1);
    if (first == null) return;
    setState(() {
      _zone = _Zone.pane;
      _valueIndex = first;
    });
    _scrollValueIntoView();
  }

  /// Remembered index if still focusable, else the first focusable row, else
  /// null (nothing to enter).
  int? _firstFocusable(List<_MenuRow> rows, int remembered) {
    if (remembered >= 0 &&
        remembered < rows.length &&
        rows[remembered].focusable) {
      return remembered;
    }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].focusable) return i;
    }
    return null;
  }

  void _moveValues(List<_MenuRow> rows, int delta) {
    var i = _valueIndex;
    while (true) {
      i += delta;
      if (i < 0 || i >= rows.length) return; // edge: stay put
      if (rows[i].focusable) break;
    }
    setState(() {
      _valueIndex = i;
      _valueIndexMemory[_activeSection.id] = i;
    });
    _scrollValueIntoView();
  }

  void _scrollValueIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx =
          _paneRowKeys[(_activeSection.id, _valueIndex)]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _activateRow(_MenuRow row) {
    if (row.isStepper) {
      row.onIncrease?.call();
      return;
    }
    row.onTap?.call();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720;
    final panelWidth = compact
        ? size.width
        : (size.width * 0.46).clamp(430.0, 560.0);

    // On television the host's PopScope (TV controls) already routes BACK /
    // tvOS Menu here via handleHostBack — a second PopScope would fire too
    // and double-step. Everywhere else the panel must gate the route pop
    // itself, or the phone's system Back would quit the whole player.
    if (!PlatformUtil.isTelevision) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (!handleHostBack()) widget.onClose();
        },
        child: _buildBody(compact, panelWidth),
      );
    }
    return _buildBody(compact, panelWidth);
  }

  Widget _buildBody(bool compact, double panelWidth) {
    return Stack(
      children: [
        // Scrim: the picture dims but never disappears. Tap closes.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.20),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: _slideAnim,
            child: SizedBox(
              width: panelWidth,
              height: double.infinity,
              child: Focus(
                focusNode: _keyboardFocusNode,
                onKeyEvent: _handleKey,
                child: _buildGlass(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: compact ? 168 : 208, child: _buildRail()),
                      Container(width: 0.75, color: _ink.withValues(alpha: 0.09)),
                      Expanded(child: _buildValues()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Black glass: real blur where it's cheap (tvOS / phones / desktop), a
  /// near-opaque fill on Android TV boxes where BackdropFilter janks.
  Widget _buildGlass({required Widget child}) {
    final content = Container(
      decoration: BoxDecoration(
        color: PlatformUtil.isAndroidTvCached
            ? const Color(0xF5101012)
            : _glass.withValues(alpha: 0.72),
        border: Border(
          left: BorderSide(color: _ink.withValues(alpha: 0.14), width: 0.75),
        ),
      ),
      child: child,
    );
    if (PlatformUtil.isAndroidTvCached) return content;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: content,
      ),
    );
  }

  Widget _buildRail() {
    final sections = _sections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 14),
          child: Text(
            'PLAYER MENU',
            style: TextStyle(
              color: _ink.withValues(alpha: 0.42),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.0,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _railScroll,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
            itemCount: sections.length,
            itemBuilder: (context, i) {
              final s = sections[i];
              final focused = _dpadActive && _zone == _Zone.rail && i == _railIndex;
              final selected = _zone == _Zone.pane && i == _railIndex;
              return _RailRow(
                icon: s.icon,
                label: s.label,
                caption: _railCaption(s.id),
                focused: focused,
                selected: selected,
                onTap: () {
                  setState(() => _railIndex = i);
                  _enterSection();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildValues() {
    final section = _activeSection;
    final rows = section.isAction ? const <_MenuRow>[] : _rowsFor(section);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.03, 0),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(section.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 30, 24, 14),
            child: Text(
              section.label.toUpperCase(),
              style: TextStyle(
                color: _ink.withValues(alpha: 0.42),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.0,
              ),
            ),
          ),
          Expanded(
            child: section.isAction
                ? _buildActionHint()
                : ListView.builder(
                    controller: _valuesScroll,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final key = row.focusable
                          ? _paneRowKeys.putIfAbsent(
                              (section.id, i),
                              () => GlobalKey(),
                            )
                          : null;
                      final focused = _dpadActive &&
                          _zone == _Zone.pane &&
                          i == _valueIndex &&
                          row.focusable;
                      return KeyedSubtree(
                        key: key,
                        child: _ValueRow(
                          row: row,
                          focused: focused,
                          onTap: row.focusable
                              ? () {
                                  setState(() {
                                    _zone = _Zone.pane;
                                    _valueIndex = i;
                                    _valueIndexMemory[section.id] = i;
                                  });
                                  _activateRow(row);
                                }
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 4, 24, 0),
      child: Text(
        'Opens the sync controls over the video.',
        style: TextStyle(
          color: _ink.withValues(alpha: 0.45),
          fontSize: 12.5,
          height: 1.5,
        ),
      ),
    );
  }
}

// ── Row widgets ─────────────────────────────────────────────────────────────

class _RailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String caption;
  final bool focused;
  final bool selected;
  final VoidCallback onTap;

  const _RailRow({
    required this.icon,
    required this.label,
    required this.caption,
    required this.focused,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const ink = Colors.white;
    final fg = focused ? Colors.black : ink.withValues(alpha: 0.80);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        scale: focused ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: focused
                ? ink
                : selected
                ? ink.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 22,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: fg.withValues(alpha: focused ? 1 : 0.75)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (caption.isNotEmpty)
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: focused
                              ? Colors.black.withValues(alpha: 0.55)
                              : ink.withValues(alpha: 0.42),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final _MenuRow row;
  final bool focused;
  final VoidCallback? onTap;

  const _ValueRow({required this.row, required this.focused, this.onTap});

  static const _ink = Colors.white;
  static const _statusRed = PlayerMenuPanelState._statusRed;

  @override
  Widget build(BuildContext context) {
    if (row.header) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 6),
        child: Row(
          children: [
            Text(
              row.label.toUpperCase(),
              style: TextStyle(
                color: _ink.withValues(alpha: 0.35),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      );
    }
    if (row.note) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
        child: Row(
          children: [
            if (row.loading) ...[
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Text(
                row.label,
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.40),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final fg = focused
        ? Colors.black
        : _ink.withValues(alpha: row.destructiveDim ? 0.55 : 0.85);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        scale: focused ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: focused ? _ink : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (row.badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: focused
                                    ? Colors.black.withValues(alpha: 0.40)
                                    : _ink.withValues(alpha: 0.34),
                                width: 0.75,
                              ),
                              borderRadius: BorderRadius.circular(3.5),
                            ),
                            child: Text(
                              row.badge!,
                              style: TextStyle(
                                color: focused
                                    ? Colors.black.withValues(alpha: 0.65)
                                    : _ink.withValues(alpha: 0.70),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (row.sublabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          row.sublabel!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: focused
                                ? Colors.black.withValues(alpha: 0.50)
                                : _ink.withValues(alpha: 0.45),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (row.loading)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: focused ? Colors.black54 : Colors.white38,
                  ),
                )
              else if (row.isStepper)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepChevron(
                      icon: Icons.chevron_left_rounded,
                      focused: focused,
                      onTap: row.onDecrease == null
                          ? null
                          : () => row.onDecrease!(),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 64),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // A color value is shown as a bordered swatch, not
                          // as text ink — white text on the white focus pill
                          // (or black on the glass) would vanish.
                          if (row.stepperValueColor != null) ...[
                            Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: row.stepperValueColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: focused
                                      ? Colors.black.withValues(alpha: 0.4)
                                      : _ink.withValues(alpha: 0.4),
                                  width: 0.75,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              row.stepperValue ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: focused
                                    ? Colors.black
                                    : _ink.withValues(alpha: 0.85),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StepChevron(
                      icon: Icons.chevron_right_rounded,
                      focused: focused,
                      onTap: row.onIncrease == null
                          ? null
                          : () => row.onIncrease!(),
                    ),
                  ],
                )
              else if (row.selected)
                Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: focused ? Colors.black : _ink.withValues(alpha: 0.9),
                )
              else if (row.destructiveDim && row.label.startsWith('Failed'))
                const Icon(Icons.refresh_rounded, size: 15, color: _statusRed),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepChevron extends StatelessWidget {
  final IconData icon;
  final bool focused;
  final VoidCallback? onTap;

  const _StepChevron({required this.icon, required this.focused, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          icon,
          size: 19,
          color: onTap == null
              ? (focused ? Colors.black26 : Colors.white24)
              : (focused
                    ? Colors.black.withValues(alpha: 0.75)
                    : Colors.white.withValues(alpha: 0.65)),
        ),
      ),
    );
  }
}
