import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/discover_source_repository.dart';
import '../models/discover_source_state.dart';
import 'discover_source_dependencies.dart';

final discoverSourceProvider = NotifierProvider.autoDispose
    .family<
      DiscoverSourceController,
      DiscoverSourceState,
      DiscoverSourceSession
    >(
      DiscoverSourceController.new,
      retry: (count, error) => null,
      dependencies: [discoverSourceRepositoryProvider],
    );

class DiscoverSourceController extends Notifier<DiscoverSourceState> {
  DiscoverSourceController(this.session);
  final DiscoverSourceSession session;
  late DiscoverSourceRepository _repository;
  DiscoverSourceState? _accepted;
  int _selectionRevision = 0;
  int _generation = 0;
  int _writeGeneration = 0;

  @override
  DiscoverSourceState build() {
    _repository = ref.watch(discoverSourceRepositoryProvider(session));
    ref.onDispose(() {
      _generation++;
      _writeGeneration++;
    });
    return _accepted ??= DiscoverSourceState(source: session.initialSource);
  }

  bool get _active =>
      ref.mounted && session.owner == ProfileSessionMemory.captureOwner();
  DiscoverSourceState get current => ref.mounted
      ? state
      : const DiscoverSourceState(source: DiscoverSources.cw);
  void _publish(DiscoverSourceState next) {
    _accepted = next;
    state = next;
  }

  Future<void> rememberCurrent({required bool Function() isCurrent}) {
    if (!_active || !isCurrent()) return Future.value();
    final generation = ++_writeGeneration;
    return _repository.writeLast(
      state.source,
      () => _active && generation == _writeGeneration && isCurrent(),
    );
  }

  bool select(
    String source, {
    required bool discoveryEnabled,
    required bool Function() isCurrent,
    required void Function() beforeChange,
    required void Function() onChanged,
  }) {
    if (!_active ||
        !isCurrent() ||
        source == state.source ||
        (source == DiscoverSources.tmdb && !discoveryEnabled)) {
      return false;
    }
    beforeChange();
    if (!_active || !isCurrent()) return false;
    _selectionRevision++;
    _publish(DiscoverSourceState(source: source, addons: state.addons));
    if (!_active || !isCurrent()) return false;
    onChanged();
    unawaited(rememberCurrent(isCurrent: isCurrent));
    return true;
  }

  Future<void> load({
    required bool Function() isCurrent,
    required bool mdblistEnabled,
    required Future<bool> Function() discoveryEnabled,
    required void Function(List<StremioAddon>) onInventory,
    required void Function() onChanged,
  }) async {
    if (!_active || !isCurrent()) return;
    final generation = ++_generation;
    final revision = _selectionRevision;
    bool active() => _active && generation == _generation && isCurrent();
    bool ownsLanding() =>
        active() &&
        discoverLandingLoadIsCurrent(
          capturedRevision: revision,
          currentRevision: _selectionRevision,
          hasPendingHandoff: session.hasHandoff,
        );
    var landing = await _repository.readLanding();
    if (!active()) return;
    if (landing == DiscoverSources.tmdb) {
      final enabled = await discoveryEnabled();
      if (!active()) return;
      if (!enabled) landing = DiscoverSources.cw;
    }
    final fixed = {
      DiscoverSources.cw,
      DiscoverSources.trakt,
      DiscoverSources.simkl,
      DiscoverSources.tmdb,
      DiscoverSources.jellyfin,
      DiscoverSources.emby,
      if (mdblistEnabled) DiscoverSources.mdblist,
    }.contains(landing);
    if (fixed && ownsLanding()) {
      if (state.source != landing) {
        _publish(DiscoverSourceState(source: landing, addons: state.addons));
        if (!active()) return;
        onChanged();
      }
      if (ownsLanding()) unawaited(rememberCurrent(isCurrent: ownsLanding));
    }
    if (!active()) return;
    List<StremioAddon> addons = const [];
    try {
      addons = await _repository.readAddons();
    } catch (_) {}
    if (!active()) return;
    final browsable = List<StremioAddon>.unmodifiable([
      for (final addon in addons)
        if (addon.catalogs.any((catalog) => catalog.isBrowsable)) addon,
    ]);
    final available =
        landing.startsWith(DiscoverSources.addonPrefix) &&
        browsable.any(
          (addon) => '${DiscoverSources.addonPrefix}${addon.id}' == landing,
        );
    if (!fixed && !available) landing = DiscoverSources.cw;
    onInventory(List.unmodifiable(addons));
    if (!active()) return;
    _publish(
      DiscoverSourceState(
        source: !fixed && ownsLanding() ? landing : state.source,
        addons: browsable,
      ),
    );
    if (!active()) return;
    onChanged();
    if (!fixed && ownsLanding()) {
      unawaited(rememberCurrent(isCurrent: ownsLanding));
    }
  }
}
