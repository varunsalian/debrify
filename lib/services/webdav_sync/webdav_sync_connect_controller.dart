import '../../models/webdav_item.dart';
import 'webdav_sync_activation.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_runtime.dart';
import 'webdav_sync_setup_authorization.dart';
import 'webdav_sync_setup_service.dart';

final class WebDavSyncLoginCredentials {
  const WebDavSyncLoginCredentials({
    required this.endpoint,
    required this.username,
    required this.password,
    required this.serverName,
  });

  final Uri endpoint;
  final String username;
  final String password;
  final String serverName;

  WebDavConfig toConfig() => WebDavConfig(
    id: 'webdav-sync-login',
    name: serverName,
    baseUrl: endpoint.toString(),
    username: username,
    password: password,
  );
}

sealed class WebDavSyncConnectOutcome {
  const WebDavSyncConnectOutcome();
}

final class WebDavSyncConnectCancelled extends WebDavSyncConnectOutcome {
  const WebDavSyncConnectCancelled();
}

final class WebDavSyncConnectActive extends WebDavSyncConnectOutcome {
  const WebDavSyncConnectActive(this.binding, {this.createdNewCircle = false});

  final WebDavSyncBinding binding;
  final bool createdNewCircle;
}

final class WebDavSyncConnectAdoptedFinishing extends WebDavSyncConnectOutcome {
  const WebDavSyncConnectAdoptedFinishing(this.binding);

  final WebDavSyncBinding binding;
}

final class WebDavSyncConnectPreHandoffFailure
    extends WebDavSyncConnectOutcome {
  const WebDavSyncConnectPreHandoffFailure(this.error);

  final Object error;
}

final class WebDavSyncConnectPostHandoffFailure
    extends WebDavSyncConnectOutcome {
  const WebDavSyncConnectPostHandoffFailure(this.error);

  final Object error;
}

typedef WebDavSyncReplacementConfirmation = Future<bool> Function();

WebDavSyncConnectController createWebDavSyncConnectController({
  WebDavSyncSetupService? setupService,
  WebDavSyncSetupAuthorization? authorization,
  WebDavSyncActivationController? activation,
}) {
  final usesProductionSetup = setupService == null;
  return WebDavSyncConnectController(
    setupService: setupService ?? WebDavSyncSetupService(),
    authorization: authorization ?? const ProfileWebDavSyncSetupAuthorization(),
    activation:
        activation ?? (usesProductionSetup ? WebDavSyncRuntime.instance : null),
  );
}

/// Shared login-first orchestration used by Settings and future onboarding.
///
/// The login screen calls [inspect] so authentication and keyfile failures can
/// remain inline. [connect] consumes that authenticated inspection and owns
/// every durable step through activation. Runtime pausing and dialog rendering
/// remain responsibilities of the caller.
final class WebDavSyncConnectController {
  WebDavSyncConnectController({
    required this.setupService,
    required this.authorization,
    required this.activation,
  });

  static const String folderPath = 'Debrify';

  final WebDavSyncSetupService setupService;
  final WebDavSyncSetupAuthorization authorization;
  final WebDavSyncActivationController? activation;

  _InspectedLogin? _lastInspection;

  Future<WebDavSyncFolderInspection> inspect(
    WebDavSyncLoginCredentials credentials,
  ) async {
    final config = credentials.toConfig();
    final inspection = await authorization.runForAdminSession(
      (beforeSend) => setupService.inspectFolder(
        config: config,
        folderPath: folderPath,
        context: WebDavSyncFolderInspectionContext.setup,
        beforeSend: beforeSend,
      ),
    );
    _lastInspection = _InspectedLogin(credentials, inspection);
    return inspection;
  }

  Future<WebDavSyncFolderInspection> inspectReconnect(
    WebDavSyncLoginCredentials credentials,
  ) async {
    final snapshot = await setupService.store.load();
    final binding = snapshot.activeBinding;
    if (binding == null) {
      throw StateError('WebDAV sync active binding is unavailable');
    }
    final config = WebDavConfig(
      id: 'webdav-sync-reconnect',
      name: binding.location.serverName,
      baseUrl: binding.location.endpoint.toString(),
      username: credentials.username,
      password: credentials.password,
    );
    final inspection = await authorization.runForActiveBinding(
      (beforeSend) => setupService.inspectFolder(
        config: config,
        folderPath: binding.location.folderPath,
        context: WebDavSyncFolderInspectionContext.repair,
        repairBindingId: binding.id,
        beforeSend: beforeSend,
      ),
    );
    _lastInspection = _InspectedLogin(
      credentials,
      inspection,
      repairBindingId: binding.id,
    );
    return inspection;
  }

