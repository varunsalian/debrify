import 'package:flutter/material.dart';

import '../services/watched_status_service.dart';

/// A quiet watched marker for movie posters.
///
/// The state lookup is backed by profile preferences (already memory-backed)
/// and refreshes only when movie completion changes, rather than on animation
/// or scroll frames.
class MovieWatchedBadge extends StatefulWidget {
  const MovieWatchedBadge({
    super.key,
    required this.imdbId,
    this.contentType = 'movie',
    this.compact = false,
    this.tickPolicyScoped = false,
  });

  final String imdbId;
  final String contentType;
  final bool compact;

  /// Draw the ✓ only for histories selected in Settings → Tracking → Watched
  /// ticks. Poster cards everywhere opt in; in-guide episode ticks do not
  /// (those follow the Progress source instead).
  final bool tickPolicyScoped;

  @override
  State<MovieWatchedBadge> createState() => _MovieWatchedBadgeState();
}

class _MovieWatchedBadgeState extends State<MovieWatchedBadge> {
  WatchedStatusService get _status => WatchedStatusService.instance;

  @override
  void initState() {
    super.initState();
    _status.addListener(_refresh);
    _status.ensureStarted();
  }

  @override
  void didUpdateWidget(MovieWatchedBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imdbId != widget.imdbId ||
        oldWidget.contentType != widget.contentType) {
      _refresh();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Navigator changes TickerMode when Home is covered/revealed. This is the
    // demand edge that consumes a deferred MDBList watched-state invalidation.
    if (TickerMode.valuesOf(context).enabled) _status.ensureStarted();
  }

  @override
  void dispose() {
    _status.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (TickerMode.valuesOf(context).enabled) _status.ensureStarted();
    final watched = widget.tickPolicyScoped
        ? _status.isWatchedForTicks(widget.imdbId, widget.contentType)
        : _status.isWatched(widget.imdbId, widget.contentType);
    if (!watched) {
      return const SizedBox.shrink();
    }
    final extent = widget.compact ? 20.0 : 23.0;
    return IgnorePointer(
      child: Container(
        width: extent,
        height: extent,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.30),
            width: 0.7,
          ),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.check_rounded,
          size: widget.compact ? 13 : 15,
          color: const Color(0xFFE8FFF4),
        ),
      ),
    );
  }
}
