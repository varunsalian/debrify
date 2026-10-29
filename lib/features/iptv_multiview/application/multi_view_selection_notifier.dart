// Application layer for multi-view: owns the active profile's tile selection.
// The notifier keeps one immutable [MultiViewSelection] and drops it as soon
// as the owning profile changes, so a profile switch never leaks another
// profile's channels into the grid.
import 'package:debrify/features/iptv_multiview/models/multi_view_selection.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The active profile's identity (compared with ==); the app overrides this
/// so the selection is scoped to whoever is watching. Defaults to no profile.
final multiViewOwnerProvider = Provider<Object? Function()>(
  (ref) =>
      () => null,
);

/// How many tiles may play at once. Defaults to the desktop/Android-TV cap.
final multiViewMaxTilesProvider = Provider<int>((ref) => 4);

/// The active profile's multi-view selection.
final multiViewSelectionProvider =
    NotifierProvider<MultiViewSelectionNotifier, MultiViewSelection>(
      MultiViewSelectionNotifier.new,
    );

final class MultiViewSelectionNotifier extends Notifier<MultiViewSelection> {
  /// Rebuilds only when the tile cap changes. The owner is re-read on every
  /// access instead: the closure behind [multiViewOwnerProvider] can be
  /// rebound to another profile without the provider identity changing, and
  /// [current] is what catches that switch.
  @override
  MultiViewSelection build() {
    ref.watch(multiViewMaxTilesProvider);
    return MultiViewSelection(owner: ref.read(multiViewOwnerProvider)());
  }

  /// Two channels are the same tile when their `url` is equal. Adding stops
  /// once the selection reaches [multiViewMaxTilesProvider].
  MultiViewAddResult add(IptvChannel channel) {
    final selection = current();
    if (selection.channels.any((c) => c.url == channel.url)) {
      return MultiViewAddResult.duplicate;
    }
    if (selection.channels.length >= ref.read(multiViewMaxTilesProvider)) {
      return MultiViewAddResult.full;
    }
    _publish(
      [...selection.channels, channel],
      selection.audioIndex,
      selection.owner,
    );
    return MultiViewAddResult.added;
  }

  /// Removes the tile at [index] (out of range is ignored). The sound keeps
  /// following its tile, or falls back to the first tile when that tile left.
  void remove(int index) {
    final selection = current();
    if (index < 0 || index >= selection.channels.length) {
      return;
    }
    final channels = [...selection.channels]..removeAt(index);
    var audioIndex = selection.audioIndex;
    if (audioIndex == index) {
      audioIndex = 0;
    } else if (index < audioIndex) {
      audioIndex -= 1;
    }
    if (audioIndex >= channels.length) {
      audioIndex = 0;
    }
    _publish(channels, audioIndex, selection.owner);
  }

  /// Makes the tile at [index] the one with sound (ignored if out of range).
  void setAudio(int index) {
    final selection = current();
    if (index < 0 || index >= selection.channels.length) {
      return;
    }
    if (index == selection.audioIndex) {
      return;
    }
    _publish(selection.channels, index, selection.owner);
  }

  /// Whether [channel] (matched by url) already occupies a tile.
  bool contains(IptvChannel channel) {
    return current().channels.any((c) => c.url == channel.url);
  }

  /// Empties the selection, keeping the current owner.
  void clear() {
    final selection = current();
    if (selection.isEmpty) {
      return;
    }
    _publish(const [], 0, selection.owner);
  }

  /// The current selection, empty when the owner changed since it was made.
  /// Does not mutate state.
  MultiViewSelection current() {
    final owner = ref.read(multiViewOwnerProvider)();
    final selection = state;
    if (selection.owner != owner) {
      return MultiViewSelection(owner: owner);
    }
    return selection;
  }

  /// Replaces the published state; [owner] is the profile the new selection
  /// belongs to (the caller resolved it through [current], so it is never a
  /// stale profile).
  void _publish(List<IptvChannel> channels, int audioIndex, Object? owner) {
    state = MultiViewSelection(
      channels: List.unmodifiable(channels),
      audioIndex: audioIndex,
      owner: owner,
    );
  }
}
