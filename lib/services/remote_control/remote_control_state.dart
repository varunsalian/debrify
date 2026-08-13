import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'remote_constants.dart';
import 'remote_command_router.dart';
import 'remote_pairing_store.dart';
import 'remote_session.dart';
import 'udp_discovery_service.dart';
import 'udp_command_service.dart';

/// Connection state enum
enum RemoteConnectionState { disconnected, scanning, connecting, connected }

enum _RemoteRole { stopped, receiver, sender }

/// A caller-owned claim on receiver mode. Releasing the final claim restores
/// the role that was active before the first claim was acquired.
class ReceiverLease {
  ReceiverLease._(this._owner, this._id);

  final RemoteControlState _owner;
  final int _id;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _owner._releaseReceiverLease(_id);
  }
}

/// State manager for remote control functionality
class RemoteControlState extends ChangeNotifier {
  // Singleton
  static final RemoteControlState _instance = RemoteControlState._internal();
  factory RemoteControlState() => _instance;
  RemoteControlState._internal();

  // Services
  UdpDiscoveryService? _discoveryService;
  UdpCommandService? _commandService;

  // State
  RemoteConnectionState _connectionState = RemoteConnectionState.disconnected;
  DiscoveredDevice? _connectedDevice;
  List<DiscoveredDevice> _discoveredDevices = [];
  String? _lastError;
  bool _isTv = false;
  String _deviceId = '';
  _RemoteRole _role = _RemoteRole.stopped;
  String? _receiverName;

  Future<void> _roleQueue = Future<void>.value();
  int _nextLeaseId = 0;
  final Set<int> _receiverLeases = <int>{};
  _RemoteRole? _roleBeforeLeases;
  String? _receiverNameBeforeLeases;

  @visibleForTesting
  Future<void> Function(String name)? debugReceiverStarter;
  @visibleForTesting
  Future<void> Function()? debugSenderStarter;
  @visibleForTesting
  Future<void> Function()? debugRoleStopper;
  bool _debugReceiverBound = false;

  // Callbacks for TV mode
  void Function(String action, String command, String? data)? onCommandReceived;

  /// Context-aware variant. When set it takes precedence over
  /// [onCommandReceived] and additionally learns whether the command arrived
  /// encrypted and over an authorized (paired) session — the router uses this
  /// to gate credential writes.
  void Function(String action, String command, String? data,
      RemoteCommandContext context)? onCommandReceivedWithContext;

  /// Pair-action traffic (requests/challenges/proofs/acks) with its session.
  /// Receiver side: the router drives the pairing gate. Sender side: the
  /// pairing sheet awaits challenge/ok/err responses.
  void Function(RemoteSession session, String command, String? data)?
      onPairMessage;

  // --- Protocol v2 session state -------------------------------------------
  RemoteSessionManager? _sessionManager;
  PairingGate? _pairingGate;
  Timer? _sessionTimer;
  final Map<String, ({String ip, int port})> _sessionPeers = {};
  final Map<String, RemoteSession> _sessionByIp = {};
  final Map<String, Completer<RemoteSession?>> _pendingHandshakes = {};
  final Map<String, Completer<void>> _pendingPongs = {};
  final Set<String> _rememberedFingerprints = <String>{};
  int _pingSeq = 0;

  // Getters
  RemoteConnectionState get connectionState => _connectionState;
  DiscoveredDevice? get connectedDevice => _connectedDevice;
  List<DiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  String? get lastError => _lastError;
  bool get isConnected => _connectionState == RemoteConnectionState.connected;
  bool get isScanning => _connectionState == RemoteConnectionState.scanning;
  bool get isTv => _isTv;
  bool get hasDevices => _discoveredDevices.isNotEmpty;

  /// Initialize receiver mode - start listening for incoming commands.
  /// Any device can call this; it's also the default for Android TV at boot.
  Future<void> startTvListener(String deviceName) =>
      _enqueueRoleChange(() => _switchToReceiverRaw(deviceName));

