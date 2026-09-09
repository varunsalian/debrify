import '../profiles/profile_authorization.dart';
import '../profiles/profile_preferences.dart';
import 'webdav_sync_adoption.dart';
import 'webdav_sync_adoption_models.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_discovery.dart';
import 'webdav_sync_engine.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_manifest_publisher.dart';
import 'webdav_sync_models.dart';

typedef WebDavSyncAuthorizationRecapture =
    Future<ProfileAuthorizationContext> Function();

/// Completes first connection to an existing folder. Durable bootstrap
/// adoption phases are resumed from the engine-state journal, so a retry after
/// a crash does not restore an already-applied package again.
final class WebDavSyncExistingRootConnector {
  const WebDavSyncExistingRootConnector({
    required WebDavSyncBindingStore bindingStore,
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncExistingRootDiscoverer discovery,
    required WebDavSyncAdoptionRunner adoption,
    required WebDavSyncSeedPublisher publisher,
    required WebDavSyncCycleRunner engine,
    this.preferenceFenceRetrySpacing = const Duration(milliseconds: 250),
  }) : _bindingStore = bindingStore,
       _stateRepository = stateRepository,
       _discovery = discovery,
       _adoption = adoption,
       _publisher = publisher,
       _engine = engine;

  static const int preferenceFenceAttemptLimit = 5;

  final WebDavSyncBindingStore _bindingStore;
  final WebDavSyncEngineStateRepository _stateRepository;
  final WebDavSyncExistingRootDiscoverer _discovery;
  final WebDavSyncAdoptionRunner _adoption;
  final WebDavSyncSeedPublisher _publisher;
  final WebDavSyncCycleRunner _engine;
  final Duration preferenceFenceRetrySpacing;

