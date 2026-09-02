import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/webdav_item.dart';
import '../../services/analytics_service.dart';
import '../../services/webdav_sync/webdav_sync_activation.dart';
import '../../services/webdav_sync/webdav_sync_clock.dart';
import '../../services/webdav_sync/webdav_sync_engine.dart';
import '../../services/webdav_sync/webdav_sync_feature.dart';
import '../../services/webdav_sync/webdav_sync_graph_tier.dart';
import '../../services/webdav_sync/webdav_sync_models.dart';
import '../../services/webdav_sync/webdav_sync_runtime.dart';
import '../../services/webdav_sync/webdav_sync_scheduler.dart';
import '../../services/webdav_sync/webdav_sync_setup_authorization.dart';
import '../../services/webdav_sync/webdav_sync_setup_service.dart';
import '../../widgets/tv_text_field.dart';
import '../webdav/webdav_files_screen.dart';
import 'profile_backup_flows.dart';
import 'widgets/settings_widgets.dart';

class SyncAndMigratePage extends StatefulWidget {
  const SyncAndMigratePage({
    super.key,
    this.onRestored,
    this.syncService,
    this.syncAuthorization,
    this.syncActivation,
    this.syncFeatureEnabled,
    this.pickSyncFolder,
  });

  final Future<void> Function()? onRestored;
  final WebDavSyncSetupService? syncService;
  final WebDavSyncSetupAuthorization? syncAuthorization;
  final WebDavSyncActivationController? syncActivation;
  final bool? syncFeatureEnabled;
  final Future<WebDavPickerResult?> Function(BuildContext context)?
  pickSyncFolder;

  @override
  State<SyncAndMigratePage> createState() => _SyncAndMigratePageState();
}

class _SyncAndMigratePageState extends State<SyncAndMigratePage> {
  late final WebDavSyncSetupService _syncService;
  late final WebDavSyncSetupAuthorization _syncAuthorization;
  WebDavSyncActivationController? _syncActivation;
  WebDavSyncBinding? _syncBinding;
  WebDavSyncRuntimeStatus? _runtimeStatus;
  WebDavSyncGraphChange? _graphChange;
  String? _graphTierMessage;
  String? _promptedGraphDigest;
  bool _syncBusy = false;

  bool get _syncFeatureEnabled =>
      widget.syncFeatureEnabled ?? WebDavSyncFeature.enabled;

  @override
  void initState() {
    super.initState();
    _syncService = widget.syncService ?? WebDavSyncSetupService();
    _syncAuthorization =
        widget.syncAuthorization ?? const ProfileWebDavSyncSetupAuthorization();
    // A custom setup service in widget tests intentionally exercises the M3
    // read-only boundary. Production owns the integrated M5 activation flow.
    _syncActivation =
        widget.syncActivation ??
        (widget.syncService == null ? WebDavSyncRuntime.instance : null);
    AnalyticsService.screenView('sync_and_migrate');
    if (_syncFeatureEnabled) _loadSyncState();
  }