  Future<void> _startTvListenerRaw(String deviceName) async {
    if (_role == _RemoteRole.receiver &&
        _receiverName == deviceName &&
        (_debugReceiverBound ||
            (_discoveryService != null && _commandService != null))) {
      return;
    }
    _isTv = true;
    _receiverName = deviceName;
    _deviceId = _generateDeviceId();

    // Wire dispatch into the command router by default so callers don't have
    // to remember to set this up. main.dart used to do this only for TV;
    // having it here means switchToReceiverMode on phones/desktops also works.
    onCommandReceived ??= (action, command, data) {
      RemoteCommandRouter().dispatchCommand(action, command, data);
    };
    // Context-aware path (takes precedence): the router needs to know whether
    // a command arrived over an authorized session to gate credential writes.
    onCommandReceivedWithContext ??= (action, command, data, context) {
      RemoteCommandRouter()
          .dispatchCommand(action, command, data, context: context);
    };
    // Receiver-side pairing traffic drives the on-screen code gate.
    onPairMessage ??= (session, command, data) {
      unawaited(
          RemoteCommandRouter().handlePairMessage(this, session, command, data));
    };

    debugPrint(
      'RemoteControlState: Starting receiver listener as "$deviceName"',
    );

    final testStarter = debugReceiverStarter;
    if (testStarter != null) {
      await testStarter(deviceName);
      _debugReceiverBound = true;
      _role = _RemoteRole.receiver;
      _connectionState = RemoteConnectionState.disconnected;
      notifyListeners();
      return;
    }

    // Start discovery service (to respond to discovery requests)
    _discoveryService = UdpDiscoveryService(
      deviceId: _deviceId,
      isTv: true,
      tvDeviceName: deviceName,
    );
    await _discoveryService!.start();
    // Advertise our static key once loaded so senders can pin this receiver.
    unawaited(RemotePairingStore.publicKeyBytes().then((key) {
      _discoveryService?.advertisedStaticKey = base64Encode(key);
    }).catchError((Object e) {
      debugPrint('RemoteControlState: could not load static key: $e');
    }));

    // Start command service (to receive commands)
    _commandService = UdpCommandService(isTv: true);
    _commandService!.onCommandReceived = _handleCommand;
    _commandService!.onHeartbeatReceived = () {
      if (_connectionState != RemoteConnectionState.connected) {
        _connectionState = RemoteConnectionState.connected;
        notifyListeners();
      }
    };
    _commandService!.onConnectionLost = () {
      _connectionState = RemoteConnectionState.disconnected;
      _connectedDevice = null;
      notifyListeners();
    };
    await _commandService!.start();
    _wireSession(_commandService!);

    _role = _RemoteRole.receiver;
    _connectionState = RemoteConnectionState.disconnected;
    notifyListeners();
  }

  /// Initialize for Mobile mode - start scanning for TVs
  Future<void> startMobileDiscovery() => _enqueueRoleChange(() async {
    if (_role == _RemoteRole.sender && isScanning) {
      debugPrint('RemoteControlState: Already scanning');
      return;
    }
    await _switchToSenderRaw();
  });

  Future<void> _startMobileDiscoveryRaw() async {
    if (_connectionState == RemoteConnectionState.scanning) {
      debugPrint('RemoteControlState: Already scanning');
      return;
    }

    _isTv = false;
    _receiverName = null;
    _deviceId = _generateDeviceId();
    _discoveredDevices = [];

    debugPrint('RemoteControlState: Starting mobile discovery');

    _connectionState = RemoteConnectionState.scanning;
    _lastError = null;
    notifyListeners();

    final testStarter = debugSenderStarter;
    if (testStarter != null) {
      await testStarter();
      _role = _RemoteRole.sender;
      return;
    }

    // Start discovery service
    _discoveryService = UdpDiscoveryService(deviceId: _deviceId, isTv: false);

    _discoveryService!.onDeviceDiscovered = _handleDeviceDiscovered;
    _discoveryService!.onDevicesUpdated = (devices) {
      _discoveredDevices = devices;
      notifyListeners();
    };
    _discoveryService!.onDiscoveryComplete = () {
      debugPrint('RemoteControlState: Discovery complete');
      // Only change state if not already connected
      if (_connectionState == RemoteConnectionState.scanning) {
        if (_discoveredDevices.isEmpty) {
          _connectionState = RemoteConnectionState.disconnected;
          _lastError = 'No TV found on the network';
        } else {
          // Stay in disconnected but with devices available
          _connectionState = RemoteConnectionState.disconnected;
        }
        notifyListeners();
      }
    };
    _discoveryService!.onError = (error) {
      _lastError = error;
      notifyListeners();
    };

    await _discoveryService!.start();
    _role = _RemoteRole.sender;
  }

