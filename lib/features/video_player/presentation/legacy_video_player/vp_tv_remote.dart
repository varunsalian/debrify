import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/models/channel_entry.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpTvRemoteHost {
  bool get anyPlayerOverlayOpen;
  List<ChannelEntry> get channelEntries;
  ValueNotifier<bool> get controlsVisible;
  Duration get duration;
  List<IptvChannel>? get effectiveIptvChannels;
  bool get hasStremioTvGuide;
  bool get isPlaying;
  bool get isReady;
  bool get isTransitioning;
  mk.Player get player;
  Duration get position;
  bool get tvNoTimeline;
  FocusNode get tvPlayPauseFocus;
  FocusNode get tvProgressFocus;
  int get tvScrubGeneration;
  Duration? get tvScrubTarget;
  set tvScrubTarget(Duration? v);
  void scheduleAutoHide();
  void tvShowBar();
  void tvHideBar();
  void togglePlay();
  bool get mounted;
  void setState(VoidCallback fn);
  Future<Map<String, dynamic>?> Function(String channelId)?
  get requestChannelById;
  void showChannelGuideOverlay();
  void showIptvChannelSheetOverlay();
  void mdblistScrobbleSeek(Duration target);
  void simklScrobbleSeek(Duration seekTarget);
  SkipSegment? get activeSkipSegment;
  void skipActiveSegment();
  void showStremioTvGuideOverlay();
  void traktScrobbleSeek(Duration seekTarget);
  void zapIptvChannel(int delta);
  bool get canZapIptvChannel;
}

class VpTvRemote {
  VpTvRemote(this._host);
  final VpTvRemoteHost _host;

  /// When the last LEFT/RIGHT arrived, so a held key (fast repeats) can be
  /// told from deliberate taps without needing key-up, which the tvOS fork
  /// does not reliably deliver.
  DateTime? tvLastArrowAt;
  bool tvScrubWasPlaying = false;
  int tvScrubRepeats = 0;

  /// The generation in force when the current scrub began.
  int tvScrubStartedAtGeneration = 0;

