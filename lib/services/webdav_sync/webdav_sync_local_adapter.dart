import '../profiles/profile_package_service.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/profile_registry.dart';
import '../profiles/profile_runtime.dart';
import '../profiles/profile_scope.dart';
import 'webdav_sync_active_profile_refresh.dart';

final class WebDavSyncLocalSession {
  const WebDavSyncLocalSession(this.scope, {void Function()? revalidate})
    : _revalidate = revalidate;

  final ProfileScope scope;
  final void Function()? _revalidate;

  void validate() => _revalidate?.call();
}

final class WebDavSyncLocalProfileSnapshot {
  const WebDavSyncLocalProfileSnapshot({
    required this.localProfileId,
    required this.rawPreferences,
    required this.portablePreferences,
    this.mutationToken,
  });

  final String localProfileId;
  final Map<String, Object?> rawPreferences;
  final Map<String, Object?> portablePreferences;
  final ProfilePreferenceMutationToken? mutationToken;
}

abstract interface class WebDavSyncLocalAdapter {
  Future<WebDavSyncLocalSession> beginCycle();

  Future<WebDavSyncLocalProfileSnapshot> readProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
  );

  Future<void> applyProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
    Map<String, Object> values, {
    ProfilePreferenceMutationToken? expectedMutationToken,
    Future<void> Function()? beforeWrite,
    bool replayingPending = false,
  });
}

/// ProfilePreferences-backed adapter used once M5 arms the engine.
final class ProfileWebDavSyncLocalAdapter implements WebDavSyncLocalAdapter {
  ProfileWebDavSyncLocalAdapter(
    this.registry, {
    WebDavSyncActiveProfileRefresher? activeProfileRefresher,
  }) : _activeProfileRefresher =
           activeProfileRefresher ??
           const DefaultWebDavSyncActiveProfileRefresher();

  final ProfileRegistry registry;
  final WebDavSyncActiveProfileRefresher _activeProfileRefresher;

  @override
  Future<WebDavSyncLocalSession> beginCycle() async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      throw StateError('WebDAV sync requires committed Profiles');
    }
    final scope = ProfileRuntime.capture();
    return WebDavSyncLocalSession(
      scope,
      revalidate: () => _validateScope(scope),
    );
  }

  @override
  Future<WebDavSyncLocalProfileSnapshot> readProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
  ) async {
    _validateSession(session);
    final profile = await registry.getProfile(localProfileId);
    _validateSession(session);
    if (profile == null) {
      throw StateError('A mapped WebDAV sync profile is unavailable');
    }
    final scope = ProfileScope(
      profileId: profile.id,
      dataGeneration: profile.visibleDataGeneration,
      sessionEpoch: session.scope.sessionEpoch,
    );
    return ProfilePreferences.captureMutationSnapshot((mutationToken) async {
      _validateSession(session);
      final prefs = await ProfilePreferences.forCapturedScope(
        scope,
        CapturedProfilePreferenceAccess.diagnosticsReadOnly,
      );
      final raw = <String, Object?>{
        for (final key in prefs.getKeys()) key: prefs.get(key),
      };
      final portable = await ProfilePackageService.exportPortablePreferences(
        scope,
        includeCredentialEngineSettings: false,
      );
      _validateSession(session);
      return WebDavSyncLocalProfileSnapshot(
        localProfileId: localProfileId,
        rawPreferences: Map<String, Object?>.unmodifiable(raw),
        portablePreferences: Map<String, Object?>.unmodifiable(portable),
        mutationToken: mutationToken,
      );
    });
  }

  @override
  Future<void> applyProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
    Map<String, Object> values, {
    ProfilePreferenceMutationToken? expectedMutationToken,
    Future<void> Function()? beforeWrite,
    bool replayingPending = false,
  }) async {
    _validateSession(session);
    final profile = await registry.getProfile(localProfileId);
    _validateSession(session);
    if (profile == null) {
      throw StateError('A mapped WebDAV sync profile is unavailable');
    }
    // Read the visible generation immediately before apply. Adoption and
    // profile refresh can replace it between the cycle's read and write.
    final scope = ProfileScope(
      profileId: profile.id,
      dataGeneration: profile.visibleDataGeneration,
      sessionEpoch: session.scope.sessionEpoch,
    );
    final prefs = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.syncApply,
    );
    if (!await prefs.applySyncBatch(
      values,
      authorizationBarrier: () => _validateSession(session),
      expectedMutationToken: expectedMutationToken,
      beforeWrite: beforeWrite,
      replayCommittedTarget: replayingPending,
      afterApply: (appliedScope, changedKeys) async {
        if (appliedScope != session.scope) return;
        await _activeProfileRefresher.refresh(
          changedKeys,
          authorizationBarrier: () => _validateSession(session),
        );
      },
    )) {
      throw StateError('Could not apply WebDAV sync preferences');
    }
    _validateSession(session);
  }

  static void _validateSession(WebDavSyncLocalSession session) {
    _validateScope(session.scope);
  }

  static void _validateScope(ProfileScope scope) {
    if (!ProfileRuntime.isInitialized ||
        !ProfileRuntime.isProfileCommitted ||
        ProfileRuntime.scope.value != scope) {
      throw StateError('Profile session changed during WebDAV sync');
    }
  }
}