  /// Stop all services
  Future<void> stop() => _enqueueRoleChange(_stopRaw);

  Future<void> _stopRaw() async {
    final testStopper = debugRoleStopper;
    if (testStopper != null) {
      await testStopper();
    } else {
      await _discoveryService?.stop();
      await _commandService?.stop();
    }
    _discoveryService = null;
    _commandService = null;
    _teardownSessions();
    _connectionState = RemoteConnectionState.disconnected;
    _connectedDevice = null;
    _discoveredDevices = [];
    _role = _RemoteRole.stopped;
    _receiverName = null;
    _debugReceiverBound = false;
    notifyListeners();
  }

  Future<void> _switchToReceiverRaw(String deviceName) async {
    if (_role == _RemoteRole.receiver &&
        _receiverName == deviceName &&
        (_debugReceiverBound ||
            (_discoveryService != null && _commandService != null))) {
      return;
    }
    if (_role != _RemoteRole.stopped ||
        _discoveryService != null ||
        _commandService != null ||
        _debugReceiverBound) {
      await _stopRaw();
    }
    try {
      await _startTvListenerRaw(deviceName);
    } catch (_) {
      await _stopRaw();
      rethrow;
    }
  }

  Future<void> _switchToSenderRaw() async {
    if (_role != _RemoteRole.stopped ||
        _discoveryService != null ||
        _commandService != null ||
        _debugReceiverBound) {
      await _stopRaw();
    }
    try {
      await _startMobileDiscoveryRaw();
    } catch (_) {
      await _stopRaw();
      rethrow;
    }
  }

