import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/metadata_preferences.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/metadata_feature_policy.dart';
import 'metadata_feature_dependencies.dart';

final metadataFeaturePolicyProvider = NotifierProvider.autoDispose
    .family<
      MetadataFeatureController,
      MetadataFeaturePolicy,
      MetadataFeatureSession
    >(
      MetadataFeatureController.new,
      retry: (count, error) => null,
      dependencies: [metadataFeatureReaderProvider],
    );

/// Accepted discovery policy and readiness, independently owned by each view.
class MetadataFeatureController extends Notifier<MetadataFeaturePolicy> {
  MetadataFeatureController(this.session);
  final MetadataFeatureSession session;
  late MetadataFeatureReader _read;
  MetadataFeaturePolicy _accepted = (preferences: null, ready: false);
  int _generation = 0;

  @override
  MetadataFeaturePolicy build() {
    _read = ref.watch(metadataFeatureReaderProvider(session));
    ref.onDispose(() => _generation++);
    return _accepted;
  }

  MetadataFeaturePolicy get current =>
      ref.mounted ? state : (preferences: null, ready: false);
  bool get _active =>
      ref.mounted && session.owner == ProfileSessionMemory.captureOwner();

  /// Retain the last policy while preventing suggestions under stale settings.
  void invalidate() {
    if (!_active) return;
    _generation++;
    _accepted = (preferences: state.preferences, ready: false);
    state = _accepted;
  }

  Future<void> load({
    required bool Function() isCurrent,
    required void Function(MetadataPreferences) onAccepted,
  }) async {
    if (!_active || !isCurrent()) return;
    final generation = ++_generation;
    bool active() => _active && generation == _generation && isCurrent();
    try {
      final preferences = await _read();
      if (!active()) return;
      _accepted = (preferences: preferences, ready: true);
      state = _accepted;
      if (active()) onAccepted(preferences);
    } catch (_) {
      // Preserve the legacy optional-policy behavior: no automatic retry or
      // fallback to an enabled default after an unavailable settings read.
    }
  }
}
