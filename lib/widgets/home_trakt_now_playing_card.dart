import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/stremio_addon.dart';
import '../services/trakt/trakt_service.dart';
import '../services/trakt/trakt_item_transformer.dart';

/// Compact "Now Playing" bar — slim music-player style with poster art.
/// Self-hides when nothing is playing. No DPAD focus (purely informational).
class HomeTraktNowPlayingCard extends StatefulWidget {
  final bool isTelevision;

  const HomeTraktNowPlayingCard({
    super.key,
    this.isTelevision = false,
  });

  /// True when there's currently an active Trakt scrobble (something playing).
  ///
  /// Exposed as a global notifier so sibling Home widgets (like
  /// HomeTodayCalendarCard) can subscribe and adjust their visibility when
  /// the user is actively watching something.
  static final ValueNotifier<bool> isScrobbleActive =
      ValueNotifier<bool>(false);

  @override
  State<HomeTraktNowPlayingCard> createState() => HomeTraktNowPlayingCardState();
}

class HomeTraktNowPlayingCardState extends State<HomeTraktNowPlayingCard> {
  _NowPlayingData? _data;
  bool _isLoading = true;
  int _loadGeneration = 0;
  Timer? _refreshTimer;
  Timer? _progressTimer;
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  // Cached auth state — avoid hitting storage on every 30s poll
  bool? _cachedAuth;
  DateTime? _cachedAuthAt;

  static const _red = Color(0xFFE50914); // Netflix red
  static const _watchingGreen = Color(0xFF10B981);
  static const _pollWhenPlaying = Duration(seconds: 30);
  static const _pollWhenIdle = Duration(minutes: 2);
  static const _authCacheTtl = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void reload() => _load();

  Future<bool> _checkAuth() async {
    final now = DateTime.now();
    if (_cachedAuth != null &&
        _cachedAuthAt != null &&
        now.difference(_cachedAuthAt!) < _authCacheTtl) {
      return _cachedAuth!;
    }
    final isAuth = await TraktService.instance.isAuthenticated();
    _cachedAuth = isAuth;
    _cachedAuthAt = now;
    return isAuth;
  }

  void _scheduleNextLoad({required bool playing}) {
    _refreshTimer?.cancel();
    final delay = playing ? _pollWhenPlaying : _pollWhenIdle;
    _refreshTimer = Timer(delay, _load);
  }