  Future<T> _enqueueRoleChange<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _roleQueue = _roleQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Ensures receiver mode is fully bound and returns a distinct caller lease.
  /// Starts, restores, and stops share one queue so backing out cannot race a
  /// pending socket bind.
  Future<ReceiverLease> ensureReceiverMode(String deviceName) =>
      _enqueueRoleChange(() async {
        final id = ++_nextLeaseId;
        if (_receiverLeases.isEmpty) {
          _roleBeforeLeases = _role;
          _receiverNameBeforeLeases = _receiverName;
        }
        _receiverLeases.add(id);
        try {
          await _switchToReceiverRaw(deviceName);
        } catch (error, stackTrace) {
          _receiverLeases.remove(id);
          if (_receiverLeases.isEmpty) {
            final previous = _roleBeforeLeases ?? _RemoteRole.stopped;
            final previousName = _receiverNameBeforeLeases;
            _roleBeforeLeases = null;
            _receiverNameBeforeLeases = null;
            try {
              switch (previous) {
                case _RemoteRole.receiver:
                  if (previousName != null) {
                    await _switchToReceiverRaw(previousName);
                  }
                case _RemoteRole.sender:
                  await _switchToSenderRaw();
                case _RemoteRole.stopped:
                  await _stopRaw();
              }
            } catch (restoreError) {
              debugPrint(
                'RemoteControlState: Could not restore role after a failed '
                'receiver lease: $restoreError',
              );
            }
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
        return ReceiverLease._(this, id);
      });

  Future<void> _releaseReceiverLease(int id) => _enqueueRoleChange(() async {
    if (!_receiverLeases.remove(id)) return;
    if (_receiverLeases.isNotEmpty) return;

    final previous = _roleBeforeLeases ?? _RemoteRole.stopped;
    final previousReceiverName = _receiverNameBeforeLeases;
    _roleBeforeLeases = null;
    _receiverNameBeforeLeases = null;
    switch (previous) {
      case _RemoteRole.receiver:
        if (previousReceiverName != null &&
            previousReceiverName != _receiverName) {
          await _switchToReceiverRaw(previousReceiverName);
        }
        return;
      case _RemoteRole.sender:
        await _switchToSenderRaw();
        return;
      case _RemoteRole.stopped:
        await _stopRaw();
        return;
    }
  });

  /// Connect to a device by manually entered IP (e.g. Tailscale / VPN address).
  /// Bypasses UDP broadcast discovery — useful when the receiver is reachable
  /// over a mesh VPN but not on the same Wi-Fi subnet.
  Future<void> connectToManualIp(String ip, {String? deviceName}) async {
    final trimmed = ip.trim();
    if (trimmed.isEmpty) return;
    final device = DiscoveredDevice(
      deviceName: deviceName?.trim().isNotEmpty == true
          ? deviceName!.trim()
          : trimmed,
      ip: trimmed,
    );
    await connectToDevice(device);
  }

  /// Connect to a specific TV (for mobile)
  Future<void> connectToDevice(DiscoveredDevice device) async {
    if (_isTv) return;

    // If already connected to this device, do nothing
    if (_connectedDevice?.ip == device.ip && isConnected) {
      debugPrint(
        'RemoteControlState: Already connected to ${device.deviceName}',
      );
      return;
    }

    debugPrint('RemoteControlState: Connecting to ${device.deviceName}');

    _connectionState = RemoteConnectionState.connecting;
    _connectedDevice = device;
    notifyListeners();

    // Stop existing command service if switching devices
    await _commandService?.stop();
    _commandService = null;

    // Stop discovery (we've selected a device)
    await _discoveryService?.stop();
    _discoveryService = null;

    // Start command service
    _commandService = UdpCommandService(isTv: false);
    _commandService!.onHeartbeatReceived = () {
      if (_connectionState != RemoteConnectionState.connected) {
        _connectionState = RemoteConnectionState.connected;
        notifyListeners();
      }
    };
    _commandService!.onConnectionLost = () {
      debugPrint('RemoteControlState: Connection lost');
      _connectionState = RemoteConnectionState.disconnected;
      notifyListeners();
    };

    await _commandService!.start(targetIp: device.ip);
    _wireSession(_commandService!);

    // Opportunistic session: harmless against a v1 TV (hs1 is silently
    // dropped); against a v2 TV every subsequent keypress rides encrypted
    // and the credential flows find a session already warm.
    unawaited(ensureEncryptedSession(device.ip));

    // Mark as connected after a short delay to allow heartbeat exchange
    // (real heartbeats now arrive from v2 peers — this stays as the v1
    // fallback).
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_connectionState == RemoteConnectionState.connecting) {
        _connectionState = RemoteConnectionState.connected;
        notifyListeners();
      }
    });
  }

  /// Send [command] to the connected device — encrypted when a session
  /// exists, plaintext otherwise (v1 TVs). Credential-bearing actions
  /// (config/addon) never take the plaintext branch; benign remote-control
  /// traffic keeps working against old receivers.
  void _sendOpportunistic(RemoteCommand command) {
    final sensitive = command.action == RemoteAction.config ||
        command.action == RemoteAction.addon;
    final ip = _connectedDevice?.ip;
    final session = ip == null ? null : _sessionByIp[ip];
    if (session != null) {
      unawaited(sendEncryptedCommand(session, command).then((sent) {
        if (!sent && !sensitive) _commandService?.sendCommand(command);
      }));
      return;
    }
    if (sensitive) {
      debugPrint('RemoteControlState: refusing plaintext ${command.action} — '
          'no session with $ip');
      return;
    }
    _commandService?.sendCommand(command);
  }

  /// Send a navigation command (sender role)
  void sendNavigateCommand(String direction) {
    if (!isConnected || _isTv) return;
    _sendOpportunistic(RemoteCommand.navigate(direction));
  }

  /// Send a media command (sender role)
  void sendMediaCommand(String command) {
    if (!isConnected || _isTv) return;
    _sendOpportunistic(RemoteCommand.media(command));
  }

  /// Send an addon command (sender role)
  void sendAddonCommand(String command, {String? manifestUrl}) {
    if (!isConnected || _isTv) return;
    _sendOpportunistic(RemoteCommand.addon(command, manifestUrl: manifestUrl));
  }

  /// Send an addon command to a specific device by IP (doesn't require connection)
  ///
  /// Same no-plaintext rule as config: manifest URLs embed debrid keys.
  Future<bool> sendAddonCommandToDevice(
    String command,
    String targetIp, {
    String? manifestUrl,
  }) async {
    final cmd = RemoteCommand.addon(command, manifestUrl: manifestUrl);
    final session = _sessionByIp[targetIp];
    if (session == null) {
      debugPrint('RemoteControlState: refusing plaintext addon send — '
          'no session with $targetIp');
      return false;
    }
    return sendEncryptedCommand(session, cmd);
  }

  /// Send a config command to a specific device by IP (doesn't require connection)
  ///
  /// [plaintextTransport] is for chunk-transfer start/piece packets: their
  /// payload is ALREADY session-sealed ciphertext, and wrapping the ~1400-byte
  /// packet in a second base64-inflating envelope would blow the single-
  /// fragment UDP budget.
  ///
  /// Non-transport config NEVER falls back to plaintext: if the session aged
  /// out between the preflight and this item, the send FAILS rather than
  /// quietly handing credentials to any passive LAN observer. (This is the
  /// enforcement point for the block policy — the UI preflight is just the
  /// messaging.)
  Future<bool> sendConfigCommandToDevice(
    String configType,
    String targetIp, {
    String? configData,
    bool plaintextTransport = false,
  }) async {
    final cmd = RemoteCommand.config(configType, configData: configData);
    if (plaintextTransport) {
      // Prefer the persistent socket: hundreds of chunk packets from
      // one-shot temp sockets would each arrive at the receiver from a
      // different (instantly dead) source port, and a receiver that replies
      // toward the latest source would lose the phone's real endpoint.
      final service = _commandService;
      if (service != null &&
          service.isRunning &&
          service.sendRaw(cmd.toJson(), targetIp)) {
        return true;
      }
      return await UdpCommandService.sendCommandToIp(cmd, targetIp);
    }
    final session = _sessionByIp[targetIp];
    if (session == null) {
      debugPrint(
          'RemoteControlState: refusing plaintext config "$configType" — '
          'no session with $targetIp');
      return false;
    }
    return sendEncryptedCommand(session, cmd);
  }

  /// Send a text input command (sender role)
  void sendTextCommand(String command, {String? text}) {
    if (!isConnected || _isTv) return;
    _sendOpportunistic(RemoteCommand.text(command, text: text));
  }

  /// Switch this device into RECEIVER mode (listens for incoming commands).
  /// Stops any existing sender/receiver state first. Safe to call from any platform.
  Future<void> switchToReceiverMode(String deviceName) async {
    await _enqueueRoleChange(() => _switchToReceiverRaw(deviceName));
  }

  /// Switch this device into SENDER mode (scans for receivers and sends commands).
  /// Stops any existing sender/receiver state first.
  Future<void> switchToSenderMode() async {
    await _enqueueRoleChange(_switchToSenderRaw);
  }

  /// Restart scanning (for mobile)
  Future<void> rescan() async {
    await _enqueueRoleChange(_switchToSenderRaw);
  }

  /// Test-only singleton reset. Production [stop] deliberately keeps [isTv]
  /// semantics unchanged; tests need a hermetic way to clear process state.
  @visibleForTesting
  Future<void> debugResetForTesting() async {
    await _enqueueRoleChange(() async {
      await _stopRaw();
      _isTv = false;
      _receiverLeases.clear();
      _roleBeforeLeases = null;
      _receiverNameBeforeLeases = null;
      _nextLeaseId = 0;
      onCommandReceived = null;
    });
    debugReceiverStarter = null;
    debugSenderStarter = null;
    debugRoleStopper = null;
  }

  @visibleForTesting
  String get debugRole => _role.name;

  @visibleForTesting
  int get debugReceiverLeaseCount => _receiverLeases.length;

  /// Disconnect from current device (for mobile)
  Future<void> disconnect() async {
    await _commandService?.stop();
    _commandService = null;
    _teardownSessions();
    _connectionState = RemoteConnectionState.disconnected;
    _connectedDevice = null;
    notifyListeners();
  }

  void _handleDeviceDiscovered(DiscoveredDevice device) {
    debugPrint('RemoteControlState: Device discovered: $device');
    // Don't auto-connect - let user choose from list
    // The devices list is updated via onDevicesUpdated callback
  }

  void _handleCommand(RemoteCommand command, String sourceIp) {
    if (command.command != ConfigCommand.debrifyChannelChunk) {
      debugPrint('RemoteControlState: Command received: $command');
    }
    _dispatch(
      command.action,
      command.command,
      command.data,
      RemoteCommandContext(
        encrypted: false,
        authorized: false,
        sourceIp: sourceIp,
      ),
    );
  }

  void _dispatch(String action, String command, String? data,
      RemoteCommandContext context) {
    final contextual = onCommandReceivedWithContext;
    if (contextual != null) {
      contextual(action, command, data, context);
    } else {
      onCommandReceived?.call(action, command, data);
    }
  }

  String _generateDeviceId() {
    final random = Random();
    return 'device_${random.nextInt(999999).toString().padLeft(6, '0')}';
  }

  // ==========================================================================
  // Protocol v2: encrypted sessions
  // ==========================================================================

  /// The session manager for this role instance (created on wiring).
  RemoteSessionManager? get sessionManager => _sessionManager;

  /// The pairing gate (receiver side). UI layers listen to this to show the
  /// on-screen code.
  PairingGate? get pairingGate => _pairingGate;

  /// The established session for [ip], if any.
  RemoteSession? sessionFor(String ip) => _sessionByIp[ip];

  void _wireSession(UdpCommandService service) {
    _sessionManager ??= RemoteSessionManager(
      loadStaticKeyPair: RemotePairingStore.loadOrCreateKeypair,
      deviceName: () => _receiverName ?? 'Debrify',
    );
    _pairingGate ??= PairingGate(isRemembered: _rememberedFingerprints.contains);
    service.onSessionMessage = (json, address, port) {
      unawaited(_onSessionMessage(service, json, address.address, port));
    };
    _sessionTimer ??= Timer.periodic(const Duration(milliseconds: 400), (_) {
      final manager = _sessionManager;
      final commandService = _commandService;
      if (manager == null || commandService == null) return;
      for (final message in manager.tick()) {
        final peer = _sessionPeers[message['sid']];
        if (peer != null) {
          commandService.sendRaw(message, peer.ip, port: peer.port);
        }
      }
      _pairingGate?.tick();
      _sessionByIp.removeWhere(
          (_, session) => !manager.sessions.containsKey(session.sidB64));
      // Endpoints die with whatever tracked their sid (session, pending
      // handshake) — this keeps the map bounded on the always-on listener.
      _sessionPeers.removeWhere((sid, _) => !manager.knowsSid(sid));
    });
    unawaited(refreshRememberedPeers());
  }

  /// Reload the remembered-phone fingerprints the pairing gate consults.
  Future<void> refreshRememberedPeers() async {
    try {
      final paired = await RemotePairingStore.listPaired();
      _rememberedFingerprints
        ..clear()
        ..addAll(paired.map((d) => d.fingerprint));
    } catch (e) {
      debugPrint('RemoteControlState: could not load paired devices: $e');
    }
  }

  Future<void> _onSessionMessage(UdpCommandService service,
      Map<String, dynamic> json, String ip, int port) async {
    final manager = _sessionManager;
    if (manager == null) return;
    final type = json['type'] as String?;
    final sid = json['sid'];

    if (type == RemoteMessageType.ecmd) {
      final opened = await manager.openCommand(json);
      if (opened.serr != null) {
        service.sendRaw(opened.serr!, ip, port: port);
        return;
      }
      final command = opened.command;
      final session = opened.session;
      if (command == null || session == null) return;
      // Endpoint recorded only AFTER the envelope authenticated — a spoofed
      // sid must not redirect replies. The service-level cache (used by
      // heartbeats and plaintext sends) learns it here too, and only here.
      _sessionPeers[session.sidB64] = (ip: ip, port: port);
      service.notePeerEndpoint(ip, port);
      _sessionByIp[ip] = session;
      _dispatchDecrypted(service, session, command, ip, port);
      return;
    }

    if (type == RemoteMessageType.serr) {
      // Advisory and unauthenticated: never tear a session down on its word
      // alone — the next ensureEncryptedSession() probes with a ping and
      // re-handshakes only if that fails.
      debugPrint('RemoteControlState: peer reports unknown session');
      return;
    }

    final result = await manager.handle(json);
    // Cache the endpoint only when the manager ACCEPTED the message (it
    // produced a reply or a session). Merely knowing the sid is not enough:
    // session IDs cross the wire in the clear, so a LAN host could replay one
    // inside a malformed handshake and redirect our replies to itself.
    final accepted = result.outgoing.isNotEmpty || result.established != null;
    if (sid is String && accepted && manager.knowsSid(sid)) {
      _sessionPeers[sid] = (ip: ip, port: port);
      service.notePeerEndpoint(ip, port);
    }
    for (final message in result.outgoing) {
      service.sendRaw(message, ip, port: port);
    }
    final established = result.established;
    if (established != null) {
      _sessionByIp[ip] = established;
      _sessionPeers[established.sidB64] = (ip: ip, port: port);
      _pendingHandshakes.remove(established.sidB64)?.complete(established);
      notifyListeners();
    }
  }

  void _dispatchDecrypted(UdpCommandService service, RemoteSession session,
      Map<String, dynamic> command, String ip, int port) {
    final action = command['action'] as String? ?? '';
    final cmd = command['command'] as String? ?? '';
    final data = command['data'] as String?;

    if (action == RemoteAction.sys) {
      if (cmd == SysCommand.ping) {
        unawaited(_sendOverSession(
            session, RemoteCommand(action: RemoteAction.sys, command: SysCommand.pong, data: data)));
      } else if (cmd == SysCommand.pong && data != null) {
        _pendingPongs.remove(data)?.complete();
      }
      return;
    }
    if (action == RemoteAction.pair) {
      onPairMessage?.call(session, cmd, data);
      return;
    }
    if ((action == RemoteAction.config || action == RemoteAction.addon) &&
        !session.authorized) {
      // A remembered phone proved possession of its static key during the
      // handshake (triple-DH), so the stored pairing carries over silently.
      if (kRememberPairedSenders &&
          _rememberedFingerprints.contains(session.peerFingerprint)) {
        session.authorized = true;
        RemoteCommandRouter().notifyRememberedAutoAuth(session.peerName);
        unawaited(RemotePairingStore.touchPeer(session.peerFingerprint));
      } else {
        // v2 senders always pair first — reaching this is a race or a bug,
        // and the reply tells them which gate they missed.
        unawaited(_sendOverSession(
          session,
          RemoteCommand(
              action: RemoteAction.pair,
              command: PairCommand.err,
              data: 'required'),
        ));
        return;
      }
    }
    _dispatch(
      action,
      cmd,
      data,
      RemoteCommandContext(
        encrypted: true,
        authorized: session.authorized,
        sidB64: session.sidB64,
        peerFingerprint: session.peerFingerprint,
        peerName: session.peerName,
      ),
    );
  }

  /// Seal and send a command over [session]'s wire endpoint. Returns false
  /// when no socket or endpoint is available.
  Future<bool> _sendOverSession(RemoteSession session, RemoteCommand command) =>
      sendEncryptedCommand(session, command);

  /// Public for the sender flows: send [command] encrypted on [session].
  Future<bool> sendEncryptedCommand(
      RemoteSession session, RemoteCommand command) async {
    final manager = _sessionManager;
    final service = _commandService;
    final peer = _sessionPeers[session.sidB64];
    if (manager == null || service == null || peer == null) return false;
    final envelope = await manager.sealCommand(session, command.toJson());
    return service.sendRaw(envelope, peer.ip, port: peer.port);
  }

  /// Liveness probe over an existing session.
  Future<bool> pingSession(RemoteSession session,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final correlator = 'p${++_pingSeq}';
    final completer = Completer<void>();
    _pendingPongs[correlator] = completer;
    final sent = await sendEncryptedCommand(
      session,
      RemoteCommand(
          action: RemoteAction.sys, command: SysCommand.ping, data: correlator),
    );
    if (!sent) {
      _pendingPongs.remove(correlator);
      return false;
    }
    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      _pendingPongs.remove(correlator);
      return false;
    }
  }

  /// Ensure the persistent (sender) socket exists so handshake replies can
  /// arrive. The static one-shot [UdpCommandService.sendCommandToIp] cannot
  /// receive anything — session traffic must never use it.
  Future<UdpCommandService> _ensureCommandService() async {
    var service = _commandService;
    if (service == null || !service.isRunning) {
      service = UdpCommandService(isTv: _isTv);
      _commandService = service;
      await service.start();
    }
    _wireSession(service);
    return service;
  }

  final Map<String, Future<RemoteSession?>> _handshakesByIp = {};

  /// Establish (or reuse) an encrypted session with [ip]. Returns null when
  /// the peer never answers the handshake (v1 build, or gone).
  ///
  /// Concurrent callers for one IP share a single attempt — otherwise the
  /// opportunistic connect-time handshake and a credential flow's preflight
  /// race, and whichever finishes LAST overwrites the ip→session mapping
  /// (possibly replacing the paired session with an unauthorized one).
  Future<RemoteSession?> ensureEncryptedSession(String ip,
      {Duration timeout = const Duration(seconds: 6)}) {
    final inFlight = _handshakesByIp[ip];
    if (inFlight != null) return inFlight;
    final attempt = _ensureEncryptedSessionInner(ip, timeout)
        .whenComplete(() => _handshakesByIp.remove(ip));
    _handshakesByIp[ip] = attempt;
    return attempt;
  }

  Future<RemoteSession?> _ensureEncryptedSessionInner(
      String ip, Duration timeout) async {
    final existing = _sessionByIp[ip];
    if (existing != null &&
        _sessionManager?.sessions.containsKey(existing.sidB64) == true) {
      // Probe: the TV may have restarted and lost the session.
      if (await pingSession(existing)) return existing;
      _sessionByIp.remove(ip);
      _sessionManager?.sessions.remove(existing.sidB64);
    }

    final service = await _ensureCommandService();
    final manager = _sessionManager!;
    final hs1 = await manager.startHandshake();
    final sid = hs1['sid'] as String;
    _sessionPeers[sid] = (ip: ip, port: service.portFor(ip));
    final completer = Completer<RemoteSession?>();
    _pendingHandshakes[sid] = completer;
    service.sendRaw(hs1, ip);
    try {
      final session = await completer.future.timeout(timeout);
      return session;
    } on TimeoutException {
      _pendingHandshakes.remove(sid);
      return null;
    }
  }

  /// Deauthorize (and drop) live sessions for a peer, e.g. after the user
  /// forgets a paired device — the persisted fingerprint alone must not leave
  /// an already-authorized session usable. Null revokes every session.
  void revokeAuthorization({String? fingerprint}) {
    final manager = _sessionManager;
    if (manager == null) return;
    manager.sessions.removeWhere((_, session) {
      final matches =
          fingerprint == null || session.peerFingerprint == fingerprint;
      if (matches) session.authorized = false;
      return matches;
    });
    _sessionByIp.removeWhere(
        (_, session) => !manager.sessions.containsKey(session.sidB64));
  }

  void _teardownSessions() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _sessionManager = null;
    _pairingGate = null;
    _sessionPeers.clear();
    _sessionByIp.clear();
    for (final completer in _pendingHandshakes.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pendingHandshakes.clear();
    for (final completer in _pendingPongs.values) {
      if (!completer.isCompleted) completer.complete();
    }
    _pendingPongs.clear();
  }
}
