import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_activation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_discovery.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_manifest_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

final class ConnectorMemoryStateRepository
    implements WebDavSyncEngineStateRepository {
  WebDavSyncEngineState state = const WebDavSyncEngineState();

  @override
  Future<WebDavSyncEngineState> load(String namespaceId) async => state;

  @override
  Future<WebDavSyncEngineState> update(
    String namespaceId,
    WebDavSyncEngineState Function(WebDavSyncEngineState current) update,
  ) async => state = update(state);
}

final class ConnectorFakeDiscovery implements WebDavSyncExistingRootDiscoverer {
  const ConnectorFakeDiscovery(this.snapshot, this.events);

  final WebDavSyncExistingRootSnapshot snapshot;
  final List<String> events;

  @override
  Future<WebDavSyncExistingRootSnapshot> discover({
    required String bindingId,
  }) async {
    events.add('discover');
    return snapshot;
  }
}

final class ConnectorFakeAdoption implements WebDavSyncAdoptionRunner {
  ConnectorFakeAdoption(this.states, this.events);

  final ConnectorMemoryStateRepository states;
  final List<String> events;
  int restoreCalls = 0;
  int copyForwardCalls = 0;
  int mapMintCalls = 0;
  bool? completeOnboarding;

  @override
  Future<WebDavSyncAdoptionRecord> adopt(
    WebDavSyncAdoptionRequest request,
  ) async {
    events.add('adopt:${request.mode.name}');
    completeOnboarding = request.completeOnboarding;
    restoreCalls++;
    copyForwardCalls++;
    mapMintCalls++;
    await states.update(
      request.namespaceId,
      (current) => current.copyWith(
        circleToLocalProfiles: const <String, String>{
          'profile-circle': 'local-profile',
        },
        circleToLocalResources: const <String, String>{},
      ),
    );
    return WebDavSyncAdoptionRecord(
      adoptionId: 'adoption-test',
      mode: request.mode,
      phase: WebDavSyncAdoptionPhase.complete,
      graphSemanticDigest: request.graphSemanticDigest,
      preRestoreProfileIds: const <String>{'local-before'},
      backupPath: '/backup',
      backupSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      backupVerified: true,
    );
  }

  @override
  Future<WebDavSyncAdoptionRecord?> recover(String namespaceId) async {
    final record = states.state.adoption;
    if (record == null) return null;
    events.add('recover');
    await states.update(
      namespaceId,
      (current) => current.copyWith(clearAdoption: true),
    );
    return record;
  }

  @override
  Future<Set<String>> retryPendingPrunes(String namespaceId) async =>
      const <String>{};
}

final class ConnectorFakePublisher implements WebDavSyncSeedPublisher {
  ConnectorFakePublisher(
    this.states,
    this.snapshot,
    this.events, {
    this.conflictsRemaining = 0,
  });

  final ConnectorMemoryStateRepository states;
  final WebDavSyncExistingRootSnapshot snapshot;
  final List<String> events;
  int conflictsRemaining;
  int publishCalls = 0;

  @override
  Future<WebDavSyncPublishedSeed> publish({
    required String bindingId,
    required ProfileAuthorizationContext authorization,
  }) async {
    events.add('publish');
    publishCalls++;
    if (conflictsRemaining > 0) {
      conflictsRemaining--;
      throw const ProfilePreferenceMutationConflict();
    }
    final manifest = WebDavSyncManifest(
      circleId: snapshot.root.document.circleId,
      deviceId: snapshot.namespace.deviceId,
      updatedAtMs: 2,
      clockOffsetMs: 0,
      graphSchemaClaim: 1,
      profileMap: const <String, String>{'profile-backup': 'profile-circle'},
      resourceMap: const <String, String>{},
      sections: const <WebDavSyncSectionReference>[],
    );
    final state = await states.load(snapshot.namespace.id);
    await states.update(
      snapshot.namespace.id,
      (current) => current.copyWith(ownManifest: manifest),
    );
    return WebDavSyncPublishedSeed(
      material: WebDavSyncSeedMaterial(
        identityMaps: WebDavSyncIdentityMaps(
          circleToLocalProfiles: state.circleToLocalProfiles!,
          circleToLocalResources: state.circleToLocalResources!,
        ),
        profileMap: manifest.profileMap,
        resourceMap: manifest.resourceMap,
        sections: const <WebDavSyncSeedSection>[],
        profileStates: const <String, WebDavSyncProfileEngineState>{},
        bootstrapDatabaseDigest:
            '5555555555555555555555555555555555555555555555555555555555555555',
        beforeRootCommit: _done,
      ),
      manifest: manifest,
      serverNowMs: 2,
    );
  }

  static Future<void> _done() async {}
}

final class ConnectorPinCheckingEngine implements WebDavSyncCycleRunner {
  final WebDavSyncBindingStore bindingStore;
  ConnectorPinCheckingEngine(
    this.bindingStore,
    this.events, {
    this.conflictsRemaining = 0,
  });

  final List<String> events;
  int conflictsRemaining;
  int runCalls = 0;

  @override
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
    WebDavSyncTrigger? trigger,
  }) async {
    expect(allowPreActivation, isTrue);
    expect(context?.active, isFalse);
    events.add('merge');
    runCalls++;
    final stored = await bindingStore.load();
    final binding = stored.bindingForCycle(
      namespaceId: context!.namespaceId!,
      preActivation: allowPreActivation && !context.active,
    );
    final namespace = binding == null ? null : stored.namespaceFor(binding);
    if (binding == null ||
        namespace == null ||
        binding.circleId != context.root?.document.circleId ||
        namespace.deviceId != context.deviceId ||
        !namespace.matchesAuthorityPin(
          context.markerPin,
          context.authorityContentHash,
        )) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    if (conflictsRemaining > 0) {
      conflictsRemaining--;
      throw const ProfilePreferenceMutationConflict();
    }
    return const WebDavSyncCycleReport(
      disposition: WebDavSyncCycleDisposition.completed,
    );
  }
}
