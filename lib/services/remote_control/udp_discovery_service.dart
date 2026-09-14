import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'remote_constants.dart';
import 'remote_network_addresses.dart';
import 'remote_transfer_diagnostics.dart';

/// Represents a discovered TV device
class DiscoveredDevice {
  final String deviceName;
  final String ip;
  final DateTime discoveredAt;

  /// Protocol version the device advertised. Absent field = 1 (a build that
  /// predates encrypted sessions).
  final int protoVersion;

  /// False only when the target was entered manually and no discovery or
  /// handshake has identified its capabilities yet.
  final bool protocolVersionKnown;

  /// The device's static X25519 public key (base64), advertised by v2
  /// receivers so senders can pin identities before any handshake.
  final String? staticKey;

  DiscoveredDevice({
    required this.deviceName,
    required this.ip,
    DateTime? discoveredAt,
    this.protoVersion = 1,
    this.protocolVersionKnown = true,
    this.staticKey,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  bool get supportsEncryption => protoVersion >= 2;
  bool get supportsAddonTransferResult =>
      protoVersion >= kAddonResultProtocolVersion;
  bool get supportsRemoteTransferResult =>
      protoVersion >= kRemoteTransferResultProtocolVersion;
  bool get supportsComprehensiveProfileGraph =>
      protoVersion >= kComprehensiveProfileGraphProtocolVersion;
  bool get maySupportComprehensiveProfileGraph =>
      !protocolVersionKnown || supportsComprehensiveProfileGraph;

  DiscoveredDevice withProtocolVersion(int value) => DiscoveredDevice(
    deviceName: deviceName,
    ip: ip,
    discoveredAt: discoveredAt,
    protoVersion: value,
    protocolVersionKnown: true,
    staticKey: staticKey,
  );

  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'ip': ip,
    'discoveredAt': discoveredAt.toIso8601String(),
    'proto': protoVersion,
    'protoKnown': protocolVersionKnown,
    if (staticKey != null) 'spk': staticKey,
  };

  factory DiscoveredDevice.fromJson(Map<String, dynamic> json) {
    return DiscoveredDevice(
      deviceName: json['deviceName'] as String? ?? 'Unknown TV',
      ip: json['ip'] as String,
      discoveredAt: json['discoveredAt'] != null
          ? DateTime.tryParse(json['discoveredAt'] as String)
          : null,
      protoVersion: (json['proto'] as num?)?.toInt() ?? 1,
      protocolVersionKnown: json['protoKnown'] as bool? ?? true,
      staticKey: json['spk'] as String?,
    );
  }

  @override
  String toString() =>
      'DiscoveredDevice($deviceName @ $ip, '
      '${protocolVersionKnown ? 'v$protoVersion' : 'version unknown'})';
}

/// Service for UDP-based device discovery
class UdpDiscoveryService {
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _discoveryTimeoutTimer;
  bool _broadcastInFlight = false;
  bool _initialScanDone = false;
  final String _deviceId;
  final bool _isTv;
  String? _tvDeviceName;

  // List of discovered devices (for mobile mode)
  final List<DiscoveredDevice> _discoveredDevices = [];

  // Callbacks
  void Function(DiscoveredDevice device)? onDeviceDiscovered;
  void Function(List<DiscoveredDevice> devices)? onDevicesUpdated;
  void Function()? onDiscoveryComplete;
  void Function(String error)? onError;

  UdpDiscoveryService({
    required String deviceId,
    required bool isTv,
    String? tvDeviceName,
  }) : _deviceId = deviceId,
       _isTv = isTv,
       _tvDeviceName = tvDeviceName;

  /// Get list of discovered devices
  List<DiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  /// Update TV device name (for TV mode)
  void setTvDeviceName(String name) {
    _tvDeviceName = name;
  }

  /// This device's static public key (base64), advertised in discovery
  /// responses. Set by the wiring layer once the keypair is loaded; until
  /// then responses carry only the protocol version, which is enough for the
  /// sender's v2 gate (the key itself also arrives in hs2).
  String? advertisedStaticKey;