  /// Cinema scrub: hold LEFT/RIGHT to pause and preview a destination, OK to
  /// confirm, BACK/DOWN to cancel. One seek on confirm, so the trackers and
  /// resume see a single jump instead of a burst.
  void tvScrubBegin(int direction) {
    if (_host.tvNoTimeline) return;
    tvScrubStartedAtGeneration = _host.tvScrubGeneration;
    tvScrubWasPlaying = _host.isPlaying;
    if (_host.isPlaying) _host.player.pause();
    _host.tvScrubTarget = _host.position;
    _host.tvShowBar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_host.mounted && _host.tvScrubTarget != null)
        _host.tvProgressFocus.requestFocus();
    });
    tvScrubStep(direction);
  }

  void tvScrubStep(int direction) {
    final base = _host.tvScrubTarget;
    if (base == null) return;
    // Accelerate with the hold: fine control at first, then long strides so a
    // two-hour remux is crossable without holding the key for a minute.
    final step = tvScrubRepeats < 8
        ? 10
        : tvScrubRepeats < 16
        ? 30
        : 60;
    tvScrubRepeats++;
    final next = base + Duration(seconds: step * direction);
    _host.setState(() {
      _host.tvScrubTarget = next < Duration.zero
          ? Duration.zero
          : (next > _host.duration ? _host.duration : next);
    });
    _host.scheduleAutoHide();
  }

  void tvScrubCommit() {
    final target = _host.tvScrubTarget;
    // Captured when the scrub STARTED. Reading it here would always match and
    // the guard would never fire — a scrub begun before a source switch would
    // happily seek whatever replaced it.
    final generation = tvScrubStartedAtGeneration;
    if (target == null) return;
    _host.setState(() => _host.tvScrubTarget = null);
    tvScrubRepeats = 0;
    // A source switch or dispose bumps the generation; a confirm that lands
    // afterwards must not seek whatever replaced the item being scrubbed.
    if (generation != _host.tvScrubGeneration || !_host.mounted) return;
    _host.player.seek(target);
    _host.traktScrobbleSeek(target);
    _host.simklScrobbleSeek(target);
    _host.mdblistScrobbleSeek(target);
    if (tvScrubWasPlaying) _host.player.play();
    if (!_host.anyPlayerOverlayOpen) _host.tvPlayPauseFocus.requestFocus();
    // Fresh interval: the countdown that was running belonged to the scrub,
    // and inheriting its remainder could drop the bar the instant OK lands.
    _host.scheduleAutoHide();
  }

  /// Drop a scrub without seeking and without touching playback — the item it
  /// belonged to is going away. Restoring "was playing" here would fight the
  /// transition, which drives play/pause itself.
  void tvAbandonScrub() {
    if (_host.tvScrubTarget == null) return;
    _host.tvScrubTarget = null;
    tvScrubRepeats = 0;
  }

  void tvScrubCancel() {
    if (_host.tvScrubTarget == null) return;
    _host.setState(() => _host.tvScrubTarget = null);
    tvScrubRepeats = 0;
    if (tvScrubWasPlaying) _host.player.play();
    if (!_host.anyPlayerOverlayOpen) _host.tvPlayPauseFocus.requestFocus();
    _host.scheduleAutoHide();
  }

  /// Opens whichever guide this session actually has, in the order the dock
  /// offers them. Returns false when there is none, so the caller can fall back
  /// to raising the transport bar.
  bool openTvGuide() {
    if (_host.channelEntries.isNotEmpty && _host.requestChannelById != null) {
      _host.showChannelGuideOverlay();
      return true;
    }
    if (_host.hasStremioTvGuide) {
      _host.showStremioTvGuideOverlay();
      return true;
    }
    if (_host.effectiveIptvChannels?.isNotEmpty == true) {
      _host.showIptvChannelSheetOverlay();
      return true;
    }
    return false;
  }

  /// Returns null to let the desktop mapping below handle the key.
  KeyEventResult? handleTvKey(LogicalKeyboardKey key) {
    // Not const: LogicalKeyboardKey overrides ==, which a const set forbids.
    // The Siri Remote's click pad arrives as `enter` (measured on device);
    // `select`/`gameButtonA` cover Android TV remotes and game controllers.
    final activate = <LogicalKeyboardKey>{
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.gameButtonA,
    };
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    final isRight = key == LogicalKeyboardKey.arrowRight;
    final isBack =
        key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;

    // A scrub in flight owns the remote completely.
    if (_host.tvScrubTarget != null) {
      if (isLeft || isRight) {
        tvScrubStep(isRight ? 1 : -1);
      } else if (activate.contains(key)) {
        tvScrubCommit();
      } else if (isBack || key == LogicalKeyboardKey.arrowDown) {
        tvScrubCancel();
      }
      return KeyEventResult.handled;
    }

    // Nothing is actionable until the first frame, and acting during a
    // transition would drive the OUTGOING item.
    // Nothing is actionable before the first frame, and during a switch most
    // actions would drive the OUTGOING item. Two exceptions, both deliberate:
    // BACK must always get you out (a tune can hang on the network), and
    // LEFT/RIGHT must still zap, because a newer switch is allowed to
    // supersede a slow one (_iptvSwitchTicket).
    if (!_host.isReady || _host.isTransitioning) {
      if (isBack) return null;
      // Zap directly rather than falling through: the mapping below only zaps
      // when the bar is hidden, so with it up the press would reach the seek
      // branch and seek the OUTGOING item.
      if ((isLeft || isRight) && _host.canZapIptvChannel) {
        _host.zapIptvChannel(isRight ? 1 : -1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (!_host.controlsVisible.value) {
      if (activate.contains(key)) {
        // While a skip is offered it owns OK: the button is on screen naming
        // the action, and it lives outside the bar's focus scope so the remote
        // has no other way to reach it.
        if (_host.activeSkipSegment != null) {
          _host.skipActiveSegment();
          return KeyEventResult.handled;
        }
        // Native TV player: OK both toggles playback and raises the bar.
        _host.togglePlay();
        _host.tvShowBar();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _host.tvShowBar();
        return KeyEventResult.handled;
      }
      // UP opens the guide, matching the native TV player. The desktop mapping
      // below only knows the Debrify-TV and Stremio guides, so on an IPTV
      // session it fell through to volume and UP appeared dead.
      if (key == LogicalKeyboardKey.arrowUp) {
        if (openTvGuide()) return KeyEventResult.handled;
        _host.tvShowBar();
        return KeyEventResult.handled;
      }
      if ((isLeft || isRight) && _host.tvNoTimeline) {
        // No timeline to move along. Hand the key down ONLY when the mapping
        // below has something real to do with it — zapping to the next
        // channel. Falling through unconditionally reached the generic 10s
        // seek, which on a live stream is a blind jump on a rolling window and
        // on a `hideSeekbar` session is exactly the seek that session turned
        // off. And never enter a scrub whose progress row is hidden.
        return _host.canZapIptvChannel ? null : KeyEventResult.handled;
      }
      if ((isLeft || isRight) && !_host.canZapIptvChannel) {
        // Repeats arriving in quick succession mean the key is held; the third
        // one enters scrub. Slower taps stay 10s nudges, so a single press
        // still does the obvious thing.
        final now = DateTime.now();
        final last = tvLastArrowAt;
        tvScrubRepeats =
            (last != null && now.difference(last).inMilliseconds < 400)
            ? tvScrubRepeats + 1
            : 0;
        tvLastArrowAt = now;
        if (tvScrubRepeats >= 2 && _host.duration > Duration.zero) {
          tvScrubRepeats = 0;
          tvScrubBegin(isRight ? 1 : -1);
          return KeyEventResult.handled;
        }
      }
      // UP keeps its existing precedence (channel guide, Stremio guide) and
      // LEFT/RIGHT fall through to zap-or-seek, both already below.
      return null;
    }

    // Bar up: it owns the DPAD and OK.
    if (isBack) {
      _host.tvHideBar();
      return KeyEventResult.handled;
    }
    if ((isLeft || isRight) && _host.tvProgressFocus.hasFocus) {
      if (!_host.tvNoTimeline) {
        tvScrubBegin(isRight ? 1 : -1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled; // nothing to scrub; don't fall through
    }
    _host.scheduleAutoHide();
    // Traversal and activation belong to the bar's own focus tree.
    return KeyEventResult.ignored;
  }
}
