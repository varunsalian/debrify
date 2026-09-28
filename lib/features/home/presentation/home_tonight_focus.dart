import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../models/home_tonight_card_info.dart';
import 'home_stage_rows.dart';

/// Tonight's remembered focus zone/queue position and focused-card caption.
/// Owns only the caption signal; row nodes and target lookup remain borrowed.
class HomeTonightFocus {
  HomeTonightFocus({required this.railKeyOf, required this.nearestNode});

  final String Function(HomeRail) railKeyOf;
  final FocusNode? Function(List<FocusNode>, int) nearestNode;
  final card = ValueNotifier<HomeTonightCardInfo?>(null);
  bool isQueue = true;
  int _queueIndex = 0;
  String? _queueKey;
  bool _disposed = false;

  String _keyOf(HomeTonightQueueEntry entry) =>
      '${railKeyOf(entry.rail)}#${entry.col}';

  /// Rail identity wins over the old index when tracker rows arrive above it.
  int resolveIndex(List<HomeTonightQueueEntry> queue) {
    if (queue.isEmpty) return 0;
    final key = _queueKey;
    if (key != null) {
      final index = queue.indexWhere((entry) => _keyOf(entry) == key);
      if (index >= 0) return index;
    }
    return _queueIndex.clamp(0, queue.length - 1);
  }

  bool focusQueue(List<HomeTonightQueueEntry> queue) {
    if (_disposed || queue.isEmpty) return false;
    final entry = queue[resolveIndex(queue)];
    var node = nearestNode(entry.rail.cw!.nodes, entry.col);
    // A remembered lazy row may be detached. The first queue entry is the
    // existing fallback; update memory only if that entry has a mounted node.
    if (node == null) {
      final first = queue.first;
      node = nearestNode(first.rail.cw!.nodes, first.col);
      if (node != null) {
        _queueIndex = 0;
        _queueKey = _keyOf(first);
      }
    }
    if (node == null) return false;
    isQueue = true;
    node.requestFocus();
    return true;
  }

  bool focusRail(FocusNode? node) {
    if (_disposed || node == null) return false;
    isQueue = false;
    node.requestFocus();
    return true;
  }

  void selectQueue(HomeTonightQueueEntry entry, int index, StremioMeta item) {
    if (_disposed) return;
    isQueue = true;
    _queueIndex = index;
    _queueKey = _keyOf(entry);
    final row = entry.rail.cw!;
    card.value = HomeTonightCardInfo(
      // Select opens detail; hold opens the preference-aware Play/Remove menu.
      action: 'Open',
      holdAction: 'Options',
      episode: row.episodeOf(item),
      progress: row.progressOf(item),
    );
  }

  void selectRail(HomeRail rail, StremioMeta item) {
    if (_disposed) return;
    isQueue = false;
    card.value = HomeTonightCardInfo(
      action: 'Open',
      // Only continuation cards have hold-OK menus on TV.
      holdAction: rail.cw != null ? 'Options' : null,
      episode: rail.cw?.episodeOf(item),
      progress: rail.cw?.progressOf(item),
    );
  }

  /// Position reset is separate from caption reset to retain the host's
  /// existing ordered notifications during a layout transition.
  void resetPosition() {
    isQueue = true;
    _queueIndex = 0;
    _queueKey = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    card.dispose();
  }
}
