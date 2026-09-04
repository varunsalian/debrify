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
  const WebDavSyncConnectActive(this.binding);

  final WebDavSyncBinding binding;
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
        beforeSend: beforeSend,
      ),
    );
    _lastInspection = _InspectedLogin(credentials, inspection);
    return inspection;
  }

  Future<WebDavSyncConnectOutcome> connect({
    required WebDavSyncLoginCredentials? credentials,
    required WebDavSyncReplacementConfirmation confirmExistingReplacement,
    bool reconnectActive = false,
  }) async {
    if (credentials == null) return const WebDavSyncConnectCancelled();
    var handedOff = false;
    try {
      final cached = _lastInspection;
      final inspection = cached != null && cached.matches(credentials)
          ? cached.inspection
          : await inspect(credentials);
      final binding = await authorization.runForAdminSession((beforeCommit) {
        if (inspection is WebDavSyncFolderMissing) {
          return setupService.configureNewRoot(
            inspection: inspection,
            syncPassphrase: WebDavSyncCodec.generateSyncSecret(),
            beforeCommit: beforeCommit,
          );
        }
        if (inspection is WebDavSyncFolderExisting) {
          return setupService.configureExistingRoot(
            inspection: inspection,
            reconnectActive: reconnectActive,
            beforeCommit: beforeCommit,
          );
        }
        throw StateError('Unexpected WebDAV sync inspection result');
      });
      handedOff = true;
      return await _activate(
        binding,
        confirmExistingReplacement: confirmExistingReplacement,
      );
    } catch (error) {
      return handedOff
          ? WebDavSyncConnectPostHandoffFailure(error)
          : WebDavSyncConnectPreHandoffFailure(error);
    } finally {
      _lastInspection = null;
    }
  }

  Future<WebDavSyncConnectOutcome> _activate(
    WebDavSyncBinding staged, {
    required WebDavSyncReplacementConfirmation confirmExistingReplacement,
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
      final initialized = await controller.initializeNew(binding.id);
      if (initialized is WebDavSyncInitialized) {
        return WebDavSyncConnectActive(initialized.binding);
      }
      if (initialized is WebDavSyncConcurrentRoot) {
        binding = initialized.binding;
      } else {
        throw StateError('Unexpected WebDAV sync activation result');
      }
    }

    await controller.inspectExisting(binding.id);
    if (!await confirmExistingReplacement()) {
      await setupService.store.discardStaged();
      return const WebDavSyncConnectCancelled();
    }
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
  const _InspectedLogin(this.credentials, this.inspection);

  final WebDavSyncLoginCredentials credentials;
  final WebDavSyncFolderInspection inspection;

  bool matches(WebDavSyncLoginCredentials other) =>
      credentials.endpoint == other.endpoint &&
      credentials.username == other.username &&
      credentials.password == other.password &&
      credentials.serverName == other.serverName;
}
