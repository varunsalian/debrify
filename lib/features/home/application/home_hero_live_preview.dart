import 'dart:async';
import '../data/home_hero_live_repository.dart';

/// One view's live-channel candidate request and fallback ladder. Channel
/// selection, displayed URL, player teardown and shell artwork stay with the view.
class HomeHeroLivePreview {
  HomeHeroLivePreview({
    required HomeHeroLiveRepository repository,
    required bool Function() isOwnerCurrent,
  }) : _repository = repository,
       _isOwnerCurrent = isOwnerCurrent;

  final HomeHeroLiveRepository _repository;
  final bool Function() _isOwnerCurrent;
  int _generation = 0;
  List<String>? _candidates;
  bool _disposed = false;
  bool get _active => !_disposed && _isOwnerCurrent();

  void load(
    String channelKey, {
    required bool Function() isCurrent,
    required void Function() prepare,
    required void Function(String) publish,
  }) {
    if (!_active) return;
    _candidates = null;
    final generation = ++_generation;
    // The caller clears the trailer, displayed live URL and shell artwork in
    // its existing order, before any synchronous URL or asynchronous lookup.
    prepare();
    if (!_active || !isCurrent() || generation != _generation) return;
    if (!_repository.isAddonChannel(channelKey)) {
      publish(channelKey);
      return;
    }
    unawaited(
      _repository.resolveCandidates(channelKey).then((found) {
        if (!_active ||
            !isCurrent() ||
            generation != _generation ||
            found.isEmpty) {
          return;
        }
        _candidates = [for (final candidate in found) candidate.url];
        publish(_candidates!.first);
      }),
    );
  }

  /// Preserve the two separate clear points around visible channel/takeover
  /// notifications: invalidate first, then clear the ladder after those writes.
  void invalidateRequest() => _generation++;
  void clearCandidates() => _candidates = null;

  void playbackFailed({
    required String? currentUrl,
    required String? Function() channelKey,
    required void Function(String?) publish,
  }) {
    if (!_active) return;
    final candidates = _candidates;
    if (candidates == null || currentUrl == null) return;
    final next = candidates.indexOf(currentUrl) + 1;
    if (next <= 0 || next >= candidates.length) {
      // Exhausted/unknown current URL: invalidate the original service cache
      // before clearing video, so a later selection obtains fresh links.
      final key = channelKey();
      if (key != null) _repository.invalidate(key);
      publish(null);
      return;
    }
    publish(candidates[next]);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _candidates = null;
  }
}