  Future<WebDavSyncBinding> connect({
    required String bindingId,
    required ProfileAuthorizationContext authorization,
    required WebDavSyncAuthorizationRecapture recaptureAuthorization,
    required bool replacementConfirmed,
    bool completeOnboarding = false,
  }) async {
    var authorityCommitted = false;
    WebDavSyncExistingRootSnapshot? discovered;
    try {
      if (!replacementConfirmed) {
        throw StateError(
          'Replacing local profiles requires explicit confirmation',
        );
      }
      final beforeResume = await _bindingStore.load();
      authorityCommitted =
          beforeResume.bindings[bindingId]?.lifecycle ==
          WebDavSyncLifecycle.active;
      final resumed = await _finishInterruptedPromotion(bindingId);
      if (resumed != null) {
        if (!completeOnboarding) return resumed;
        authorityCommitted = true;
        await _bindingStore.acknowledgeOnboardingIntent(bindingId);
        return (await _bindingStore.load()).activeBinding!;
      }

      final beforeDiscovery = await _bindingStore.load();
      final pendingBinding =
          beforeDiscovery.bindings[bindingId] ??
          (throw StateError('WebDAV sync binding is unavailable'));
      var currentAuthorization = authorization;
      var state = await _stateRepository.load(pendingBinding.namespaceId);
      if (state.adoption != null) {
        final recovered = await _adoption.recover(pendingBinding.namespaceId);
        authorityCommitted = recovered != null;
        currentAuthorization = await recaptureAuthorization();
        state = await _stateRepository.load(pendingBinding.namespaceId);
      }
      authorityCommitted =
          authorityCommitted ||
          state.hasAuthenticatedMaps &&
              state.circleToLocalProfiles!.containsValue(
                currentAuthorization.profileId,
              );

      final snapshot = await _discovery.discover(
        bindingId: bindingId,
        // Durable adoption has already published these profiles. A retry
        // still authenticates root, manifests and descriptor, but needs no
        // second archive download, decryption or extraction.
        materializeBootstrap:
            !(state.hasAuthenticatedMaps &&
                state.circleToLocalProfiles!.containsValue(
                  currentAuthorization.profileId,
                )),
      );
      discovered = snapshot;
      state = await _stateRepository.load(snapshot.namespace.id);

      final bootstrapDigest = snapshot.bootstrap.document.semanticDigest;
      final restoredProfiles =
          snapshot.namespace.values['backupRestoreProfileIds'];
      final restoredResources =
          snapshot.namespace.values['backupRestoreResourceIds'];
      final legacyRestoreMaps =
          restoredProfiles is Map && restoredResources is Map;
      final restoringBackup =
          snapshot.namespace.values['backupRestore'] == true ||
          legacyRestoreMaps;
      if (legacyRestoreMaps && !state.hasAuthenticatedMaps) {
        state = await _stateRepository.update(
          snapshot.namespace.id,
          (current) => current.copyWith(
            circleToLocalProfiles: Map<String, String>.from(restoredProfiles),
            circleToLocalResources: Map<String, String>.from(restoredResources),
          ),
        );
      }
      final adoptedBootstrapBelongsToActiveProfiles =
          state.hasAuthenticatedMaps &&
          state.circleToLocalProfiles!.containsValue(
            currentAuthorization.profileId,
          );
      authorityCommitted =
          authorityCommitted || adoptedBootstrapBelongsToActiveProfiles;
      // Restored data is already published locally. Never replace it with a
      // remote bootstrap: publish the restored records, then perform a merge.
      if (!restoringBackup && !adoptedBootstrapBelongsToActiveProfiles) {
        await _adoption.adopt(
          WebDavSyncAdoptionRequest(
            namespaceId: snapshot.namespace.id,
            mode: WebDavSyncAdoptionMode.firstJoin,
            package: snapshot.bootstrap.document.package,
            graphSemanticDigest: bootstrapDigest,
            profileMap:
                snapshot.bootstrap.document.snapshot?.profileMap ??
                snapshot.bootstrap.manifest.profileMap,
            resourceMap:
                snapshot.bootstrap.document.snapshot?.resourceMap ??
                snapshot.bootstrap.manifest.resourceMap,
            databaseFileResolver:
                snapshot.bootstrap.document.restoreStage?.resolveDatabase,
            snapshot: snapshot.bootstrap.document.snapshot,
            authorization: currentAuthorization,
            replacementConfirmed: true,
            completeOnboarding: completeOnboarding,
          ),
        );
        authorityCommitted = true;
        currentAuthorization = await recaptureAuthorization();
        state = await _stateRepository.load(snapshot.namespace.id);
      }
      if (state.adoption != null || !state.hasAuthenticatedMaps) {
        throw StateError('WebDAV sync adoption did not finish safely');
      }

      final published = await _retryPreferenceFence(
        () => _publisher.publish(
          bindingId: bindingId,
          authorization: currentAuthorization,
        ),
      );
      if (published == null) return _awaitingBinding(bindingId);
      state = await _stateRepository.load(snapshot.namespace.id);
      final report = await _retryPreferenceFence(
        () => _engine.runCycle(
          WebDavSyncCycleContext(
            namespaceId: snapshot.namespace.id,
            deviceId: snapshot.namespace.deviceId,
            markerPin: snapshot.markerBytes,
            authorityContentHash: snapshot.namespace.pinnedAuthorityHash,
            root: snapshot.root,
            circleToLocalProfiles: state.circleToLocalProfiles,
            circleToLocalResources: state.circleToLocalResources,
            wireProfileMap: published.manifest.profileMap,
            wireResourceMap: published.manifest.resourceMap,
            active: false,
          ),
          allowPreActivation: true,
        ),
      );
      if (report == null) return _awaitingBinding(bindingId);
      if (report.disposition != WebDavSyncCycleDisposition.completed) {
        throw StateError('WebDAV sync could not complete its first merge');
      }
      state = await _stateRepository.load(snapshot.namespace.id);
      if (state.adoption != null ||
          !state.hasAuthenticatedMaps ||
          state.ownManifest == null) {
        throw StateError('WebDAV sync activation state is incomplete');
      }
      await _bindingStore.activateAndPromoteStaged(bindingId);
      final active = (await _bindingStore.load()).activeBinding;
      if (active == null || active.id != bindingId) {
        throw StateError('WebDAV sync binding promotion failed');
      }
      if (completeOnboarding) {
        await _bindingStore.acknowledgeOnboardingIntent(bindingId);
        return (await _bindingStore.load()).activeBinding!;
      }
      return active;
    } catch (error, stackTrace) {
      if (!authorityCommitted || error is WebDavSyncPostHandoffException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      Error.throwWithStackTrace(
        WebDavSyncPostHandoffException(error),
        stackTrace,
      );
    } finally {
      await discovered?.bootstrap.document.dispose();
    }
  }

  /// Retries only an optimistic profile-preference fence. Callers place this
  /// around snapshot/build/commit work after durable adoption has completed,
  /// so restore, database carry-forward, and identity-map minting cannot be
  /// repeated by routine first-launch preference churn.
  Future<T?> _retryPreferenceFence<T extends Object>(
    Future<T> Function() operation,
  ) async {
    for (var attempt = 1; attempt <= preferenceFenceAttemptLimit; attempt++) {
      try {
        return await operation();
      } on ProfilePreferenceMutationConflict {
        if (attempt == preferenceFenceAttemptLimit) return null;
        await Future<void>.delayed(preferenceFenceRetrySpacing);
      }
    }
    return null;
  }

  Future<WebDavSyncBinding> _awaitingBinding(String bindingId) async {
    final stored = await _bindingStore.load();
    final binding = stored.bindings[bindingId];
    if (binding?.lifecycle == WebDavSyncLifecycle.rootVerified) {
      return _bindingStore.setLifecycle(
        bindingId,
        WebDavSyncLifecycle.awaitingAdoption,
      );
    }
    if (binding == null ||
        binding.lifecycle != WebDavSyncLifecycle.awaitingAdoption) {
      throw StateError('WebDAV sync adoption retry state is unavailable');
    }
    return binding;
  }

  Future<WebDavSyncBinding?> _finishInterruptedPromotion(
    String bindingId,
  ) async {
    final stored = await _bindingStore.load();
    final binding = stored.bindings[bindingId];
    if (binding == null || binding.lifecycle != WebDavSyncLifecycle.active) {
      return null;
    }
    if (stored.activeBindingId == bindingId) return binding;
    if (stored.stagedBindingId != bindingId) {
      throw StateError('WebDAV sync Active binding is not staged');
    }
    final state = await _stateRepository.load(binding.namespaceId);
    if (state.adoption != null ||
        !state.hasAuthenticatedMaps ||
        state.ownManifest == null) {
      throw StateError('WebDAV sync interrupted promotion is incomplete');
    }
    await _bindingStore.promoteStaged(bindingId);
    return (await _bindingStore.load()).activeBinding;
  }
}