  Future<void> _loadSyncState() async {
    try {
      final snapshot = await _syncService.store.load();
      if (!mounted) return;
      setState(() {
        _syncBinding = snapshot.stagedBinding ?? snapshot.activeBinding;
      });
      if (_syncBinding?.lifecycle == WebDavSyncLifecycle.active) {
        unawaited(_loadActiveSyncState());
      }
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  WebDavSyncManagementController? get _management =>
      _syncActivation is WebDavSyncManagementController
      ? _syncActivation as WebDavSyncManagementController
      : null;

  Future<void> _loadActiveSyncState() async {
    final management = _management;
    if (management == null) return;
    try {
      final status = await management.status();
      if (status.localStateMissing) {
        final snapshot = await _syncService.store.load();
        if (!mounted) return;
        setState(() {
          _syncBinding = snapshot.stagedBinding ?? snapshot.activeBinding;
          _runtimeStatus = status;
          _graphChange = null;
          _graphTierMessage =
              'Local sync state was cleared. Verify this folder again to reconnect safely.';
        });
        return;
      }
      // Opening this interactive page should discover graph changes without
      // queuing a potentially large daily database snapshot ahead of Sync now.
      // Automatic maintenance still owns the scheduled bootstrap refresh.
      final graph = await management.checkGraph(runBootstrapMaintenance: false);
      if (!mounted) return;
      setState(() {
        _runtimeStatus = status;
        _graphChange = graph.change;
        _graphTierMessage = switch (graph.disposition) {
          WebDavSyncGraphTierDisposition.adminRequired =>
            'Profiles & connections sync waits for an Admin session',
          WebDavSyncGraphTierDisposition.updateRequired =>
            'Update Debrify to sync profiles & connections',
          _ when status.adminPruneBlocked =>
            status.safetyCleanupBlocked
                ? 'Safety backup unavailable; kept ${status.pruneBlockingProfiles.join(', ')} on this device'
                : 'Profile cleanup is pending for ${status.pruneBlockingProfiles.join(', ')}; activity sync continues',
          _ => null,
        };
      });
      final change = graph.change;
      if (change != null && _promptedGraphDigest != change.semanticDigest) {
        _promptedGraphDigest = change.semanticDigest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_reviewGraphChange(change));
        });
      }
    } catch (_) {
      // Active sync remains usable offline; manual Sync now surfaces errors.
    }
  }

  Future<void> _configureSync() async {
    if (_syncBusy) return;
    setState(() => _syncBusy = true);
    final reconfiguration =
        _syncActivation is WebDavSyncReconfigurationController
        ? _syncActivation as WebDavSyncReconfigurationController
        : null;
    try {
      await _syncAuthorization.requireAdmin();
      reconfiguration?.pauseForReconfiguration();
      if (!mounted) return;
      final selection = widget.pickSyncFolder != null
          ? await widget.pickSyncFolder!(context)
          : await Navigator.of(context).push<WebDavPickerResult>(
              MaterialPageRoute(
                builder: (_) => const WebDavFilesScreen(
                  isPushedRoute: true,
                  pickerMode: WebDavPickerMode.selectFolder,
                  dataSource: WebDavFilesDataSource(
                    feature: ProfileFeature.backupRestore,
                  ),
                ),
              ),
            );
      if (selection == null || !mounted) return;
      final inspection = await _syncAuthorization.runForConfig(
        selection.config,
        (beforeSend) => _syncService.inspectFolder(
          config: selection.config,
          folderPath: selection.path,
          beforeSend: beforeSend,
        ),
      );
      if (!mounted) return;

      WebDavSyncBinding binding;
      if (inspection is WebDavSyncFolderMissing) {
        if (!await _confirmNewFolder(inspection) || !mounted) return;
        final passphrase = await _askForPassphrase(create: true);
        if (passphrase == null || !mounted) return;
        binding = await _syncAuthorization.runForConfig(
          inspection.config,
          (beforeCommit) => _syncService.configureNewRoot(
            inspection: inspection,
            syncPassphrase: passphrase,
            beforeCommit: beforeCommit,
          ),
        );
        final activation = _syncActivation;
        if (activation != null) {
          final outcome = await activation.initializeNew(binding.id);
          if (outcome is WebDavSyncInitialized) {
            binding = outcome.binding;
          } else if (outcome is WebDavSyncConcurrentRoot) {
            binding = outcome.binding;
            await activation.inspectExisting(binding.id);
            if (!mounted) return;
            final confirmed = await _confirmExistingReplacement();
            if (!mounted || !confirmed) {
              if (!confirmed) await _syncService.store.discardStaged();
              await _loadSyncState();
              return;
            }
            binding = await activation.connectExisting(
              binding.id,
              replacementConfirmed: true,
            );
          }
        }
      } else if (inspection is WebDavSyncFolderExisting) {
        final passphrase = await _askForPassphrase(create: false);
        if (passphrase == null || !mounted) return;
        binding = await _syncAuthorization.runForConfig(
          inspection.config,
          (beforeCommit) => _syncService.configureExistingRoot(
            inspection: inspection,
            syncPassphrase: passphrase,
            reconnectActive: _syncBinding?.requiresStateReconnect == true,
            beforeCommit: beforeCommit,
          ),
        );
        final activation = _syncActivation;
        if (activation != null &&
            binding.lifecycle != WebDavSyncLifecycle.active) {
          if (binding.lifecycle == WebDavSyncLifecycle.awaitingSeedCommit) {
            final outcome = await activation.initializeNew(binding.id);
            if (outcome is WebDavSyncInitialized) {
              binding = outcome.binding;
            } else if (outcome is WebDavSyncConcurrentRoot) {
              binding = outcome.binding;
              await activation.inspectExisting(binding.id);
              if (!mounted) return;
              final confirmed = await _confirmExistingReplacement();
              if (!mounted || !confirmed) {
                if (!confirmed) await _syncService.store.discardStaged();
                await _loadSyncState();
                return;
              }
              binding = await activation.connectExisting(
                binding.id,
                replacementConfirmed: true,
              );
            }
          } else {
            await activation.inspectExisting(binding.id);
            if (!mounted) return;
            final confirmed = await _confirmExistingReplacement();
            if (!mounted || !confirmed) {
              if (!confirmed) await _syncService.store.discardStaged();
              await _loadSyncState();
              return;
            }
            binding = await activation.connectExisting(
              binding.id,
              replacementConfirmed: true,
            );
          }
        }
      } else {
        throw StateError('Unexpected WebDAV sync folder result');
      }
      if (!mounted) return;
      setState(() => _syncBinding = binding);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_completionMessage(binding.lifecycle))),
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      try {
        await reconfiguration?.resumeAfterReconfiguration();
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
            title: const Text('Use sync data from this folder?'),
            content: const Text(
              'Existing profiles and connections on this device will be '
              'replaced. Debrify creates and verifies an encrypted local '
              'safety backup before changing anything. IPTV channel and '
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

  Future<void> _syncNow() async {
    final activation = _syncActivation;
    if (_syncBusy || activation == null) return;
    setState(() => _syncBusy = true);
    try {
      final report = await activation.syncNow();
      if (!mounted) return;
      final message = switch (report.disposition) {
        WebDavSyncCycleDisposition.completed => 'WebDAV Sync is up to date.',
        WebDavSyncCycleDisposition.clockPaused =>
          'Sync is paused because the device or server clock needs attention.',
        WebDavSyncCycleDisposition.adoptionBlocked =>
          'Sync is waiting for profile replacement to finish.',
        WebDavSyncCycleDisposition.seedRepairRequired =>
          'Sync data for this device is being rebuilt.',
        WebDavSyncCycleDisposition.inactive => 'Sync is currently paused.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _loadSyncState();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _repairCredentials() async {
    if (_syncBusy) return;
    final binding = _syncBinding;
    if (binding == null || binding.circleId == null) return;
    setState(() => _syncBusy = true);
    final reconfiguration =
        _syncActivation is WebDavSyncReconfigurationController
        ? _syncActivation as WebDavSyncReconfigurationController
        : null;
    var reloadAfterResume = false;
    try {
      await _syncAuthorization.requireAdmin();
      final currentSecrets = await _syncService.store.readSecrets(binding);
      if (!mounted) return;
      final input = await showSettingsDialog<_SyncCredentialInput>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _SyncCredentialDialog(initialUsername: currentSecrets.username),
      );
      if (input == null || !mounted) return;
      reconfiguration?.pauseForReconfiguration();
      final config = WebDavConfig(
        id: 'webdav-sync-credentials',
        name: binding.location.serverName,
        baseUrl: binding.location.endpoint.toString(),
        username: input.username,
        password: input.password,
      );
      final repaired = await _syncAuthorization.runForActiveBinding((
        beforeSend,
      ) async {
        final inspection = await _syncService.inspectFolder(
          config: config,
          folderPath: binding.location.folderPath,
          beforeSend: beforeSend,
        );
        if (inspection is! WebDavSyncFolderExisting) {
          throw const WebDavSyncRootMissingException();
        }
        return _syncService.configureExistingRoot(
          inspection: inspection,
          syncPassphrase: input.passphrase,
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
        await reconfiguration?.resumeAfterReconfiguration();
      } catch (error) {
        if (mounted) _showError(error);
      } finally {
        if (mounted) setState(() => _syncBusy = false);
      }
    }
    if (reloadAfterResume && mounted) await _loadActiveSyncState();
  }

  Future<void> _reviewGraphChange(WebDavSyncGraphChange change) async {
    final management = _management;
    if (management == null || _syncBusy || !mounted) return;
    final decision = await showSettingsDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Profiles & connections changed'),
        content: const Text(
          'Another synced device changed profiles or connections. Applying '
          'the update creates and verifies an encrypted local safety backup '
          'before replacing this device\'s structure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep current setup'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apply update'),
          ),
        ],
      ),
    );
    if (!mounted || decision == null) return;
    setState(() => _syncBusy = true);
    try {
      if (decision) {
        await management.applyGraph(change.semanticDigest);
      } else {
        await management.declineGraph(change.semanticDigest);
      }
      if (!mounted) return;
      setState(() => _graphChange = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision
                ? 'Profiles and connections were updated.'
                : 'This profile update will not be shown again.',
          ),
        ),
      );
      await _loadSyncState();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _manageDevices() async {
    final management = _management;
    if (management == null || _syncBusy) return;
    setState(() => _syncBusy = true);
    try {
      final devices = await management.listDevices();
      if (!mounted) return;
      final target = await showSettingsDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Synced devices'),
          content: SizedBox(
            width: 520,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: devices.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final device = devices[index];
                return ListTile(
                  title: Text(
                    device.isThisDevice
                        ? 'This device'
                        : _shortDeviceId(device.deviceId),
                  ),
                  subtitle: Text(
                    'Last seen ${_formatSyncTime(device.lastSeenMs)}',
                  ),
                  trailing: device.isThisDevice
                      ? null
                      : TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(device.deviceId),
                          child: const Text('Forget'),
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
          title: const Text('Forget this device?'),
          content: const Text(
            'This removes its server bookkeeping after preserving deletions '
            'and recovery data. It does not revoke an installed device that '
            'still has the WebDAV password and sync passphrase. Change the '
            'WebDAV password on the server to revoke access.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Forget device'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await management.forgetDevice(target);
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

  Future<bool> _confirmNewFolder(WebDavSyncFolderMissing inspection) async {
    return await showSettingsDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Create WebDAV sync here?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No existing Debrify sync was found in this folder. '
                  'Continuing will create a new sync here.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'Server: ${inspection.location.endpoint}\n'
                  'Folder: ${inspection.location.resolvedFolderUri}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _askForPassphrase({required bool create}) async {
    return showSettingsDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SyncPassphraseDialog(create: create),
    );
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_userFacingSyncError(error)),
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
          'Try again or verify the selected folder.';
    }
    return message;
  }

  String _syncStatus() {
    final binding = _syncBinding;
    if (binding == null) return SettingsRows.enableWebDavSync.subtitle;
    return switch (binding.lifecycle) {
      WebDavSyncLifecycle.unconfigured => 'Choose the exact folder to use',
      WebDavSyncLifecycle.configured => 'Folder selected; verification pending',
      WebDavSyncLifecycle.awaitingSeedCommit =>
        'Ready to initialize this folder',
      WebDavSyncLifecycle.rootVerified => 'Folder verified',
      WebDavSyncLifecycle.awaitingAdoption =>
        'Ready to connect after confirmation',
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
          'Folder selected. WebDAV Sync is ready to initialize.',
        WebDavSyncLifecycle.rootVerified => 'WebDAV sync folder verified.',
        _ => 'WebDAV Sync configuration updated.',
      };

  Widget _buildSyncSection() {
    final active = _syncBinding?.lifecycle == WebDavSyncLifecycle.active;
    final credentialRepairAvailable =
        _syncBinding?.lifecycle == WebDavSyncLifecycle.error &&
        _syncBinding?.circleId != null &&
        _syncBinding?.requiresStateReconnect != true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionLabel('Sync'),
        const SizedBox(height: 8),
        SettingsSection(
          title: '',
          children: [
            SettingsTile(
              icon: SettingsRows.enableWebDavSync.icon,
              title: active ? 'Change sync folder' : 'Enable WebDAV Sync',
              subtitle: _syncStatus(),
              enabled: !_syncBusy,
              trailing: _syncBusy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _configureSync,
            ),
            if (credentialRepairAvailable)
              SettingsTile(
                icon: Icons.key_rounded,
                title: 'Re-enter password / passphrase',
                subtitle: 'Verify this same folder without choosing it again',
                enabled: !_syncBusy,
                onTap: _repairCredentials,
              ),
            if (active)
              SettingsTile(
                icon: Icons.sync,
                title: 'Sync now',
                subtitle: 'Check this folder for changes',
                enabled: !_syncBusy && _syncActivation != null,
                onTap: _syncNow,
              ),
            if (active && _graphChange != null)
              SettingsTile(
                icon: Icons.account_tree_outlined,
                title: 'Profiles & connections update',
                subtitle: 'Review a change from another synced device',
                enabled: !_syncBusy,
                onTap: () => _reviewGraphChange(_graphChange!),
              ),
            if (active && _management != null)
              SettingsTile(
                icon: Icons.devices_other,
                title: 'Synced devices',
                subtitle: 'View or forget server device records',
                enabled: !_syncBusy,
                onTap: _manageDevices,
              ),
          ],
        ),
        if (_syncBinding != null) ...[
          const SizedBox(height: 8),
          Text(
            '${active ? 'Connected to' : 'Selected'}: '
            '${_syncBinding!.location.resolvedFolderUri}',
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
        if (active && _runtimeStatus != null) ...[
          const SizedBox(height: 8),
          Text(
            _runtimeStatus!.lastSuccessfulSyncMs == null
                ? 'No completed sync yet'
                : 'Last synced ${_formatSyncTime(_runtimeStatus!.lastSuccessfulSyncMs!)}'
                      ' • ${_runtimeStatus!.peerCount} device record${_runtimeStatus!.peerCount == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Text(
            _pollStatusMessage(_runtimeStatus!),
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
        if (active &&
            _runtimeStatus != null &&
            _clockStatusMessage(_runtimeStatus!) != null) ...[
          const SizedBox(height: 8),
          Text(
            _clockStatusMessage(_runtimeStatus!)!,
            style: const TextStyle(fontSize: 12.5, color: Colors.amber),
          ),
        ],
        if (active && _graphTierMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _graphTierMessage!,
            style: const TextStyle(fontSize: 12.5, color: Colors.amber),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'IPTV sources, favorites, history and resume state transfer. Each '
          'device rebuilds its channel and guide caches. Debrify TV channels '
          'do not transfer yet.',
          style: TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 20),
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
              children: [
                if (_syncFeatureEnabled) _buildSyncSection(),
                const SettingsSectionLabel('Migrate'),
                const SizedBox(height: 8),
                SettingsSection(
                  title: '',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.createWebDavBackup,
                      onTap: () => ProfileBackupFlows(
                        context,
                      ).createWebDavProfileBackup(),
                    ),
                    SettingsTile.spec(
                      SettingsRows.restoreWebDavBackup,
                      onTap: () => ProfileBackupFlows(
                        context,
                        onRestored: widget.onRestored,
                      ).restoreWebDavProfileBackup(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Backups are encrypted with the passphrase you choose. '
                  'This is a manual transfer; continuous WebDAV Sync '
                  'is not enabled by these actions.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final RegExp _internalSyncVocabulary = RegExp(
  r'circle|seed|join|enroll',
  caseSensitive: false,
);

final class _SyncPassphraseDialog extends StatefulWidget {
  const _SyncPassphraseDialog({required this.create});

  final bool create;

  @override
  State<_SyncPassphraseDialog> createState() => _SyncPassphraseDialogState();
}

final class _SyncPassphraseDialogState extends State<_SyncPassphraseDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.length >= 8) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.create ? 'Create sync passphrase' : 'Sync passphrase'),
      content: TvTextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        textInputAction: TextInputAction.done,
        keyboardSubmitLabel: 'Continue',
        decoration: const InputDecoration(labelText: 'Minimum 8 characters'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _controller.text.length >= 8 ? _submit : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

final class _SyncCredentialInput {
  const _SyncCredentialInput({
    required this.username,
    required this.password,
    required this.passphrase,
  });

  final String username;
  final String password;
  final String passphrase;
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
  final TextEditingController _passphrase = TextEditingController();

  bool get _valid =>
      _username.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      _passphrase.text.length >= 8;

  @override
  void dispose() {
    _username.dispose();
    _password
      ..clear()
      ..dispose();
    _passphrase
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
        passphrase: _passphrase.text,
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
              decoration: const InputDecoration(labelText: 'WebDAV password'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TvTextField(
              controller: _passphrase,
              obscureText: true,
              textInputAction: TextInputAction.done,
              keyboardSubmitLabel: 'Verify',
              decoration: const InputDecoration(labelText: 'Sync passphrase'),
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
