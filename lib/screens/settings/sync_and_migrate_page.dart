import '../../services/webdav_sync/webdav_log_upload.dart';
import '../../services/webdav_sync/webdav_sync_binding_store.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/webdav_item.dart';
import '../../services/analytics_service.dart';
import '../../services/webdav_sync/webdav_sync_clock.dart';
import '../../services/webdav_sync/webdav_sync_engine.dart';
import '../../services/webdav_sync/webdav_sync_feature.dart';
import '../../services/webdav_sync/webdav_sync_connect_controller.dart';
import '../../services/webdav_sync/webdav_sync_models.dart';
import '../../services/webdav_sync/webdav_sync_runtime.dart';
import '../../services/webdav_sync/webdav_sync_scheduler.dart';
import '../../services/webdav_sync/webdav_sync_setup_authorization.dart';
import '../../services/webdav_sync/webdav_sync_setup_service.dart';
import '../../widgets/tv_text_field.dart';
import '../../widgets/webdav_sync/webdav_foreground_sync.dart';
import '../webdav_sync/webdav_sync_login_screen.dart';
import 'widgets/settings_widgets.dart';

class SyncAndMigratePage extends StatefulWidget {
  const SyncAndMigratePage({
    super.key,
    this.syncService,
    this.syncAuthorization,
    this.syncActivation,
    this.syncFeatureEnabled,
    this.launchSyncLogin,
  });

  final WebDavSyncSetupService? syncService;
  final WebDavSyncSetupAuthorization? syncAuthorization;
  final WebDavSyncActivationController? syncActivation;
  final bool? syncFeatureEnabled;
  final Future<WebDavSyncLoginCredentials?> Function(
    BuildContext context,
    WebDavSyncConnectController controller,
  )?
  launchSyncLogin;

  @override
  State<SyncAndMigratePage> createState() => _SyncAndMigratePageState();
}

