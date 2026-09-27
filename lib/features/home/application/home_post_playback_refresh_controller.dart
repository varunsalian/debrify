import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/home_catalog_session.dart';

final homePostPlaybackRefreshProvider = NotifierProvider.autoDispose
    .family<HomePostPlaybackRefreshController, bool, HomeCatalogSession>(
      HomePostPlaybackRefreshController.new,
      retry: (count, error) => null,
      dependencies: const [],
    );

/// A view's playback latch and ordered return refresh. Individual loaders keep
/// their data, stale-result guards and retries; this owner only sequences them.
class HomePostPlaybackRefreshController extends Notifier<bool> {
  HomePostPlaybackRefreshController(this.session);
  final HomeCatalogSession session;
  bool _accepted = false;
  int _lifetime = 0;

  @override
  bool build() {
    ref.onDispose(() => _lifetime++);
    return _accepted;
  }

  bool get playedSinceRefresh => ref.mounted ? state : _accepted;
  bool get _active =>
      ref.mounted && session.owner == ProfileSessionMemory.captureOwner();

  void markPlaybackStarted() {
    if (!_active) return;
    _accepted = true;
    state = true;
  }

  Future<void> refresh({
    required bool searchMode,
    bool trackers = false,
    required bool Function() isCurrent,
    required void Function() clearResume,
    required Future<void> Function() watchlist,
    required Future<void> Function() local,
    required Future<void> Function() iptv,
    required Future<void> Function() trakt,
    required Future<void> Function() simkl,
    required bool Function() shouldRefreshMdblist,
    required Future<void> Function() mdblist,
    required Future<void> Function() boundSources,
    required void Function(Object error) onError,
  }) async {
    final lifetime = _lifetime;
    bool current() => _active && lifetime == _lifetime && isCurrent();
    if (!current()) return;
    clearResume();
    if (!current()) return;
    // Consume before the first await. Concurrent returns still refresh local
    // rows, but only this invocation owns the consumed tracker refresh. A new
    // playback during an in-flight refresh leaves a new latch for the next one.
    final withTrackers = trackers || state;
    _accepted = false;
    state = false;
    try {
      if (!current()) return;
      await watchlist();
      if (!current()) return;
      await local();
      if (!current()) return;
      await iptv();
      if (!current()) return;
      if (withTrackers && !searchMode) {
        await Future.wait([
          trakt(),
          simkl(),
          // Evaluate after local refreshes, preserving the scrobble controller's
          // current pending/force-fresh decision rather than capturing it early.
          if (shouldRefreshMdblist()) mdblist(),
        ]);
        if (!current()) return;
      }
      // These badges inspect the newly accepted local and tracker lists.
      await boundSources();
    } catch (error) {
      // Preserve the caller's diagnostic path; route callbacks are unawaited.
      onError(error);
    }
  }
}