  Future<void> _load() async {
    final gen = ++_loadGeneration;
    try {
      final isAuth = await _checkAuth();
      if (!isAuth || !mounted || gen != _loadGeneration) {
        _finishEmpty(gen);
        return;
      }
      final raw = await TraktService.instance.fetchNowWatching();
      if (!mounted || gen != _loadGeneration) return;
      if (raw == null) { _finishEmpty(gen); return; }

      final data = _parseResponse(raw);
      if (!mounted || gen != _loadGeneration) return;

      setState(() { _data = data; _isLoading = false; });
      HomeTraktNowPlayingCard.isScrobbleActive.value = data != null;

      _progressTimer?.cancel();
      if (data != null) {
        _progress.value = data.currentProgress;
        _progressTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) {
            if (!mounted || _data == null) return;
            _progress.value = _data!.currentProgress;
          },
        );
      }
      _scheduleNextLoad(playing: data != null);
    } catch (e) {
      debugPrint('HomeTraktNowPlayingCard: load error: $e');
      if (mounted && gen == _loadGeneration) _finishEmpty(gen);
    }
  }

  void _finishEmpty(int gen) {
    if (!mounted || gen != _loadGeneration) return;
    _progressTimer?.cancel();
    setState(() { _data = null; _isLoading = false; });
    HomeTraktNowPlayingCard.isScrobbleActive.value = false;
    _scheduleNextLoad(playing: false);
  }

  // ── Parse /users/me/watching ──────────────────────────────────────────────

  _NowPlayingData? _parseResponse(Map<String, dynamic> raw) {
    try {
      final type = raw['type'] as String?;
      if (type == null) return null;
      final startedAt = DateTime.tryParse(raw['started_at'] as String? ?? '');
      final expiresAt = DateTime.tryParse(raw['expires_at'] as String? ?? '');

      if (type == 'movie') {
        final meta = TraktItemTransformer.transformItem(raw);
        if (meta == null) return null;
        return _NowPlayingData(
          meta: meta,
          type: 'movie',
          startedAt: startedAt,
          expiresAt: expiresAt,
        );
      }
      if (type == 'episode') {
        final show = raw['show'] as Map<String, dynamic>?;
        final ep   = raw['episode'] as Map<String, dynamic>?;
        if (show == null || ep == null) return null;
        // Episodes don't have their own art — use the show's metadata
        final meta = TraktItemTransformer.transformItem(
          {'show': show},
          inferredType: 'show',
        );
        if (meta == null) return null;
        return _NowPlayingData(
          meta: meta,
          type: 'episode',
          startedAt: startedAt,
          expiresAt: expiresAt,
          season:  ep['season'] as int?,
          episode: ep['number'] as int?,
        );
      }
      return null;
    } catch (e) {
      debugPrint('HomeTraktNowPlayingCard: parse error: $e');
      return null;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _data == null) return const SizedBox.shrink();
    return _buildBar(_data!);
  }

  Widget _buildBar(_NowPlayingData data) {
    final double barHeight   = widget.isTelevision ? 68 : 64;
    final double posterWidth = widget.isTelevision ? 62 : 58;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, widget.isTelevision ? 4 : 3, 12, 0),
      child: _buildBarInner(data, barHeight, posterWidth),
    );
  }

  Widget _buildBarInner(
    _NowPlayingData data,
    double barHeight,
    double posterWidth,
  ) {
    return Container(
      height: barHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: widget.isTelevision ? null : [
          BoxShadow(
            color: _red.withValues(alpha: 0.28),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: _red.withValues(alpha: 0.10),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (data.backdropUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: data.backdropUrl,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF0D1117)),
              ),

            // Single clean left-to-right gradient: solid dark over the text
            // area (left 60%), smoothly fading into the fanart on the right.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFF0D1117),
                    Color(0xFF0D1117),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
            ),

            // Thin red border on top of everything.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _red.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
            ),

            Positioned(
              left: 0, right: 0,
              top: 0, bottom: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _PulsingDot(color: _red),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'TRAKT - WATCHING',
                                style: TextStyle(
                                  color: _watchingGreen,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              if (data.episodeLabel != null) ...[
                                Text(
                                  '  ·  ${data.episodeLabel}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: widget.isTelevision ? 16 : 15,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Empty flex space on the right — reveals the fanart
                    // through the transparent end of the gradient. Progress
                    // is communicated by the red bar along the bottom.
                    const Spacer(flex: 3),
                  ],
                ),
              ),
            ),

            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Stack(
                children: [
                  Container(
                    height: 3,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (_, p, __) => FractionallySizedBox(
                      widthFactor: (p / 100).clamp(0.0, 1.0),
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: _red,
                          boxShadow: [
                            BoxShadow(
                              color: _red.withValues(alpha: 0.7),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pulsing dot ────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7, height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

// ── Data model ─────────────────────────────────────────────────────────────

class _NowPlayingData {
  final StremioMeta meta;
  final String type;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final int? season;
  final int? episode;

  const _NowPlayingData({
    required this.meta,
    required this.type,
    this.startedAt,
    this.expiresAt,
    this.season,
    this.episode,
  });

  String get title => meta.name;
  String get posterUrl => meta.poster ?? '';
  String get backdropUrl => meta.background ?? '';

  double get currentProgress {
    if (startedAt == null || expiresAt == null) return 0;
    final total = expiresAt!.difference(startedAt!).inSeconds;
    if (total <= 0) return 0;
    return (DateTime.now().difference(startedAt!).inSeconds / total * 100)
        .clamp(0.0, 100.0);
  }

  String? get episodeLabel {
    if (type != 'episode' || season == null || episode == null) return null;
    return 'S${season!.toString().padLeft(2, '0')}E${episode!.toString().padLeft(2, '0')}';
  }
}