class _SyncAndMigratePageState extends State<SyncAndMigratePage>
    with WidgetsBindingObserver {
  late final WebDavSyncSetupService _syncService;
  late final WebDavSyncSetupAuthorization _syncAuthorization;
  late final WebDavSyncConnectController _syncConnectController;
  WebDavSyncActivationController? _syncActivation;
  WebDavSyncBinding? _syncBinding;
  WebDavSyncRuntimeStatus? _runtimeStatus;
  String? _syncStateMessage;
  bool _syncBusy = false;
  bool _logUploadEnabled = false;
  bool _logSettingsBusy = false;
  bool _logUploading = false;
  String? _logBindingId;
  int _logSettingRevision = 0;
  bool _logoutPending = false;
  Timer? _statusTimer;
  Future<void>? _statusLoading;
  bool _statusReadFailed = false;
  bool _tvSyncLaunching = false;
  _DebrifyTvSyncOperation? _tvSyncOperation;
  WebDavSyncTvManualAvailability _tvManualAvailability =
      WebDavSyncTvManualAvailability.inactive;

  bool get _syncFeatureEnabled =>
      widget.syncFeatureEnabled ?? WebDavSyncFeature.enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncService = widget.syncService ?? WebDavSyncSetupService();
    _syncAuthorization =
        widget.syncAuthorization ?? const ProfileWebDavSyncSetupAuthorization();
    // A custom setup service in widget tests intentionally exercises the M3
    // read-only boundary. Production owns the integrated M5 activation flow.
    _syncActivation =
        widget.syncActivation ??
        (widget.syncService == null ? WebDavSyncRuntime.instance : null);
    _syncConnectController = createWebDavSyncConnectController(
      setupService: _syncService,
      authorization: _syncAuthorization,
      activation: _syncActivation,
    );
    AnalyticsService.screenView('sync_and_migrate');
    if (_syncFeatureEnabled) {
      _loadSyncState();
      unawaited(_loadLogUploadSetting());
      // Also observe background completion and expiring platform gates while
      // the page remains open. Coalesce reads so a slow cycle never queues
      // an unbounded number of status operations.
      _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!_syncBusy) unawaited(_loadActiveSyncState());
      });
    }
  }

  Future<void> _loadLogUploadSetting() async {
    final revision = ++_logSettingRevision;
    final bindingId = _syncBinding?.id;
    try {
      final enabled = await WebDavLogUpload.instance.isEnabled();
      if (mounted &&
          revision == _logSettingRevision &&
          bindingId == _syncBinding?.id) {
        setState(() {
          _logUploadEnabled = enabled;
          _logBindingId = bindingId;
        });
      }
    } catch (_) {}
  }

  Future<void> _setLogUpload(bool enabled) async {
    if (_logSettingsBusy || _syncBusy || _logoutPending) return;
    setState(() => _logSettingsBusy = true);
    try {
      await _syncAuthorization.requireAdmin();
      await WebDavLogUpload.instance.setEnabled(enabled);
      await _loadLogUploadSetting();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _logSettingsBusy = false);
    }
  }

  Future<void> _uploadLogsNow() async {
    if (_logUploading) return;
    setState(() => _logUploading = true);
    try {
      await _syncAuthorization.requireAdmin();
      final result = await WebDavLogUpload.instance.upload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == WebDavLogUploadResult.uploaded
                ? 'Diagnostic logs uploaded.'
                : result == WebDavLogUploadResult.busy
                ? 'A log upload is already running.'
                : 'Logs could not be uploaded. They remain on this device.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _logUploading = false);
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _tvSyncOperation?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_syncFeatureEnabled && state == AppLifecycleState.resumed) {
      unawaited(_reloadSyncAfterForeground());
    }
  }

  Future<void> _reloadSyncAfterForeground() async {
    // Let the runtime's foreground callback enqueue any first-join promotion
    // before status enters the same serialized runtime operation path.
    await Future<void>.delayed(Duration.zero);
    if (mounted) await _loadActiveSyncState();
  }

  Future<void> _loadSyncState() async {
    try {
      final snapshot = await _syncService.store.load();
      if (!mounted) return;
      setState(() {
        _syncBinding = snapshot.stagedBinding ?? snapshot.activeBinding;
        _logoutPending = WebDavSyncBindingStore.logoutPending(snapshot);
      });
      unawaited(_loadActiveSyncState());
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  WebDavSyncManagementController? get _management =>
      _syncActivation is WebDavSyncManagementController
      ? _syncActivation as WebDavSyncManagementController
      : null;

  WebDavSyncTvManualController? get _tvManualController =>
      _syncActivation is WebDavSyncTvManualController
      ? _syncActivation as WebDavSyncTvManualController
      : null;

  Future<void> _loadActiveSyncState() {
    final pending = _statusLoading;
    if (pending != null) return pending;
    late final Future<void> started;
    started = _readActiveSyncState().whenComplete(() {
      if (identical(_statusLoading, started)) _statusLoading = null;
    });
    _statusLoading = started;
    return started;
  }

  Future<void> _readActiveSyncState() async {
    final management = _management;
    if (management == null) return;
    try {
      final status = await management.status();
      final tvAvailability =
          await _tvManualController?.tvManualAvailability() ??
          WebDavSyncTvManualAvailability.inactive;
      final snapshot = await _syncService.store.load();
      if (status.localStateMissing) {
        if (!mounted) return;
        setState(() {
          _syncBinding = snapshot.stagedBinding ?? snapshot.activeBinding;
          _logoutPending = WebDavSyncBindingStore.logoutPending(snapshot);
          _runtimeStatus = status;
          _statusReadFailed = false;
          if (_logBindingId != _syncBinding?.id) {
            unawaited(_loadLogUploadSetting());
          }
          _tvManualAvailability = tvAvailability;
          _syncStateMessage =
              'Local sync state was cleared. Re-enter your WebDAV password '
              'to reconnect safely.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _syncBinding = snapshot.stagedBinding ?? snapshot.activeBinding;
        _logoutPending = WebDavSyncBindingStore.logoutPending(snapshot);
        _runtimeStatus = status;
        _statusReadFailed = false;
        if (_logBindingId != _syncBinding?.id) {
          unawaited(_loadLogUploadSetting());
        }
        _tvManualAvailability = tvAvailability;
        _syncStateMessage = status.adminPruneBlocked
            ? 'Profile cleanup is pending for ${status.pruneBlockingProfiles.join(', ')}; activity sync continues'
            : status.statusHint;
      });
    } catch (_) {
      // Active sync remains usable offline; manual Sync now surfaces errors.
      if (mounted) setState(() => _statusReadFailed = true);
    }
  }

  Future<void> _configureSync() async {
    if (_syncBusy) return;
    if (_logoutPending && !await _forgetConnection()) return;
    if (!mounted) return;
    setState(() => _syncBusy = true);
    final reconfiguration =
        _syncActivation is WebDavSyncReconfigurationController
        ? _syncActivation as WebDavSyncReconfigurationController
        : null;
    var didPause = false;
    try {
      await _syncAuthorization.requireAdmin();
      if (reconfiguration != null) {
        reconfiguration.pauseForReconfiguration();
        didPause = true;
      }
      if (!mounted) return;
      final reconnectBinding = _syncBinding?.requiresStateReconnect == true
          ? _syncBinding
          : null;
      final reconnectUsername = reconnectBinding == null
          ? null
          : (await _syncService.store.readSecrets(reconnectBinding)).username;
      if (!mounted) return;
      final credentials = widget.launchSyncLogin != null
          ? await widget.launchSyncLogin!(context, _syncConnectController)
          : await Navigator.of(context).push<WebDavSyncLoginCredentials>(
              MaterialPageRoute(
                builder: (_) => WebDavSyncLoginScreen(
                  connectController: _syncConnectController,
                  repairBinding: reconnectBinding,
                  initialUsername: reconnectUsername,
                ),
              ),
            );
      if (!mounted) return;
      if (credentials == null) return;
      final outcome = await runWebDavForegroundSync(
        context,
        stage: 'Preparing WebDAV sync…',
        progressLimit: null,
        operation: (updateStage) => _syncConnectController.connect(
          credentials: credentials,
          reconnectActive: reconnectBinding != null,
          confirmExistingReplacement: _confirmExistingReplacement,
          onProgress: updateStage,
        ),
      );
      if (!mounted) return;
      final binding = switch (outcome) {
        WebDavSyncConnectCancelled() => null,
        WebDavSyncConnectActive active => active.binding,
        WebDavSyncConnectAdoptedFinishing finishing => finishing.binding,
        WebDavSyncConnectPreHandoffFailure failure => throw failure.error,
        WebDavSyncConnectPostHandoffFailure failure => throw failure.error,
      };
      if (binding == null) return;
      if (!mounted) return;
      setState(() => _syncBinding = binding);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_completionMessage(binding.lifecycle))),
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      try {
        if (didPause) await reconfiguration!.resumeAfterReconfiguration();
        if (mounted) await _loadActiveSyncState();
      } catch (error) {
        if (mounted) _showError(error);
      } finally {
        if (mounted) setState(() => _syncBusy = false);
      }
    }
  }

  Future<bool> _confirmExistingReplacement() async {
    return await showSettingsDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Use sync data from this account?'),
            content: const Text(
              'Existing profiles and connections on this device will be '
              'replaced. Create a manual backup first if you want to keep '
              'a copy of your current data. IPTV channel and '
              'guide caches rebuild; Debrify TV channels are not included.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Use sync data'),
              ),
            ],
          ),
        ) ??
        false;
  }

  WebDavSyncLogoutController? get _logoutController =>
      _syncActivation is WebDavSyncLogoutController
      ? _syncActivation as WebDavSyncLogoutController
      : null;

  Future<bool> _forgetConnection() async {
    final controller = _logoutController;
    if (_syncBusy || controller == null) return false;
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forget WebDAV connection?'),
        content: const Text(
          'Remove the saved connection from this device without contacting WebDAV. '
          'Your profiles and data stay here. You can then connect again.\n\n'
          'The old account may still list this device as connected. '
          'Data on WebDAV and your other devices will not be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Forget connection'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    setState(() => _syncBusy = true);
    try {
      await controller.logout(localOnly: true);
      if (!mounted) return false;
      await _loadSyncState();
      if (!mounted) return false;
      setState(() {
        _runtimeStatus = null;
        _syncStateMessage = null;
      });
      return true;
    } catch (error) {
      if (mounted) _showError(error);
      return false;
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _logout() async {
    final controller = _logoutController;
    if (_syncBusy || controller == null) return;
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Log out of WebDAV sync?'),
        content: const Text(
          'This device will stop syncing and leave the connected devices list. '
          'Its saved sync login will be removed.\n\n'
          'Your profiles and data stay on this device. Already synced data stays '
          'on WebDAV so you and your other devices can use it later. Changes '
          'that have not synced stay only on this device.\n\n'
          'If WebDAV is unavailable, you can forget the connection on this device after trying logout.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _syncBusy = true);
    try {
      await runWebDavForegroundSync(
        context,
        title: 'Logging out of WebDAV',
        stage: 'Unregistering this device and removing its saved login…',
        operation: (_) => controller.logout(),
      );
      if (!mounted) return;
      await _loadSyncState();
      if (!mounted) return;
      setState(() {
        _runtimeStatus = null;
        _syncStateMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out. Your data is still on this device.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await _loadSyncState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _logoutPending
                ? 'Logout could not be confirmed. Retry or choose Forget connection to disconnect on this device.'
                : _userFacingSyncError(error),
          ),
          action: SnackBarAction(label: 'Retry', onPressed: _logout),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _syncNow() async {
    final activation = _syncActivation;
    if (_syncBusy || activation == null) return;
    setState(() => _syncBusy = true);
    try {
      final report = await runWebDavForegroundSync(
        context,
        stage: 'Checking and exchanging sync data…',
        operation: (_) => activation.syncNow(),
      );
      if (!mounted) return;
      final message = switch (report.disposition) {
        WebDavSyncCycleDisposition.completed =>
          report.localChangeFollowUp ||
                  !report.localPublicationConfirmed ||
                  report.localProfilesSuppressed
              ? 'Sync still has pending changes. Keep Debrify open and retry.'
              : report.statusHint ?? 'WebDAV Sync is up to date.',
        WebDavSyncCycleDisposition.clockPaused =>
          'Sync is paused because the device or server clock needs attention.',
        WebDavSyncCycleDisposition.adoptionBlocked =>
          'Sync is waiting for profile replacement to finish.',
        WebDavSyncCycleDisposition.capacityBlocked =>
          'Sync is over its saved-activity limit. Clear older history or '
              'lists, then try again.',
        WebDavSyncCycleDisposition.seedRepairRequired =>
          'Sync data for this device is being rebuilt.',
        WebDavSyncCycleDisposition.inactive => 'Sync is currently paused.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action:
              report.disposition != WebDavSyncCycleDisposition.completed ||
                  !report.localPublicationConfirmed ||
                  report.localChangeFollowUp ||
                  report.localProfilesSuppressed
              ? SnackBarAction(label: 'Retry', onPressed: _syncNow)
              : null,
        ),
      );
      await _loadSyncState();
    } catch (error) {
      if (mounted) _showError(error, onRetry: _syncNow);
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _syncDebrifyTv() async {
    final controller = _tvManualController;
    if (_syncBusy || _tvSyncLaunching || controller == null) return;
    _tvSyncLaunching = true;
    _DebrifyTvSyncOperation? operation;
    try {
      final availability = await controller.tvManualAvailability();
      if (!mounted) return;
      setState(() => _tvManualAvailability = availability);
      if (availability != WebDavSyncTvManualAvailability.available) return;
      setState(() => _syncBusy = true);
      operation = _DebrifyTvSyncOperation(controller);
      _tvSyncOperation = operation;
      var report = await showSettingsDialog<WebDavSyncTvManualReport>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DebrifyTvSyncProgressDialog(operation: operation!),
      );
      report ??= await operation.terminal;
      if (!mounted) return;
      final message = switch (report.disposition) {
        WebDavSyncTvManualDisposition.completed =>
          'Debrify TV sync is up to date.',
        WebDavSyncTvManualDisposition.cancelled =>
          'Debrify TV sync stopped safely.',
        WebDavSyncTvManualDisposition.inactive =>
          'Enable WebDAV Sync before syncing Debrify TV.',
        WebDavSyncTvManualDisposition.firstJoinPending =>
          'Finish the first sync before syncing Debrify TV.',
        WebDavSyncTvManualDisposition.cycleRunning =>
          'Another sync is running. Try Debrify TV again when it finishes.',
        WebDavSyncTvManualDisposition.televisionPlayback =>
          'Stop TV playback, then run Debrify TV sync again.',
        WebDavSyncTvManualDisposition.tvOsLowMemory =>
          'Apple TV is low on memory. Wait a few minutes, then try again.',
        WebDavSyncTvManualDisposition.clockPaused =>
          'Debrify TV sync is paused because the device or server clock needs attention.',
        WebDavSyncTvManualDisposition.conflict =>
          'Debrify TV changed during sync. Run it again to finish.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (operation != null) {
        try {
          await operation.cancelAndWait();
        } catch (_) {
          // The operation error was already surfaced by the owning handler.
        }
      }
      if (identical(_tvSyncOperation, operation)) _tvSyncOperation = null;
      _tvSyncLaunching = false;
      if (mounted && _syncBusy) setState(() => _syncBusy = false);
    }
    if (mounted) await _loadActiveSyncState();
  }

  Future<void> _repairCredentials() async {
    if (_syncBusy) return;
    setState(() => _syncBusy = true);
    final reconfiguration =
        _syncActivation is WebDavSyncReconfigurationController
        ? _syncActivation as WebDavSyncReconfigurationController
        : null;
    var reloadAfterResume = false;
    var didPause = false;
    try {
      await _syncAuthorization.requireAdmin();
      var binding = _syncBinding;
      if (_logoutPending) {
        final snapshot = await _syncService.store.load();
        if (!mounted) return;
        final bindings = snapshot.bindings.values
            .where(
              (item) =>
                  item.circleId != null &&
                  snapshot.namespaceFor(item)?.markerBytes != null,
            )
            .toList();
        binding = await showSettingsDialog<WebDavSyncBinding>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('Choose account to repair'),
            children: [
              for (final item in bindings)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(item),
                  child: Text(
                    '${item.location.serverName}\n${item.location.endpoint.host} · ${item.location.folderPath}'
                    '${snapshot.namespaceFor(item)?.values['logoutNeedsAttentionBindingId'] == item.id ? '\nLogout stopped at this account' : ''}',
                  ),
                ),
            ],
          ),
        );
      }
      final repairBinding = binding;
      if (repairBinding == null || repairBinding.circleId == null) return;

      final currentSecrets = await _syncService.store.readSecrets(
        repairBinding,
      );
      if (!mounted) return;
      final input = await showSettingsDialog<_SyncCredentialInput>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _SyncCredentialDialog(initialUsername: currentSecrets.username),
      );
      if (input == null || !mounted) return;
      if (reconfiguration != null) {
        reconfiguration.pauseForReconfiguration();
        didPause = true;
      }
      final config = WebDavConfig(
        id: 'webdav-sync-credentials',
        name: repairBinding.location.serverName,
        baseUrl: repairBinding.location.endpoint.toString(),
        username: input.username,
        password: input.password,
      );
      final repaired = await _syncAuthorization.runForActiveBinding((
        beforeSend,
      ) async {
        final inspection = await _syncService.inspectFolder(
          config: config,
          folderPath: repairBinding.location.folderPath,
          context: WebDavSyncFolderInspectionContext.repair,
          repairBindingId: repairBinding.id,
          beforeSend: beforeSend,
        );
        if (inspection is! WebDavSyncFolderExisting) {
          throw const WebDavSyncRootMissingException();
        }
        return _syncService.configureExistingRoot(
          inspection: inspection,
          beforeCommit: beforeSend,
        );
      });
      if (!mounted) return;
      setState(() => _syncBinding = repaired);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV Sync credentials verified.')),
      );
      reloadAfterResume = true;
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      try {
        if (didPause) await reconfiguration!.resumeAfterReconfiguration();
      } catch (error) {
        if (mounted) _showError(error);
      } finally {
        if (mounted) setState(() => _syncBusy = false);
      }
    }
    if (reloadAfterResume && mounted) await _loadActiveSyncState();
  }

  Future<void> _manageDevices() async {
    final management = _management;
    if (management == null || _syncBusy) return;
    setState(() => _syncBusy = true);
    try {
      final devices = await runWebDavForegroundSync(
        context,
        title: 'Loading devices',
        stage: 'Checking the devices connected to this account…',
        operation: (_) => management.listDevices(),
      );
      if (!mounted) return;
      final target = await showSettingsDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Connected devices'),
          content: SizedBox(
            width: 520,
            child: devices.isEmpty
                ? const Text(
                    'No devices to show yet. Run Sync now and try again.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final device = devices[index];
                      return ListTile(
                        title: Text(
                          device.isThisDevice
                              ? 'This device'
                              : 'Other device · ${_shortDeviceId(device.deviceId)}',
                        ),
                        subtitle: Text(
                          device.isRegistered
                              ? 'Last seen ${_formatSyncTime(device.lastSeenMs)}'
                              : 'Signed out · saved data retained. Remove to free a device slot.',
                        ),
                        trailing: device.isThisDevice
                            ? null
                            : TextButton(
                                onPressed: () => Navigator.of(
                                  dialogContext,
                                ).pop(device.deviceId),
                                child: const Text('Remove'),
                              ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (!mounted || target == null) return;
      final confirmed = await showSettingsDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('Remove this device?'),
          content: const Text(
            'Remove this device from the list while keeping the data needed '
            'by your other devices. A device that still has your WebDAV '
            'password can connect again. Log out on that device to stop its sync.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove device'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await runWebDavForegroundSync(
        context,
        title: 'Removing device',
        stage: 'Removing this device from the list…',
        operation: (_) => management.forgetDevice(target),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sync device forgotten.')));
      await _loadActiveSyncState();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  void _showError(Object error, {VoidCallback? onRetry}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_userFacingSyncError(error)),
        action: onRetry == null
            ? null
            : SnackBarAction(label: 'Retry', onPressed: onRetry),
        backgroundColor: Colors.red,
      ),
    );
  }

  static String _userFacingSyncError(Object error) {
    final message = error
        .toString()
        .replaceFirst(
          RegExp(r'^(?:Exception|FormatException|Bad state):\s*'),
          '',
        )
        .replaceAll('\n', ' ')
        .trim();
    // Runtime and parser failures are useful in diagnostics, but protocol
    // implementation vocabulary must never become product copy through the
    // generic snackbar or a persisted binding error.
    if (message.isEmpty || _internalSyncVocabulary.hasMatch(message)) {
      return 'WebDAV Sync could not complete this operation. '
          'Try again or verify the WebDAV account.';
    }
    return message;
  }

  String _syncStatus() {
    final binding = _syncBinding;
    if (binding == null) return SettingsRows.enableWebDavSync.subtitle;
    return switch (binding.lifecycle) {
      WebDavSyncLifecycle.unconfigured => 'Sign in to a WebDAV account',
      WebDavSyncLifecycle.configured =>
        'Account selected; verification pending',
      WebDavSyncLifecycle.awaitingSeedCommit =>
        'Ready to initialize WebDAV Sync',
      WebDavSyncLifecycle.rootVerified => 'WebDAV account verified',
      WebDavSyncLifecycle.awaitingAdoption =>
        binding.errorMessage == null
            ? 'Finishing first sync…'
            : _userFacingSyncError(binding.errorMessage!),
      WebDavSyncLifecycle.active => 'Sync is active',
      WebDavSyncLifecycle.error =>
        binding.errorMessage == null
            ? 'Sync needs attention'
            : _userFacingSyncError(binding.errorMessage!),
    };
  }

  static String _completionMessage(WebDavSyncLifecycle lifecycle) =>
      switch (lifecycle) {
        WebDavSyncLifecycle.awaitingSeedCommit =>
          'WebDAV Sync is ready to initialize.',
        WebDavSyncLifecycle.rootVerified => 'WebDAV account verified.',
        WebDavSyncLifecycle.awaitingAdoption => 'Finishing first sync…',
        _ => 'WebDAV Sync configuration updated.',
      };

  Widget _buildSyncSection() {
    final active = _syncBinding?.lifecycle == WebDavSyncLifecycle.active;
    final live =
        active &&
        !_logoutPending &&
        _runtimeStatus?.automaticSyncActive == true &&
        _runtimeStatus?.clockPauseReason == null &&
        _runtimeStatus?.localStateMissing == false;
    final statusLabel = live
        ? 'Automatic sync is active'
        : active
        ? 'Automatic sync is paused or limited'
        : 'Sync is not active';
    final finishingFirstSync =
        _syncBinding?.lifecycle == WebDavSyncLifecycle.awaitingAdoption &&
        _syncBinding?.errorMessage == null;
    final credentialRepairAvailable =
        _logoutPending ||
        (_syncBinding?.lifecycle == WebDavSyncLifecycle.error &&
            _syncBinding?.circleId != null &&
            _syncBinding?.requiresStateReconnect != true);
    final tvControllerAvailable = _tvManualController != null;
    final tvButtonEnabled =
        active &&
        !_logoutPending &&
        tvControllerAvailable &&
        !_syncBusy &&
        _tvManualAvailability == WebDavSyncTvManualAvailability.available;
    final tvSubtitle = switch (_tvManualAvailability) {
      WebDavSyncTvManualAvailability.available
          when _runtimeStatus?.tvChangesPending == true =>
        'Changes are waiting for a manual sync',
      WebDavSyncTvManualAvailability.available => 'Ready to sync',
      WebDavSyncTvManualAvailability.inactive =>
        'Enable WebDAV Sync to use manual TV sync',
      WebDavSyncTvManualAvailability.firstJoinPending =>
        'Finish the first sync before syncing Debrify TV',
      WebDavSyncTvManualAvailability.cycleRunning =>
        'Wait for the current sync to finish',
      WebDavSyncTvManualAvailability.televisionPlayback =>
        'Stop TV playback, then try again',
      WebDavSyncTvManualAvailability.tvOsLowMemory =>
        'Apple TV is low on memory; wait a few minutes, then try again',
    };
    final connectedName = _syncBinding?.location.serverName;
    final lastSync = _runtimeStatus?.lastSuccessfulSyncMs;
    final clockMessage = _runtimeStatus == null
        ? null
        : _clockStatusMessage(_runtimeStatus!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'WebDAV sync',
          blurb: active
              ? 'Your profiles, shared settings and watch progress sync automatically while the app is open. Appearance stays on this device.'
              : 'Keep your profiles, shared settings and watch progress together across your devices. Appearance stays on each device.',
          children: [
            ListTile(
              leading: Icon(
                _logoutPending
                    ? Icons.cloud_off_outlined
                    : active
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_outlined,
                color: active ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Row(
                children: [
                  Tooltip(
                    message: statusLabel,
                    child: Semantics(
                      label: statusLabel,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: live
                              ? Colors.green
                              : active || finishingFirstSync || _logoutPending
                              ? Colors.amber
                              : Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _logoutPending
                          ? 'Logout needs attention'
                          : active
                          ? 'Connected to $connectedName'
                          : 'Not connected',
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                _logoutPending
                    ? 'Sync is paused. Retry logout to finish removing this connection.'
                    : finishingFirstSync
                    ? 'Setting up sync. Keep the app open while this finishes.'
                    : active
                    ? _runtimeStatus == null
                          ? _statusReadFailed || _management == null
                                ? 'Sync status unavailable'
                                : 'Loading sync status…'
                          : _runtimeStatus!.localStateMissing
                          ? 'Sync status unavailable'
                          : lastSync == null
                          ? 'Waiting for the first completed sync'
                          : 'Last synced ${_formatSyncTime(lastSync)}'
                    : _syncBinding == null
                    ? 'Connect the same WebDAV account on each device.'
                    : _syncStatus(),
              ),
            ),
            if (!active)
              SettingsTile(
                icon: Icons.login_rounded,
                title: finishingFirstSync ? 'Continue setup' : 'Connect WebDAV',
                subtitle: 'Use Koofr or another WebDAV provider',
                enabled: !_syncBusy,
                onTap: _configureSync,
              ),
            if (credentialRepairAvailable)
              SettingsTile(
                icon: Icons.key_rounded,
                title: 'Update password',
                subtitle: 'Restore access to your WebDAV account',
                enabled: !_syncBusy,
                onTap: _repairCredentials,
              ),
            if (active)
              SettingsTile(
                icon: Icons.sync,
                title: 'Sync now',
                subtitle: 'Send your changes and check for updates',
                enabled:
                    !_syncBusy && !_logoutPending && _syncActivation != null,
                onTap: _syncNow,
              ),
          ],
        ),
        if (active && !_logoutPending) ...[
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Diagnostics',
            children: [
              SettingsToggleTile(
                icon: Icons.upload_file_outlined,
                title: 'Upload diagnostic logs to WebDAV',
                subtitle:
                    'This device only. Saves one rolling file in logs/ every 5 minutes while the app is open. Anyone with folder access can read it.',
                subtitleMaxLines: 4,
                value: _logUploadEnabled,
                onChanged: _setLogUpload,
              ),
              if (_logUploadEnabled)
                SettingsTile(
                  icon: Icons.cloud_upload_outlined,
                  title: _logUploading ? 'Uploading logs…' : 'Upload logs now',
                  subtitle:
                      'Replace this device’s file with its latest diagnostic history',
                  enabled: !_logUploading && !_logSettingsBusy && !_syncBusy,
                  onTap: _uploadLogsNow,
                ),
            ],
          ),
        ],
        if (clockMessage != null || _syncStateMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            clockMessage ?? _syncStateMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_syncBinding != null) ...[
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Account and devices',
            children: [
              if (active && _management != null)
                SettingsTile(
                  icon: Icons.devices_other,
                  title: 'Connected devices',
                  subtitle: 'Manage devices using this sync account',
                  enabled: !_syncBusy && !_logoutPending,
                  onTap: _manageDevices,
                ),
              SettingsTile(
                icon: Icons.manage_accounts_outlined,
                title: 'Change account',
                subtitle: 'Use a different WebDAV account',
                enabled: !_syncBusy,
                onTap: _configureSync,
              ),
              if (_logoutController != null)
                SettingsTile(
                  icon: Icons.logout_rounded,
                  title: _logoutPending ? 'Retry logout' : 'Log out',
                  subtitle: 'Stop syncing and forget this saved login',
                  enabled: !_syncBusy,
                  onTap: _logout,
                ),
              if (_logoutPending && _logoutController != null)
                SettingsTile(
                  icon: Icons.link_off_rounded,
                  title: 'Forget connection',
                  subtitle:
                      'Disconnect on this device if WebDAV is unavailable',
                  enabled: !_syncBusy,
                  onTap: () async {
                    await _forgetConnection();
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Debrify TV channels',
          blurb:
              'Channels and saved torrent pools transfer only when you sync them here. Run this on both devices after changing channels.',
          children: [
            SettingsTile(
              icon: Icons.live_tv_rounded,
              title: 'Sync channels now',
              subtitle: tvControllerAvailable
                  ? tvSubtitle
                  : 'Connect WebDAV to sync your channels',
              enabled: tvButtonEnabled,
              onTap: _syncDebrifyTv,
            ),
          ],
        ),
        if (active && _runtimeStatus?.lastTvSyncMs != null) ...[
          const SizedBox(height: 8),
          Text(
            'Channels last synced ${_formatSyncTime(_runtimeStatus!.lastTvSyncMs!)}',
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
        if (active && _runtimeStatus != null) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Sync details'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_pollStatusMessage(_runtimeStatus!)),
              const SizedBox(height: 8),
              const Text(
                'IPTV playlists, favorites and watch history sync automatically. Channel listings and TV guides are downloaded separately on each device.',
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  static String _formatSyncTime(int milliseconds) => DateFormat.yMd()
      .add_jm()
      .format(DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal());

  static String _pollStatusMessage(WebDavSyncRuntimeStatus status) =>
      switch (status.pollState) {
        WebDavSyncPollState.active when status.lastRemoteChangeMs != null =>
          'Checking for changes every minute • Last remote change '
              '${_formatSyncTime(status.lastRemoteChangeMs!)}',
        WebDavSyncPollState.active => 'Checking for changes every minute',
        WebDavSyncPollState.pausedBackoff =>
          'Checking for changes paused; syncing continues every 15 min',
        WebDavSyncPollState.disabledNoValidators =>
          'Server does not report changes; syncing every 15 min',
        WebDavSyncPollState.gated => 'Checking for changes is currently paused',
      };

  static String? _clockStatusMessage(WebDavSyncRuntimeStatus status) {
    final paused = switch (status.clockPauseReason) {
      WebDavSyncClockPauseReason.missingServerDate =>
        'Sync is paused because the WebDAV server did not provide a reliable clock.',
      WebDavSyncClockPauseReason.offsetOutlier =>
        'Sync is paused while a large device or server clock change is confirmed.',
      WebDavSyncClockPauseReason.serverMovedBackwards =>
        'Sync is paused because the WebDAV server clock moved backwards.',
      null => null,
    };
    if (paused != null) return paused;
    return status.deviceClockWarning
        ? 'This device clock differs substantially from the WebDAV server; sync timestamps use server time.'
        : null;
  }

  static String _shortDeviceId(String value) =>
      value.length <= 16 ? value : '${value.substring(0, 12)}…';

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Sync and Migrate',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [if (_syncFeatureEnabled) _buildSyncSection()],
            ),
          ),
        ),
      ),
    );
  }
}

final class _DebrifyTvSyncProgressDialog extends StatefulWidget {
  const _DebrifyTvSyncProgressDialog({required this.operation});

  final _DebrifyTvSyncOperation operation;

  @override
  State<_DebrifyTvSyncProgressDialog> createState() =>
      _DebrifyTvSyncProgressDialogState();
}

final class _DebrifyTvSyncProgressDialogState
    extends State<_DebrifyTvSyncProgressDialog> {
  WebDavSyncTvManualStage _stage = WebDavSyncTvManualStage.reading;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final report = await widget.operation.start(
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (mounted) Navigator.of(context).pop(report);
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _stop() {
    if (_stopping) return;
    widget.operation.cancel();
    setState(() => _stopping = true);
  }

  @override
  void dispose() {
    widget.operation.cancel();
    super.dispose();
  }

  String get _stageLabel => switch (_stage) {
    WebDavSyncTvManualStage.reading => 'Reading',
    WebDavSyncTvManualStage.merging => 'Merging',
    WebDavSyncTvManualStage.applying => 'Applying',
    WebDavSyncTvManualStage.publishing => 'Publishing',
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Syncing Debrify TV'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Text(_stopping ? 'Stopping after this stage…' : _stageLabel),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _stopping ? null : _stop,
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}

final class _DebrifyTvSyncOperation {
  _DebrifyTvSyncOperation(this._controller);

  final WebDavSyncTvManualController _controller;
  final WebDavSyncTvCancellationToken _token = WebDavSyncTvCancellationToken();
  Future<WebDavSyncTvManualReport>? _terminal;

  Future<WebDavSyncTvManualReport> start({
    WebDavSyncTvStageCallback? onStage,
  }) => _terminal ??= _controller.syncDebrifyTv(
    cancellationToken: _token,
    onStage: onStage,
  );

  Future<WebDavSyncTvManualReport> get terminal => _terminal!;

  void cancel() => _token.cancel();

  Future<void> cancelAndWait() async {
    cancel();
    final terminal = _terminal;
    if (terminal != null) await terminal;
  }
}

final RegExp _internalSyncVocabulary = RegExp(
  r'circle|seed|join|enroll|passphrase',
  caseSensitive: false,
);

final class _SyncCredentialInput {
  const _SyncCredentialInput({required this.username, required this.password});

  final String username;
  final String password;
}

final class _SyncCredentialDialog extends StatefulWidget {
  const _SyncCredentialDialog({required this.initialUsername});

  final String initialUsername;

  @override
  State<_SyncCredentialDialog> createState() => _SyncCredentialDialogState();
}

final class _SyncCredentialDialogState extends State<_SyncCredentialDialog> {
  late final TextEditingController _username = TextEditingController(
    text: widget.initialUsername,
  );
  final TextEditingController _password = TextEditingController();

  bool get _valid =>
      _username.text.trim().isNotEmpty && _password.text.isNotEmpty;

  @override
  void dispose() {
    _username.dispose();
    _password
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(
      _SyncCredentialInput(
        username: _username.text.trim(),
        password: _password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify sync credentials'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvTextField(
              controller: _username,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'WebDAV username'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TvTextField(
              controller: _password,
              obscureText: true,
              textInputAction: TextInputAction.done,
              keyboardSubmitLabel: 'Verify',
              decoration: const InputDecoration(labelText: 'WebDAV password'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('Verify'),
        ),
      ],
    );
  }
}
