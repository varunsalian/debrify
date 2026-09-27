import 'dart:async';
import 'home_configuration_changes.dart';

typedef HomeSettingsStep = Future<void> Function(bool Function() isCurrent);

/// Orders settings refreshes without owning their state or presentation effects.
class HomeSettingsRefresh {
  HomeSettingsRefresh({required this.isOwnerCurrent});
  final bool Function() isOwnerCurrent;
  int _generation = 0;
  bool _disposed = false;

  Future<void> run({
    required bool Function() isCurrent,
    required HomeSettingsStep refreshAppearance,
    required HomeSettingsStep refreshDisplay,
    required Future<bool> Function(bool Function()) refreshContinuation,
    required void Function() reconcileContinuation,
    required HomeSettingsStep refreshTrailers,
    required HomeSettingsStep selectDefaultView,
    required Future<HomeConfigurationChanges?> Function(bool Function())
    refreshConfiguration,
    required void Function(HomeConfigurationChanges) applyConfiguration,
  }) async {
    bool active() => !_disposed && isOwnerCurrent() && isCurrent();
    if (!active()) return;
    final generation = ++_generation;
    bool current() => active() && generation == _generation;
    await refreshAppearance(current);
    if (!current()) return;
    await refreshDisplay(current);
    if (!current()) return;
    final mergeChanged = await refreshContinuation(current);
    if (!current()) return;
    if (mergeChanged) reconcileContinuation();
    if (!current()) return;
    // Preserve independent volume refresh: default/config reads do not await it.
    unawaited(refreshTrailers(current));
    if (!current()) return;
    await selectDefaultView(current);
    if (!current()) return;
    final changes = await refreshConfiguration(current);
    if (!current() || changes == null || !changes.changed) return;
    applyConfiguration(changes);
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}