  /// Start discovery (for mobile) or listening (for TV)
  Future<void> start() async {
    try {
      await stop();

      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kDiscoveryPort,
        reuseAddress: true,
        reusePort: true,
      );

      _socket!.broadcastEnabled = true;

      final socket = _socket!;
      socket.listen(
        _handleDatagram,
        onError: (error) {
          debugPrint(
            'UdpDiscoveryService: Socket error (${error.runtimeType})',
          );
          onError?.call('Discovery socket failed');
        },
        onDone: () {
          if (identical(_socket, socket)) {
            _socket = null;
            _broadcastTimer?.cancel();
            _discoveryTimeoutTimer?.cancel();
            onError?.call('Discovery stopped. Check local network access and retry.');
          }
          debugPrint('UdpDiscoveryService: Socket closed');
        },
      );

      if (_isTv) {
        debugPrint('UdpDiscoveryService: TV mode - listening for discovery');
      } else {
        debugPrint('UdpDiscoveryService: Mobile mode - starting broadcast');
        _startBroadcasting();
        _startDiscoveryTimeout();
      }
    } catch (error) {
      await stop();
      RemoteTransferDiagnostics.record(
        'discovery_start_failed',
        fields: {'errorType': error.runtimeType},
      );
      debugPrint('UdpDiscoveryService: Failed to start');
      onError?.call('Discovery could not start');
      rethrow;
    }
  }

  /// Stop discovery/listening
  Future<void> stop() async {
    _initialScanDone = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _discoveryTimeoutTimer?.cancel();
    _discoveryTimeoutTimer = null;
    _socket?.close();
    _socket = null;
    _discoveredDevices.clear();
  }

  /// Send a single discovery broadcast (for mobile)
  void sendDiscoveryBroadcast() async {
    if (_socket == null || _isTv || _broadcastInFlight) return;
    final listeningSocket = _socket;
    _broadcastInFlight = true;

    final message = jsonEncode({
      'type': RemoteMessageType.discovery,
      'sender': RemoteSender.mobile,
      'deviceId': _deviceId,
      'proto': kProtoVersion, // ignored by old TVs
    });

    final data = utf8.encode(message);

    // Send to global broadcast (works on most mobile devices)
    try {
      _socket!.send(data, InternetAddress(kBroadcastAddress), kDiscoveryPort);
      debugPrint('UdpDiscoveryService: Sent discovery broadcast');
    } catch (error) {
      debugPrint('UdpDiscoveryService: Failed to send discovery broadcast');
      RemoteTransferDiagnostics.record('discovery_broadcast_failed', fields: {
        'errorType': error.runtimeType,
        if (error is SocketException) 'osErrorCode': error.osError?.errorCode,
      });
    }

    // Send limited broadcast from each local address. Let the OS deliver it
    // on that network; inventing a /24 directed-broadcast address fails on
    // other subnet sizes. Responses still arrive on our fixed discovery port.
    try {
      for (final address in await RemoteNetworkAddress.list()) {
        if (!identical(_socket, listeningSocket)) return;
        RawDatagramSocket? source;
        try {
          source = await RawDatagramSocket.bind(
            InternetAddress(address.address),
            0,
          );
          if (!identical(_socket, listeningSocket)) return;
          source.broadcastEnabled = true;
          source.send(data, InternetAddress(kBroadcastAddress), kDiscoveryPort);
        } on SocketException catch (error) {
          debugPrint('UdpDiscoveryService: Interface broadcast unavailable');
          RemoteTransferDiagnostics.record('discovery_interface_failed', fields: {'osErrorCode': error.osError?.errorCode});
        } finally {
          source?.close();
        }
      }
    } catch (_) {
      debugPrint('UdpDiscoveryService: Network interface discovery failed');
    } finally {
      _broadcastInFlight = false;
    }
  }

