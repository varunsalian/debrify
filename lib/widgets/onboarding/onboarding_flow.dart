import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/settings/profile_backup_flows.dart';
import '../../services/account_service.dart';
import '../../services/alldebrid_account_service.dart';
import '../../services/analytics_service.dart';
import '../../services/engine/config_loader.dart';
import '../../services/engine/engine_registry.dart';
import '../../services/engine/local_engine_storage.dart';
import '../../services/engine/remote_engine_manager.dart';
import '../../services/main_page_bridge.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/premiumize_account_service.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_restore_coordinator.dart';
import '../../services/remote_control/remote_command_router.dart';
import '../../services/remote_control/remote_constants.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/storage_service.dart';
import '../../services/torbox_account_service.dart';
import '../../utils/platform_util.dart';
import '../pikpak_folder_picker_dialog.dart';
import 'controllers/tracker_auth_controller.dart';
import 'key_codec.dart';
import 'onboarding_focus.dart';
import 'onboarding_models.dart';
import 'onboarding_stage.dart';
import 'onboarding_theme.dart';
import 'steps/done_step.dart';
import 'steps/engines_step.dart';
import 'steps/import_step.dart';
import 'steps/key_step.dart';
import 'steps/mode_step.dart';
import 'steps/services_step.dart';
import 'steps/trackers_step.dart';
import '../../services/mdblist/mdblist_service.dart';
import 'tv_keyboard_slot.dart';

typedef OnboardingValidationOverride =
    Future<bool> Function(
      IntegrationType type,
      String value,
      String? secondary,
    );

typedef OnboardingEngineImportOverride =
    Future<bool> Function(RemoteEngineInfo engine, String yaml);

typedef OnboardingBackupRestoreOverride =
    Future<ProfileBackupRestoreResult?> Function();

typedef OnboardingBackupHandoffOverride =
    Future<void> Function(ProfileGraphRestoreReport report);

class InitialSetupFlow extends StatefulWidget {
  const InitialSetupFlow({
    super.key,
    this.engineManager,
    this.engineImportOverride,
    this.backupRestoreOverride,
    this.backupHandoffOverride,
    this.validationOverride,
    this.isTelevisionOverride,
  });

  final RemoteEngineManager? engineManager;
  final OnboardingEngineImportOverride? engineImportOverride;
  final OnboardingBackupRestoreOverride? backupRestoreOverride;
  final OnboardingBackupHandoffOverride? backupHandoffOverride;
  final OnboardingValidationOverride? validationOverride;
  final bool? isTelevisionOverride;

  static Future<bool> show(BuildContext context) async {
    final parentFocusScope = FocusScope.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    parentFocusScope.canRequestFocus = false;
    try {
      final isTelevision = PlatformUtil.isTelevision;
      final result = await Navigator.of(context, rootNavigator: true)
          .push<bool>(
            PageRouteBuilder<bool>(
              opaque: true,
              maintainState: true,
              transitionDuration: isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              reverseTransitionDuration: isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              pageBuilder: (_, __, ___) =>
                  OnboardingTheme.scope(const InitialSetupFlow()),
              transitionsBuilder: (_, animation, __, child) => isTelevision
                  ? child
                  : FadeTransition(opacity: animation, child: child),
            ),
          );
      return result ?? false;
    } finally {
      // A remote config/complete intentionally replaces the entire route
      // stack. In that case the caller's focus scope has been disposed along
      // with its route and must not be touched by this async finally block.
      if (context.mounted) parentFocusScope.canRequestFocus = true;
    }
  }

  @override
  State<InitialSetupFlow> createState() => _InitialSetupFlowState();
}

class _InitialSetupFlowState extends State<InitialSetupFlow> {
  late final bool _isTelevision =
      widget.isTelevisionOverride ?? PlatformUtil.isTelevision;
  late final RemoteEngineManager _engineManager =
      widget.engineManager ?? RemoteEngineManager();
  late final bool _ownsEngineManager = widget.engineManager == null;

