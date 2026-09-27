import 'dart:async';
import '../data/home_hero_live_repository.dart';

/// One mounted Spotlight card's candidate request and fallback lifetime.
/// The widget owns displayed URL and whether publication requires a rebuild.
class HomeSpotlightLivePreview {
  HomeSpotlightLivePreview({
    required HomeHeroLiveRepository repository,
    required bool Function() isOwnerCurrent,
  }) : _repository = repository,
       _isOwnerCurrent = isOwnerCurrent;

  final HomeHeroLiveRepository _repository;
  final bool Function() _isOwnerCurrent;
  List<String>? _candidates;
  int _generation = 0;
  bool _disposed = false;
  bool get _active => !_disposed && _isOwnerCurrent();

  bool isAddonChannel(String key) => _repository.isAddonChannel(key);

  void resolve({
    required String channelKey,
    required bool isSeries,
    required bool Function() isCurrent,
    required void Function(String? url, bool notify) publish,
    bool notify = true,
  }) {
    if (!_active) return;
    final generation = ++_generation;
    _candidates = null;
    if (isSeries) {
      publish(null, notify);
      return;
    }
    if (!isAddonChannel(channelKey)) {
      publish(channelKey, notify);
      return;
    }
    publish(null, notify);
    bool current() => _active && isCurrent() && generation == _generation;
    if (!current()) return;
    // The borrowed service converts resolution failures to an empty ladder.
    unawaited(
      _repository.resolveCandidates(channelKey).then((found) {
        if (!current() || found.isEmpty) return;
        _candidates = [for (final candidate in found) candidate.url];
        publish(_candidates!.first, true);
      }),
    );
  }

  void playbackFailed({
    required String? currentUrl,
    required String channelKey,
    required void Function(String?) publish,
  }) {
    if (!_active) return;
    final candidates = _candidates;
    if (candidates == null || currentUrl == null) return;
    final next = candidates.indexOf(currentUrl) + 1;
    if (next <= 0 || next >= candidates.length) {
      _repository.invalidate(channelKey);
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