  void _startBroadcasting() {
    // Send immediately
    sendDiscoveryBroadcast();

    // Then every 2 seconds
    var ticks = 0;
    _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_initialScanDone && ++ticks % 5 != 0) return;
      final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
      _discoveredDevices.removeWhere(
        (device) => device.discoveredAt.isBefore(cutoff),
      );
      onDevicesUpdated?.call(List.unmodifiable(_discoveredDevices));
      sendDiscoveryBroadcast();
    });
  }

  void _startDiscoveryTimeout() {
    _discoveryTimeoutTimer = Timer(kDiscoveryTimeout, () {
      debugPrint(
        'UdpDiscoveryService: Discovery complete (found ${_discoveredDevices.length} devices)',
      );
      // Keep a low-frequency scan alive for receivers opened later and for
      // Wi-Fi changes; selecting a peer stops this service entirely.
      _initialScanDone = true;
      onDiscoveryComplete?.call();
    });
  }

  void _handleDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket?.receive();
    if (datagram == null) return;

    try {
      final message = utf8.decode(datagram.data);
      final json = jsonDecode(message) as Map<String, dynamic>;
      final type = json['type'] as String?;

      debugPrint('UdpDiscoveryService: Received ${type ?? 'unknown'} packet');

      if (_isTv && type == RemoteMessageType.discovery) {
        _handleDiscoveryRequest(datagram.address, json);
      } else if (!_isTv && type == RemoteMessageType.discoveryResponse) {
        _handleDiscoveryResponse(datagram.address, json);
      }
    } catch (_) {
      debugPrint('UdpDiscoveryService: Failed to parse discovery packet');
    }
  }

  void _handleDiscoveryRequest(
    InternetAddress senderAddress,
    Map<String, dynamic> json,
  ) {
    // TV received discovery request from mobile - send response. The proto
    // and spk fields are invisible to old phones (they read only deviceName).
    final response = jsonEncode({
      'type': RemoteMessageType.discoveryResponse,
      'deviceName': _tvDeviceName ?? 'Debrify TV',
      'ip': _getLocalIp() ?? senderAddress.address,
      'proto': kProtoVersion,
      if (advertisedStaticKey != null) 'spk': advertisedStaticKey,
    });

    try {
      _socket?.send(utf8.encode(response), senderAddress, kDiscoveryPort);
      debugPrint('UdpDiscoveryService: Sent discovery response');
    } catch (_) {
      debugPrint('UdpDiscoveryService: Failed to send discovery response');
    }
  }

  void _handleDiscoveryResponse(
    InternetAddress senderAddress,
    Map<String, dynamic> json,
  ) {
    // Mobile received discovery response from TV
    // Always use the actual source IP of the packet, not the JSON field
    // (the JSON 'ip' field may be wrong if TV can't determine its own IP)
    final device = DiscoveredDevice(
      deviceName: json['deviceName'] as String? ?? 'Unknown TV',
      ip: senderAddress.address,
      protoVersion: (json['proto'] as num?)?.toInt() ?? 1,
      staticKey: json['spk'] as String?,
    );

    // Check if we already have this device (by IP)
    final existingIndex = _discoveredDevices.indexWhere(
      (d) => d.ip == device.ip,
    );
    if (existingIndex >= 0) {
      // Update existing device (name might have changed)
      _discoveredDevices[existingIndex] = device;
      debugPrint('UdpDiscoveryService: Updated discovered device');
    } else {
      // Add new device
      _discoveredDevices.add(device);
      debugPrint('UdpDiscoveryService: Discovered new device');
    }

    // Notify listeners
    onDeviceDiscovered?.call(device);
    onDevicesUpdated?.call(List.unmodifiable(_discoveredDevices));
  }

  String? _getLocalIp() {
    try {
      // This is a best-effort attempt to get local IP
      // The actual IP used for communication will be the one from the datagram
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Check if service is running
  bool get isRunning => _socket != null;
}
