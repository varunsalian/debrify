import '../profiles/profile_authorization.dart';
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

/// Completes first connection to an existing folder. Durable graph adoption
/// phases are resumed from the engine-state journal, so a retry after a crash
/// does not restore an already-applied revision again.
final class WebDavSyncExistingRootConnector {
  const WebDavSyncExistingRootConnector({
    required WebDavSyncBindingStore bindingStore,
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncExistingRootDiscoverer discovery,
    required WebDavSyncAdoptionRunner adoption,
    required WebDavSyncSeedPublisher publisher,
    required WebDavSyncCycleRunner engine,
  }) : _bindingStore = bindingStore,
       _stateRepository = stateRepository,
       _discovery = discovery,
       _adoption = adoption,
       _publisher = publisher,
       _engine = engine;

  final WebDavSyncBindingStore _bindingStore;
  final WebDavSyncEngineStateRepository _stateRepository;
  final WebDavSyncExistingRootDiscoverer _discovery;
  final WebDavSyncAdoptionRunner _adoption;
  final WebDavSyncSeedPublisher _publisher;
  final WebDavSyncCycleRunner _engine;

  Future<WebDavSyncBinding> connect({
    required String bindingId,
    required ProfileAuthorizationContext authorization,
    required WebDavSyncAuthorizationRecapture recaptureAuthorization,
    required bool replacementConfirmed,
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
    if (snapshot.requiresGraphUpgrade) {
      throw StateError(
        'Update Debrify before syncing profiles and connections',
      );
    }
    final secrets = await _bindingStore.readSecrets(snapshot.binding);
    state = await _stateRepository.load(snapshot.namespace.id);

    final bootstrapDigest = snapshot.bootstrap.document.semanticDigest;
    final appliedGraphBelongsToActiveProfiles =
        state.appliedGraphDigest != null &&
        state.hasAuthenticatedMaps &&
        state.circleToLocalProfiles!.containsValue(
          currentAuthorization.profileId,
        );
    if (state.appliedGraphDigest == null ||
        !appliedGraphBelongsToActiveProfiles) {
      if (state.hasAuthenticatedMaps) {
        if (state.appliedGraphDigest == null) {
          throw StateError('WebDAV sync adoption state is incomplete');
        }
      } else if (state.appliedGraphDigest != null) {
        throw StateError('WebDAV sync adopted identity maps are missing');
      }
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
        ),
      );
      currentAuthorization = await recaptureAuthorization();
      state = await _stateRepository.load(snapshot.namespace.id);
    } else if (!state.hasAuthenticatedMaps) {
      throw StateError('WebDAV sync adopted identity maps are missing');
    }

    final latestGraph = snapshot.latestGraph;
    if (latestGraph != null &&
        state.appliedGraphDigest != latestGraph.document.semanticDigest) {
      await _adoption.adopt(
        WebDavSyncAdoptionRequest(
          namespaceId: snapshot.namespace.id,
          mode: WebDavSyncAdoptionMode.refresh,
          package: latestGraph.document.package,
          graphSemanticDigest: latestGraph.document.semanticDigest,
          profileMap: latestGraph.manifest.profileMap,
          resourceMap: latestGraph.manifest.resourceMap,
          passphrase: secrets.syncPassphrase,
          authorization: currentAuthorization,
          replacementConfirmed: true,
        ),
      );
      currentAuthorization = await recaptureAuthorization();
      state = await _stateRepository.load(snapshot.namespace.id);
    }
    if (state.adoption != null || !state.hasAuthenticatedMaps) {
      throw StateError('WebDAV sync adoption did not finish safely');
    }

    final published = await _publisher.publish(
      bindingId: bindingId,
      authorization: currentAuthorization,
    );
    state = await _stateRepository.load(snapshot.namespace.id);
    final report = await _engine.runCycle(
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
    );
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