  final OnboardFocusController _focus = OnboardFocusController();
  final TvKeyboardSession _keyboardSession = TvKeyboardSession();
  final Set<IntegrationType> _serviceSelection = <IntegrationType>{};
  final Map<IntegrationType, TextEditingController> _controllers = {
    for (final type in IntegrationType.values) type: TextEditingController(),
  };
  final TextEditingController _pikpakPassword = TextEditingController();

  late final TrackerAuthController _trakt = TrackerAuthController(
    TrackerKind.trakt,
  )..addListener(_trackerChanged);
  late final TrackerAuthController _simkl = TrackerAuthController(
    TrackerKind.simkl,
  )..addListener(_trackerChanged);
  bool _mdblistConnected = false;

  OnboardStep _step = OnboardStep.mode;
  List<IntegrationType> _providerFlow = <IntegrationType>[];
  int _providerIndex = 0;
  KeyValidationPhase _keyPhase = KeyValidationPhase.idle;
  String? _keyError;
  String? _clipboardCandidate;
  int _keyRequest = 0;

  List<RemoteEngineInfo> _engines = <RemoteEngineInfo>[];
  Set<String> _selectedEngines = <String>{};
  List<String> _importedEngineNames = <String>[];
  bool _loadingEngines = false;
  bool _importingEngines = false;
  String? _engineError;
  int _engineRequest = 0;
  int _engineImportRequest = 0;
  Completer<void>? _engineTransactionSettled;

  final List<String> _connectedServices = <String>[];
  bool _hasConfigured = false;
  bool _finishing = false;
  bool _restoringBackup = false;

