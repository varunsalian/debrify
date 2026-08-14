import 'package:flutter/foundation.dart';

import 'profile_runtime.dart';
import 'profile_scope.dart';

/// Identity captured by a mounted UI surface for process-memory that may only
/// be reused during the same profile session.
///
/// The lifecycle revision is part of the identity so an outgoing widget that
/// disposes after a profile switch has begun cannot repopulate a cache for the
/// incoming profile.
@immutable
class ProfileSessionOwner {
  final ProfileRuntimeMode? runtimeMode;
  final ProfileScope? scope;
  final int lifecycleRevision;

  const ProfileSessionOwner._({
    required this.runtimeMode,
    required this.scope,
    required this.lifecycleRevision,
  });

  @override
  bool operator ==(Object other) =>
      other is ProfileSessionOwner &&
      other.runtimeMode == runtimeMode &&
      other.scope == scope &&
      other.lifecycleRevision == lifecycleRevision;

  @override
  int get hashCode => Object.hash(runtimeMode, scope, lifecycleRevision);
}

abstract interface class _ProfileSessionClearable {
  void clear();
}

class _ProfileSessionEntry<T> {
  final ProfileSessionOwner owner;
  final T value;

  const _ProfileSessionEntry(this.owner, this.value);
}

/// A process-lifetime, single-value cache whose contents are owned by the
/// profile session that created them.
///
/// Instantiate this only as a static field. A lifecycle clear both drops its
/// retained value and advances the owner revision. The revision closes the
/// late-dispose race: an old screen may store again after the clear, but a new
/// screen captures a different owner and rejects that value.
class ProfileSessionMemory<T> implements _ProfileSessionClearable {
  static final Set<_ProfileSessionClearable> _stores =
      <_ProfileSessionClearable>{};
  static int _lifecycleRevision = 0;

  _ProfileSessionEntry<T>? _entry;

  ProfileSessionMemory() {
    _stores.add(this);
  }

  static ProfileSessionOwner captureOwner() {
    final mode = ProfileRuntime.isInitialized ? ProfileRuntime.mode : null;
    final scope = mode == ProfileRuntimeMode.profileCommitted
        ? ProfileRuntime.scope.value
        : null;
    return ProfileSessionOwner._(
      runtimeMode: mode,
      scope: scope,
      lifecycleRevision: _lifecycleRevision,
    );
  }

  void store(ProfileSessionOwner owner, T value) {
    _entry = _ProfileSessionEntry<T>(owner, value);
  }

  /// Consumes a value owned by [owner]. A value from any other profile,
  /// generation, session epoch, or lifecycle revision is discarded.
  ///
  /// When [where] rejects a matching value it remains available for the
  /// matching sibling surface, such as another SearchScreen variant.
  T? take(ProfileSessionOwner owner, {bool Function(T value)? where}) {
    final entry = _entry;
    if (entry == null) return null;
    if (entry.owner != owner) {
      _entry = null;
      return null;
    }
    if (where != null && !where(entry.value)) return null;
    _entry = null;
    return entry.value;
  }

  @override
  void clear() {
    _entry = null;
  }

  /// Invalidates every registered profile-session cache before a switch or
  /// reset. Static stores stay registered so future values are also covered.
  static void clearAll() {
    _lifecycleRevision++;
    for (final store in _stores) {
      store.clear();
    }
  }

  @visibleForTesting
  static void debugReset() {
    for (final store in _stores) {
      store.clear();
    }
    _lifecycleRevision = 0;
  }
}