  Future<WebDavSyncConnectOutcome> connect({
    required WebDavSyncLoginCredentials? credentials,
    required WebDavSyncReplacementConfirmation confirmExistingReplacement,
    bool reconnectActive = false,
    bool completeOnboarding = false,
    void Function(String)? onProgress,
  }) async {
    if (credentials == null) {
      _lastInspection = null;
      return const WebDavSyncConnectCancelled();
    }
    onProgress?.call('Verifying WebDAV account…');
    String? stagedByThisAttempt;
    try {
      final reconnectBindingId = reconnectActive
          ? (await setupService.store.load()).activeBindingId
          : null;
      if (reconnectActive && reconnectBindingId == null) {
        throw StateError('WebDAV sync active binding is unavailable');
      }
      final cached = _lastInspection;
      final inspection =
          cached != null &&
              cached.matches(credentials) &&
              cached.repairBindingId == reconnectBindingId
          ? cached.inspection
          : reconnectActive
          ? await inspectReconnect(credentials)
          : await inspect(credentials);
      onProgress?.call('Preparing sync setup…');
      final binding = await authorization.runForAdminSession((beforeCommit) {
        if (inspection is WebDavSyncFolderMissing) {
          if (reconnectActive) {
            throw const WebDavSyncRootMissingException();
          }
          return setupService.configureNewRoot(
            inspection: inspection,
            syncPassphrase: WebDavSyncCodec.generateSyncSecret(),
            completeOnboarding: completeOnboarding,
            beforeCommit: beforeCommit,
            afterStaged: (binding) => stagedByThisAttempt = binding.id,
          );
        }
        if (inspection is WebDavSyncFolderExisting) {
          return setupService.configureExistingRoot(
            inspection: inspection,
            reconnectActive: reconnectActive,
            completeOnboarding: completeOnboarding,
            beforeCommit: beforeCommit,
            afterStaged: (binding) => stagedByThisAttempt = binding.id,
          );
        }
        throw StateError('Unexpected WebDAV sync inspection result');
      });
      stagedByThisAttempt ??= binding.id;
      return await _activate(
        binding,
        confirmExistingReplacement: confirmExistingReplacement,
        onProgress: onProgress,
      );
    } catch (error) {
      if (error is! WebDavSyncPostHandoffException &&
          completeOnboarding &&
          stagedByThisAttempt != null) {
        try {
          await setupService.store.discardStagedMatching(stagedByThisAttempt!);
        } catch (_) {
          // Preserve the actionable setup failure. A later login replaces the
          // same candidate, and startup never treats it as active authority.
        }
      }
      return error is WebDavSyncPostHandoffException
          ? WebDavSyncConnectPostHandoffFailure(error.error)
          : WebDavSyncConnectPreHandoffFailure(error);
    } finally {
      _lastInspection = null;
    }
  }

  Future<WebDavSyncConnectOutcome> _activate(
    WebDavSyncBinding staged, {
    required WebDavSyncReplacementConfirmation confirmExistingReplacement,
    void Function(String)? onProgress,
  }) async {
    var binding = staged;
    final controller = activation;
    if (binding.lifecycle == WebDavSyncLifecycle.active) {
      return WebDavSyncConnectActive(binding);
    }
    if (controller == null) {
      return WebDavSyncConnectAdoptedFinishing(binding);
    }
    if (binding.lifecycle == WebDavSyncLifecycle.awaitingSeedCommit) {
      onProgress?.call('Uploading initial sync data…');
      final initialized = await controller.initializeNew(binding.id);
      if (initialized is WebDavSyncInitialized) {
        return WebDavSyncConnectActive(
          initialized.binding,
          createdNewCircle: true,
        );
      }
      if (initialized is WebDavSyncConcurrentRoot) {
        binding = initialized.binding;
      } else {
        throw StateError('Unexpected WebDAV sync activation result');
      }
    }

    onProgress?.call('Checking existing sync data…');
    await controller.inspectExisting(binding.id);
    onProgress?.call('Waiting for your confirmation…');
    if (!await confirmExistingReplacement()) {
      await setupService.store.discardStagedMatching(binding.id);
      return const WebDavSyncConnectCancelled();
    }
    onProgress?.call('Restoring and finishing sync setup…');
    binding = await controller.connectExisting(
      binding.id,
      replacementConfirmed: true,
    );
    return binding.lifecycle == WebDavSyncLifecycle.active
        ? WebDavSyncConnectActive(binding)
        : WebDavSyncConnectAdoptedFinishing(binding);
  }
}

final class _InspectedLogin {
  const _InspectedLogin(
    this.credentials,
    this.inspection, {
    this.repairBindingId,
  });

  final WebDavSyncLoginCredentials credentials;
  final WebDavSyncFolderInspection inspection;
  final String? repairBindingId;

  bool matches(WebDavSyncLoginCredentials other) =>
      credentials.endpoint == other.endpoint &&
      credentials.username == other.username &&
      credentials.password == other.password &&
      credentials.serverName == other.serverName;
}