  ReceiverLease? _importLease;
  int _importAttempt = 0;
  bool _importListenersAttached = false;
  bool _transferComplete = false;
  bool _hadImportConnection = false;
  int _receivedItemCount = 0;
  String? _lastReceivedLabel;
  String? _chunkInFlightLabel;
  String _advertisedName = 'This device';
  String? _receiverError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestLanding());
  }

  @override
  void dispose() {
    _engineRequest++;
    _engineImportRequest++;
    _keyRequest++;
    _importAttempt++;
    _detachImportListeners();
    final lease = _importLease;
    _importLease = null;
    if (lease != null) unawaited(lease.release());
    _trakt.removeListener(_trackerChanged);
    _simkl.removeListener(_trackerChanged);
    _trakt.dispose();
    _simkl.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _pikpakPassword.dispose();
    _keyboardSession.dispose();
    _focus.dispose();
    if (_ownsEngineManager) _engineManager.dispose();
    super.dispose();
  }

  void _trackerChanged() {
    if (!mounted) return;
    if (_trakt.connected || _simkl.connected) _hasConfigured = true;
    setState(() {});
  }

  void _transition(OnboardStep step, {bool requestFocus = true}) {
    _focus.clearStep();
    setState(() => _step = step);
    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestLanding());
    }
  }

  void _requestLanding() {
    // TV only. Landing focus is the DPAD cursor's opening position; on touch
    // there is no cursor, so the same request just made the first card wear
    // the parallax pop for no one (every step-transition call site funnels
    // through here, so this is the one gate). Pointer/keyboard users on
    // desktop reach the cards by click or arrow like any other page.
    if (!mounted || !_isTelevision) return;
    _focus.focusLanding(_step);
  }

  Future<void> _handleBack() async {
    if (_keyboardSession.ownsBack) return;
    if (_step == OnboardStep.key &&
        _keyPhase == KeyValidationPhase.validating) {
      return;
    }
    switch (_step) {
      case OnboardStep.mode:
        await _leave();
      case OnboardStep.services:
        _transition(OnboardStep.mode);
      case OnboardStep.key:
        _keyRequest++;
        if (_providerIndex > 0) {
          setState(() {
            _providerIndex--;
            _keyPhase = KeyValidationPhase.idle;
            _keyError = null;
          });
          await _prepareKeyLanding();
        } else {
          _transition(OnboardStep.services);
        }
      case OnboardStep.engines:
        _engineImportRequest++;
        _importingEngines = false;
        final transactionSettled = _engineTransactionSettled;
        if (transactionSettled != null) {
          await transactionSettled.future;
          if (!mounted || _step != OnboardStep.engines) return;
        }
        if (_providerFlow.isEmpty) {
          _transition(OnboardStep.services);
        } else {
          _providerIndex = _providerFlow.length - 1;
          _transition(OnboardStep.key, requestFocus: false);
          await _prepareKeyLanding();
        }
      case OnboardStep.trackers:
        _transition(OnboardStep.engines);
      case OnboardStep.importing:
        await _leaveImport();
        if (mounted) _transition(OnboardStep.mode);
      case OnboardStep.done:
        _transition(OnboardStep.trackers);
    }
  }

  void _chooseSetupHere() => _transition(OnboardStep.services);

  void _toggleService(IntegrationType type) {
    setState(() {
      if (!_serviceSelection.add(type)) _serviceSelection.remove(type);
    });
  }

  Future<void> _startSelectedServices() async {
    if (_serviceSelection.isEmpty) return;
    _providerFlow = <IntegrationType>[
      for (final type in IntegrationType.values)
        if (_serviceSelection.contains(type)) type,
    ];
    _providerIndex = 0;
    _keyPhase = KeyValidationPhase.idle;
    _keyError = null;
    _transition(OnboardStep.key, requestFocus: false);
    await _prepareKeyLanding();
  }

  Future<void> _prepareKeyLanding() async {
    _clipboardCandidate = null;
    if (mounted) setState(() {});
    ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      data = null;
    }
    if (!mounted || _step != OnboardStep.key) return;
    final raw = data?.text?.trim() ?? '';
    final meta = integrationMeta[_providerFlow[_providerIndex]]!;
    final parsed = parseOnboardingKey(raw);
    final plausible = meta.type == IntegrationType.pikpak
        ? raw.contains('@')
        : meta.keyLength != null
        ? parsed.key.length == meta.keyLength
        : parsed.key.length >= 8;
    setState(() => _clipboardCandidate = plausible ? raw : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestLanding());
  }

  void _skipProvider() {
    _keyRequest++;
    _advanceProvider();
  }

  void _advanceProvider() {
    if (_providerIndex + 1 < _providerFlow.length) {
      setState(() {
        _providerIndex++;
        _keyPhase = KeyValidationPhase.idle;
        _keyError = null;
      });
      unawaited(_prepareKeyLanding());
      return;
    }
    _goToEngines();
  }

  Future<void> _submitProvider() async {
    if (_keyPhase == KeyValidationPhase.validating) return;
    final request = ++_keyRequest;
    final type = _providerFlow[_providerIndex];
    final providerIndex = _providerIndex;
    final primaryController = _controllers[type]!;
    final parsed = type == IntegrationType.pikpak
        ? (key: primaryController.text.trim(), hideFromNav: false)
        : parseOnboardingKey(primaryController.text);
    final secondary = type == IntegrationType.pikpak
        ? _pikpakPassword.text.trim()
        : null;
    if (parsed.key.isEmpty ||
        (type == IntegrationType.pikpak && (secondary?.isEmpty ?? true))) {
      setState(() {
        _keyPhase = KeyValidationPhase.failed;
        _keyError = type == IntegrationType.pikpak
            ? 'Enter both your email and password.'
            : 'Enter an API key to continue.';
      });
      return;
    }

    setState(() {
      _keyPhase = KeyValidationPhase.validating;
      _keyError = null;
    });
    var success = false;
    try {
      success = widget.validationOverride != null
          ? await widget.validationOverride!(type, parsed.key, secondary)
          : await _validate(type, parsed.key, secondary);
    } catch (error, stackTrace) {
      debugPrint('Onboarding validation failed for ${type.name}: $error');
      if (kDebugMode) debugPrint('$stackTrace');
      success = false;
    }
    if (!mounted ||
        request != _keyRequest ||
        _step != OnboardStep.key ||
        providerIndex != _providerIndex ||
        _providerFlow[_providerIndex] != type) {
      return;
    }
    if (!success) {
      setState(() {
        _keyPhase = KeyValidationPhase.failed;
        _keyError = type == IntegrationType.pikpak
            ? 'Login failed. Check your credentials and try again.'
            : "That key didn't work — check for a missing character";
      });
      return;
    }

    if (parsed.hideFromNav) await _hideProviderFromNavigation(type);
    if (!mounted || request != _keyRequest) return;
    final title = integrationMeta[type]!.title;
    if (!_connectedServices.contains(title)) _connectedServices.add(title);
    _hasConfigured = true;
    AnalyticsService.integrationConnected(type.name, {'surface': 'onboarding'});
    MainPageBridge.notifyIntegrationChanged();

    if (type == IntegrationType.pikpak) await _offerPikPakRestriction();
    if (!mounted) return;
    setState(() => _keyPhase = KeyValidationPhase.idle);
    _advanceProvider();
  }

  Future<bool> _validate(
    IntegrationType type,
    String value,
    String? secondary,
  ) async {
    return switch (type) {
      IntegrationType.realDebrid => AccountService.validateAndGetUserInfo(
        value,
      ),
      IntegrationType.torbox => TorboxAccountService.validateAndGetUserInfo(
        value,
      ),
      IntegrationType.premiumize =>
        PremiumizeAccountService.validateAndGetUserInfo(value),
      IntegrationType.allDebrid =>
        AllDebridAccountService.validateAndGetUserInfo(value),
      IntegrationType.pikpak => _loginPikPak(value, secondary!),
    };
  }

  Future<bool> _loginPikPak(String email, String password) async {
    final success = await PikPakApiService.instance.login(email, password);
    if (success) await StorageService.setPikPakEnabled(true);
    return success;
  }

  Future<void> _hideProviderFromNavigation(IntegrationType type) async {
    switch (type) {
      case IntegrationType.realDebrid:
        await StorageService.setRealDebridHiddenFromNav(true);
      case IntegrationType.torbox:
        await StorageService.setTorboxHiddenFromNav(true);
      case IntegrationType.premiumize:
        await StorageService.setPremiumizeHiddenFromNav(true);
      case IntegrationType.allDebrid:
        await StorageService.setAllDebridHiddenFromNav(true);
      case IntegrationType.pikpak:
        return;
    }
  }

  Future<void> _offerPikPakRestriction() async {
    final restrict = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Restrict PikPak to one folder?'),
        content: const Text(
          'For extra privacy, Debrify can access one chosen folder instead of your whole PikPak drive. You can skip this now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose folder'),
          ),
        ],
      ),
    );
    if (restrict != true || !mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const PikPakFolderPickerDialog(),
    );
    if (result == null) return;
    await StorageService.setPikPakRestrictedFolder(
      result['folderId'] as String?,
      result['folderName'] as String?,
    );
  }

  void _goToEngines() {
    _transition(OnboardStep.engines);
    unawaited(_loadEngines());
  }

  Future<void> _loadEngines() async {
    final request = ++_engineRequest;
    setState(() {
      _loadingEngines = true;
      _engineError = null;
    });
    try {
      final engines = await _engineManager.fetchAvailableEngines();
      if (!mounted ||
          request != _engineRequest ||
          _step != OnboardStep.engines) {
        return;
      }
      setState(() {
        _engines = engines;
        _selectedEngines = engines.map((engine) => engine.id).toSet();
        _loadingEngines = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestLanding());
    } catch (error) {
      if (!mounted ||
          request != _engineRequest ||
          _step != OnboardStep.engines) {
        return;
      }
      setState(() {
        _loadingEngines = false;
        _engineError = error.toString();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestLanding());
    }
  }

  void _toggleEngine(String id) {
    setState(() {
      if (!_selectedEngines.add(id)) _selectedEngines.remove(id);
    });
  }

  void _toggleAllEngines() {
    setState(() {
      if (_selectedEngines.isEmpty) {
        _selectedEngines = _engines.map((engine) => engine.id).toSet();
      } else {
        _selectedEngines.clear();
      }
    });
  }

  Future<void> _importEngines() async {
    if (_loadingEngines || _importingEngines) return;
    final request = ++_engineImportRequest;
    setState(() => _importingEngines = true);
    _importedEngineNames = <String>[];
    final prepared = <({RemoteEngineInfo engine, String yaml})>[];
    for (final engine in _engines) {
      if (!_selectedEngines.contains(engine.id)) continue;
      try {
        final yaml = await _engineManager.downloadEngineYaml(engine.fileName);
        if (!mounted || request != _engineImportRequest) return;
        if (yaml == null) continue;
        if (widget.engineImportOverride != null) {
          final imported = await widget.engineImportOverride!(engine, yaml);
          if (!mounted || request != _engineImportRequest) return;
          if (imported) _importedEngineNames.add(engine.displayName);
        } else {
          prepared.add((engine: engine, yaml: yaml));
        }
      } catch (error) {
        debugPrint('Failed to import ${engine.id}: $error');
      }
    }

    if (prepared.isNotEmpty && widget.engineImportOverride == null) {
      final settled = Completer<void>();
      _engineTransactionSettled = settled;
      LocalEngineTransaction? transaction;
      try {
        transaction = await LocalEngineStorage.instance
            .saveEnginesAtomically(<LocalEngineWrite>[
              for (final item in prepared)
                LocalEngineWrite(
                  engineId: item.engine.id,
                  fileName: item.engine.fileName,
                  yamlContent: item.yaml,
                  displayName: item.engine.displayName,
                  icon: item.engine.icon,
                ),
            ], isCanceled: () => !mounted || request != _engineImportRequest);
        if (transaction == null) return;

        ConfigLoader().clearCache();
        await EngineRegistry.instance.reload();
        if (!mounted || request != _engineImportRequest) {
          await transaction.rollback();
          ConfigLoader().clearCache();
          await EngineRegistry.instance.reload();
          return;
        }
        transaction.commit();
        _importedEngineNames = <String>[
          for (final item in prepared) item.engine.displayName,
        ];
      } catch (error) {
        await transaction?.rollback();
        ConfigLoader().clearCache();
        try {
          await EngineRegistry.instance.reload();
        } catch (reloadError) {
          debugPrint('Failed to reload engines after rollback: $reloadError');
        }
        debugPrint('Failed to commit imported engines: $error');
      } finally {
        if (identical(_engineTransactionSettled, settled)) {
          _engineTransactionSettled = null;
        }
        if (!settled.isCompleted) settled.complete();
      }
    }
    if (!mounted || request != _engineImportRequest) return;
    if (_importedEngineNames.isNotEmpty) _hasConfigured = true;
    if (!mounted) return;
    setState(() => _importingEngines = false);
    _transition(OnboardStep.trackers);
    unawaited(_initializeTrackers());
  }

  Future<void> _initializeTrackers() async {
    final initialized = await Future.wait<Object?>([
      _trakt.initialize(),
      _simkl.initialize(),
      if (kMdblistEnabled)
        MdblistService.instance.isAuthenticated()
      else
        Future.value(false),
    ]);
    if (!mounted || _step != OnboardStep.trackers) return;
    _mdblistConnected = initialized[2] == true;
    if (_trakt.connected || _simkl.connected || _mdblistConnected) {
      _hasConfigured = true;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestLanding());
  }

  void _trackersDone() => _transition(OnboardStep.done);

  void _skipEngines() {
    _engineImportRequest++;
    _importingEngines = false;
    _transition(OnboardStep.trackers);
    unawaited(_initializeTrackers());
  }

  Future<void> _restoreBackup() async {
    if (_restoringBackup || _finishing) return;
    _restoringBackup = true;
    try {
      final ProfileBackupRestoreResult? result;
      if (widget.backupRestoreOverride != null) {
        result = await widget.backupRestoreOverride!();
      } else {
        result = await ProfileBackupFlows(
          context,
          completingOnboarding: true,
        ).restoreProfileBackup();
      }
      if (!mounted || result == null) return;
      _hasConfigured = true;
      MainPageBridge.notifyIntegrationChanged();
      final graphReport = result.graphReport;
      final shouldHandoff =
          graphReport != null &&
          result.authorizingProfileId == ProfileBootstrap.freshAdminId;
      await _finish(
        afterSetupComplete: shouldHandoff
            ? () => _handoffRestoredGraph(graphReport)
            : null,
      );
    } finally {
      _restoringBackup = false;
    }
  }

  Future<void> _handoffRestoredGraph(ProfileGraphRestoreReport report) async {
    try {
      final override = widget.backupHandoffOverride;
      if (override != null) {
        await override(report);
      } else {
        await RemoteCommandRouter().handoffImportedAdminForOnboarding(report);
      }
    } catch (error, stack) {
      // The graph is already durable. A failed handoff keeps the bootstrap
      // recovery Admin active; it must not make the completed restore look as
      // though nothing was imported or invite a duplicate restore.
      debugPrint(
        'InitialSetupFlow: imported profiles but could not hand off '
        'authority — $error\n$stack',
      );
    }
  }

  Future<void> _enterImport() async {
    final attempt = ++_importAttempt;
    _transferComplete = false;
    _hadImportConnection = false;
    _receivedItemCount = 0;
    _lastReceivedLabel = null;
    _chunkInFlightLabel = null;
    _receiverError = null;
    _transition(OnboardStep.importing);
    _attachImportListeners();
    try {
      var name = await StorageService.getRemoteTvDeviceName();
      name ??= await PlatformUtil.getDeviceName();
      name ??= _isTelevision ? 'Debrify TV' : 'This device';
      if (!mounted ||
          attempt != _importAttempt ||
          _step != OnboardStep.importing) {
        return;
      }
      setState(() => _advertisedName = name!);
      final lease = await RemoteControlState().ensureReceiverMode(name);
      if (!mounted ||
          attempt != _importAttempt ||
          _step != OnboardStep.importing) {
        await lease.release();
        return;
      }
      final previous = _importLease;
      _importLease = lease;
      if (previous != null) await previous.release();
    } catch (error) {
      if (!mounted ||
          attempt != _importAttempt ||
          _step != OnboardStep.importing) {
        return;
      }
      setState(() {
        _receiverError =
            'Could not make this device discoverable. Check Remote Control in Settings, then try again.';
      });
      debugPrint('Onboarding receiver start failed: $error');
    }
  }

  Future<void> _leaveImport() async {
    _importAttempt++;
    _detachImportListeners();
    final lease = _importLease;
    _importLease = null;
    if (lease != null) await lease.release();
  }

  void _attachImportListeners() {
    if (_importListenersAttached) return;
    _importListenersAttached = true;
    RemoteControlState().addListener(_remoteStateChanged);
    RemoteCommandRouter().addHandler(_remoteCommand);
  }

  void _detachImportListeners() {
    if (!_importListenersAttached) return;
    _importListenersAttached = false;
    RemoteControlState().removeListener(_remoteStateChanged);
    RemoteCommandRouter().removeHandler(_remoteCommand);
  }

  void _remoteStateChanged() {
    if (!mounted || _step != OnboardStep.importing) return;
    if (RemoteControlState().isConnected) _hadImportConnection = true;
    setState(() {});
  }

  void _remoteCommand(String action, String command, String? data) {
    if (!mounted || _step != OnboardStep.importing) return;
    if (action == RemoteAction.config && command == ConfigCommand.complete) {
      setState(() => _transferComplete = true);
      return;
    }
    String? label;
    if (action == RemoteAction.addon && command == AddonCommand.install) {
      label = 'Stremio addon';
    } else if (action == RemoteAction.config) {
      label = _configLabel(command, data);
    }
    if (label == null) return;
    setState(() {
      if (command == ConfigCommand.debrifyChannelStart) {
        _chunkInFlightLabel = label;
        _receivedItemCount++;
      } else if (_chunkInFlightLabel == label) {
        // The start packet already counted this logical payload. Reassembly
        // replays its real command through the same observer; do not display
        // one all-profile transfer (or IPTV payload) as two received items.
        _chunkInFlightLabel = null;
      } else {
        _receivedItemCount++;
      }
      _lastReceivedLabel = label;
    });
  }

  String? _configLabel(String command, String? data) {
    return switch (command) {
      ConfigCommand.realDebrid => 'Real-Debrid',
      ConfigCommand.torbox => 'TorBox',
      ConfigCommand.premiumize => 'Premiumize',
      ConfigCommand.allDebrid => 'AllDebrid',
      ConfigCommand.pikpak => 'PikPak',
      ConfigCommand.trakt => 'Trakt',
      ConfigCommand.simkl => 'Simkl',
      ConfigCommand.searchEngines => 'Search engines',
      ConfigCommand.webDav => 'WebDAV servers',
      ConfigCommand.indexerManagers => 'Indexer managers',
      ConfigCommand.iptvPlaylists => 'IPTV providers',
      ConfigCommand.iptvFavorites => 'IPTV favorites',
      ConfigCommand.iptvLists => 'IPTV lists',
      ConfigCommand.streamBadges => 'Stream badges',
      ConfigCommand.debrifyChannel => 'TV channel',
      ConfigCommand.debrifyChannelStart => _chunkLabel(data),
      ConfigCommand.profileGraph => 'All profiles',
      _ => null,
    };
  }

  String _chunkLabel(String? data) {
    if (data == null) return 'TV channel';
    try {
      final decoded = jsonDecode(data);
      final kind = decoded is Map ? decoded['kind'] as String? : null;
      return _configLabel(kind ?? ConfigCommand.debrifyChannel, null) ??
          'TV channel';
    } catch (_) {
      return 'TV channel';
    }
  }

  Future<void> _leave() async {
    if (_finishing) return;
    _finishing = true;
    MainPageBridge.queuePostSetupSnackBar(
      'Setup skipped. Connect services any time in Settings › Services.',
    );
    await StorageService.setInitialSetupComplete(true);
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _finish({Future<void> Function()? afterSetupComplete}) async {
    if (_finishing) return;
    _finishing = true;
    await StorageService.setInitialSetupComplete(true);
    await afterSetupComplete?.call();
    if (!mounted) return;
    Navigator.of(context).pop(_hasConfigured);
  }

  OnboardSummary get _summary => OnboardSummary(
    services: List<String>.unmodifiable(_connectedServices),
    engines: List<String>.unmodifiable(_importedEngineNames),
    trackers: <String>[
      if (_trakt.connected) 'Trakt',
      if (_simkl.connected) 'Simkl',
      if (_mdblistConnected) 'MDBList',
    ],
  );

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_keyboardSession.ownsBack) unawaited(_handleBack());
      },
      child: FocusTraversalGroup(
        descendantsAreFocusable: true,
        policy: WidgetOrderTraversalPolicy(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = resolveOnboardLayout(
              isTelevision: _isTelevision,
              size: constraints.biggest,
            );
            return _buildStep(context, layout);
          },
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, OnboardLayout layout) {
    late final String eyebrow;
    late final String title;
    late final String subtitle;
    late final Widget content;
    Widget? footer;
    var keyStep = false;

    switch (_step) {
      case OnboardStep.mode:
        eyebrow = 'Welcome';
        title = "Let's set\nDebrify up.";
        subtitle =
            'About two minutes. Every step can be skipped, and everything lives in Settings afterwards.';
        content = ModeStep(
          focusController: _focus,
          onSetupHere: _chooseSetupHere,
          onImport: () => unawaited(_enterImport()),
          onRestore: PlatformUtil.isTvOS
              ? null
              : () => unawaited(_restoreBackup()),
          onSkip: () => unawaited(_leave()),
        );
      case OnboardStep.services:
        eyebrow = 'Step 1 of 4';
        title = 'Which services\ndo you have?';
        subtitle =
            'Pick any you already pay for. Debrify uses them to turn a link into a stream.';
        final step = ServicesStep(
          layout: layout,
          focusController: _focus,
          selection: _serviceSelection,
          onToggle: _toggleService,
          onNone: _goToEngines,
          onContinue: () => unawaited(_startSelectedServices()),
        );
        content = step;
        footer = step.buildFooter(context);
      case OnboardStep.key:
        keyStep = true;
        final type = _providerFlow[_providerIndex];
        final meta = integrationMeta[type]!;
        eyebrow = 'Step 1 of 4';
        title = meta.title;
        subtitle = 'Connect this service securely.';
        final step = KeyStep(
          layout: layout,
          isTelevision: _isTelevision,
          focusController: _focus,
          session: _keyboardSession,
          meta: meta,
          index: _providerIndex,
          total: _providerFlow.length,
          controller: _controllers[type]!,
          pikpakPasswordController: _pikpakPassword,
          phase: _keyPhase,
          clipboardCandidate: _clipboardCandidate,
          error: _keyError,
          onChanged: (_) {
            if (mounted && _keyPhase != KeyValidationPhase.idle) {
              setState(() {
                _keyRequest++;
                _keyPhase = KeyValidationPhase.idle;
                _keyError = null;
              });
            } else if (mounted) {
              setState(() {});
            }
          },
          onConnect: () => unawaited(_submitProvider()),
          onSkip: _skipProvider,
          onImport: () => unawaited(_enterImport()),
        );
        content = step;
        if (!_isTelevision) footer = step.buildFooter(context);
      case OnboardStep.engines:
        eyebrow = 'Step 2 of 4';
        title = 'Where should\nwe search?';
        subtitle =
            'These are the sources Debrify searches. They all start on; turn off any you do not want.';
        final step = EnginesStep(
          layout: layout,
          focusController: _focus,
          engines: _engines,
          selected: _selectedEngines,
          loading: _loadingEngines,
          importing: _importingEngines,
          error: _engineError,
          onToggle: _toggleEngine,
          onTurnAllOff: _toggleAllEngines,
          onContinue: () => unawaited(_importEngines()),
          onSkip: _skipEngines,
          onRetry: () => unawaited(_loadEngines()),
        );
        content = step;
        footer = step.buildFooter(context);
      case OnboardStep.trackers:
        eyebrow = 'Step 3 of 4';
        title = 'Keep your\nprogress synced.';
        // "Both" only holds while Trakt and Simkl are the whole list. The
        // step's own footer already switches on [kMdblistEnabled]; this
        // sentence has to move with it or it contradicts the cards below it.
        subtitle =
            'A tracker remembers what you watched across devices. '
            '${kMdblistEnabled ? 'All are optional.' : 'Both are optional.'}';
        final step = TrackersStep(
          layout: layout,
          focusController: _focus,
          trakt: _trakt,
          simkl: _simkl,
          mdblistConnected: _mdblistConnected,
          onMdblistConnected: () {
            if (!mounted) return;
            setState(() {
              _mdblistConnected = true;
              _hasConfigured = true;
            });
          },
          onDone: _trackersDone,
        );
        content = step;
        footer = step.buildFooter(context);
      case OnboardStep.importing:
        eyebrow = 'Import';
        title = 'Send it\nfrom another device.';
        subtitle =
            'This device is visible on your network. Follow these three steps on the other device.';
        final step = ImportStep(
          layout: layout,
          focusController: _focus,
          deviceName: _advertisedName,
          connected: RemoteControlState().isConnected,
          connectionDropped:
              _hadImportConnection && !RemoteControlState().isConnected,
          receivedCount: _receivedItemCount,
          lastReceived: _lastReceivedLabel,
          transferComplete: _transferComplete,
          startError: _receiverError,
          onSetupHere: () => unawaited(_handleBack()),
        );
        content = step;
        footer = step.buildFooter(context);
      case OnboardStep.done:
        eyebrow = 'All set';
        title = "You're ready\nto watch.";
        subtitle =
            'Anything you skipped is one screen away in Settings › Services.';
        final step = DoneStep(
          focusController: _focus,
          summary: _summary,
          onStart: () => unawaited(_finish()),
        );
        content = step;
        footer = step.buildFooter(context);
    }

    return OnboardingStage(
      key: ValueKey(_step),
      step: _step,
      layout: layout,
      focusController: _focus,
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      onBack: () => unawaited(_handleBack()),
      content: content,
      footer: footer,
      keyStep: keyStep,
      backEnabled:
          _step != OnboardStep.key ||
          _keyPhase != KeyValidationPhase.validating,
    );
  }
}
