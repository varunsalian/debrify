import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'remote_constants.dart';
import 'remote_command_router.dart';
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

    // Mark as connected after a short delay to allow heartbeat exchange
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_connectionState == RemoteConnectionState.connecting) {
        _connectionState = RemoteConnectionState.connected;
        notifyListeners();
      }
    });
  }

  /// Send a navigation command (sender role)
  void sendNavigateCommand(String direction) {
    if (!isConnected || _isTv) return;
    _commandService?.sendCommand(RemoteCommand.navigate(direction));
  }

  /// Send a media command (sender role)
  void sendMediaCommand(String command) {
    if (!isConnected || _isTv) return;
    _commandService?.sendCommand(RemoteCommand.media(command));
  }

  /// Send an addon command (sender role)
  void sendAddonCommand(String command, {String? manifestUrl}) {
    if (!isConnected || _isTv) return;
    _commandService?.sendCommand(
      RemoteCommand.addon(command, manifestUrl: manifestUrl),
    );
  }

  /// Send an addon command to a specific device by IP (doesn't require connection)
  Future<bool> sendAddonCommandToDevice(
    String command,
    String targetIp, {
    String? manifestUrl,
  }) async {
    final cmd = RemoteCommand.addon(command, manifestUrl: manifestUrl);
    return await UdpCommandService.sendCommandToIp(cmd, targetIp);
  }

  /// Send a config command to a specific device by IP (doesn't require connection)
  Future<bool> sendConfigCommandToDevice(
    String configType,
    String targetIp, {
    String? configData,
  }) async {
    final cmd = RemoteCommand.config(configType, configData: configData);
    return await UdpCommandService.sendCommandToIp(cmd, targetIp);
  }

  /// Send a text input command (sender role)
  void sendTextCommand(String command, {String? text}) {
    if (!isConnected || _isTv) return;
    _commandService?.sendCommand(RemoteCommand.text(command, text: text));
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
    _connectionState = RemoteConnectionState.disconnected;
    _connectedDevice = null;
    notifyListeners();
  }

  void _handleDeviceDiscovered(DiscoveredDevice device) {
    debugPrint('RemoteControlState: Device discovered: $device');
    // Don't auto-connect - let user choose from list
    // The devices list is updated via onDevicesUpdated callback
  }

  void _handleCommand(RemoteCommand command) {
    if (command.command != ConfigCommand.debrifyChannelChunk) {
      debugPrint('RemoteControlState: Command received: $command');
    }
    onCommandReceived?.call(command.action, command.command, command.data);
  }

  String _generateDeviceId() {
    final random = Random();
    return 'device_${random.nextInt(999999).toString().padLeft(6, '0')}';
  }
}
