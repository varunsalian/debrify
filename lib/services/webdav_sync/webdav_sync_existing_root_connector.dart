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
    if (!replacementConfirmed) {
      throw StateError(
        'Replacing local profiles requires explicit confirmation',
      );
    }
    final resumed = await _finishInterruptedPromotion(bindingId);
    if (resumed != null) return resumed;

    final beforeDiscovery = await _bindingStore.load();
    final pendingBinding =
        beforeDiscovery.bindings[bindingId] ??
        (throw StateError('WebDAV sync binding is unavailable'));
    var currentAuthorization = authorization;
    var state = await _stateRepository.load(pendingBinding.namespaceId);
    if (state.adoption != null) {
      await _adoption.recover(pendingBinding.namespaceId);
      currentAuthorization = await recaptureAuthorization();
    }

    final snapshot = await _discovery.discover(bindingId: bindingId);
    final secrets = await _bindingStore.readSecrets(snapshot.binding);
    state = await _stateRepository.load(snapshot.namespace.id);

    final bootstrapDigest = snapshot.bootstrap.document.semanticDigest;
    final adoptedBootstrapBelongsToActiveProfiles =
        state.hasAuthenticatedMaps &&
        state.circleToLocalProfiles!.containsValue(
          currentAuthorization.profileId,
        );
    if (!adoptedBootstrapBelongsToActiveProfiles) {
      await _adoption.adopt(
        WebDavSyncAdoptionRequest(
          namespaceId: snapshot.namespace.id,
          mode: WebDavSyncAdoptionMode.firstJoin,
          package: snapshot.bootstrap.document.package,
          graphSemanticDigest: bootstrapDigest,
          profileMap: snapshot.bootstrap.manifest.profileMap,
          resourceMap: snapshot.bootstrap.manifest.resourceMap,
          passphrase: secrets.syncPassphrase,
          authorization: currentAuthorization,
          replacementConfirmed: true,
          completeOnboarding: completeOnboarding,
        ),
      );
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
    return active;
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
