import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'udp_discovery_service.dart';
import 'udp_command_service.dart';

/// Connection state enum
enum RemoteConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
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

  // Callbacks for TV mode
  void Function(String action, String command, String? data)? onCommandReceived;

  // Getters
  RemoteConnectionState get connectionState => _connectionState;
  DiscoveredDevice? get connectedDevice => _connectedDevice;
  List<DiscoveredDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  String? get lastError => _lastError;
  bool get isConnected => _connectionState == RemoteConnectionState.connected;
  bool get isScanning => _connectionState == RemoteConnectionState.scanning;
  bool get isTv => _isTv;
  bool get hasDevices => _discoveredDevices.isNotEmpty;

  /// Initialize for TV mode - start listening for mobile devices
  Future<void> startTvListener(String deviceName) async {
    _isTv = true;
    _deviceId = _generateDeviceId();

    debugPrint('RemoteControlState: Starting TV listener as "$deviceName"');

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

    _connectionState = RemoteConnectionState.disconnected;
    notifyListeners();
  }

  /// Initialize for Mobile mode - start scanning for TVs
  Future<void> startMobileDiscovery() async {
    if (_connectionState == RemoteConnectionState.scanning) {
      debugPrint('RemoteControlState: Already scanning');
      return;
    }

    _isTv = false;
    _deviceId = _generateDeviceId();
    _discoveredDevices = [];

    debugPrint('RemoteControlState: Starting mobile discovery');

    _connectionState = RemoteConnectionState.scanning;
    _lastError = null;
    notifyListeners();

    // Start discovery service
    _discoveryService = UdpDiscoveryService(
      deviceId: _deviceId,
      isTv: false,
    );

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
  }

  /// Stop all services
  Future<void> stop() async {
    await _discoveryService?.stop();
    await _commandService?.stop();
    _discoveryService = null;
    _commandService = null;
    _connectionState = RemoteConnectionState.disconnected;
    _connectedDevice = null;
    _discoveredDevices = [];
    notifyListeners();
  }

  /// Connect to a specific TV (for mobile)
  Future<void> connectToDevice(DiscoveredDevice device) async {
    if (_isTv) return;

    // If already connected to this device, do nothing
    if (_connectedDevice?.ip == device.ip && isConnected) {
      debugPrint('RemoteControlState: Already connected to ${device.deviceName}');
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

  /// Send a navigation command (for mobile)
  void sendNavigateCommand(String direction) {
    if (!isConnected || _isTv) return;
    _commandService?.sendCommand(RemoteCommand.navigate(direction));
  }

  /// Send a media command (for mobile)
  void sendMediaCommand(String command) {
    if (!isConnected || _isTv) return;
    _commandService?.sendCommand(RemoteCommand.media(command));
  }

  /// Send an addon command (for mobile)
  void sendAddonCommand(String command, {String? manifestUrl}) {
    if (!isConnected || _isTv) return;
    _commandService?.sendCommand(RemoteCommand.addon(command, manifestUrl: manifestUrl));
  }

  /// Send an addon command to a specific device by IP (doesn't require connection)
  Future<bool> sendAddonCommandToDevice(String command, String targetIp, {String? manifestUrl}) async {
    final cmd = RemoteCommand.addon(command, manifestUrl: manifestUrl);
    return await UdpCommandService.sendCommandToIp(cmd, targetIp);
  }

  /// Send a text input command (for mobile)
  void sendTextCommand(String command, {String? text}) {
    if (!isConnected || _isTv) return;
    _commandService?.sendCommand(RemoteCommand.text(command, text: text));
  }

  /// Restart scanning (for mobile)
  Future<void> rescan() async {
    await stop();
    await startMobileDiscovery();
  }

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
    debugPrint('RemoteControlState: Command received: $command');
    onCommandReceived?.call(command.action, command.command, command.data);
  }

  String _generateDeviceId() {
    final random = Random();
    return 'device_${random.nextInt(999999).toString().padLeft(6, '0')}';
  }
}
