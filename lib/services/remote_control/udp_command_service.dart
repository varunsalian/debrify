import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'remote_constants.dart';

/// Represents a remote control command
class RemoteCommand {
  final String action;
  final String command;
  final String? data;

  RemoteCommand({
    required this.action,
    required this.command,
    this.data,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': RemoteMessageType.command,
      'action': action,
      'command': command,
    };
    if (data != null) {
      json['data'] = data;
    }
    return json;
  }

  factory RemoteCommand.fromJson(Map<String, dynamic> json) {
    return RemoteCommand(
      action: json['action'] as String? ?? '',
      command: json['command'] as String? ?? '',
      data: json['data'] as String?,
    );
  }

  /// Create a navigation command
  factory RemoteCommand.navigate(String direction) {
    return RemoteCommand(
      action: RemoteAction.navigate,
      command: direction,
    );
  }

  /// Create a media command
  factory RemoteCommand.media(String mediaAction) {
    return RemoteCommand(
      action: RemoteAction.media,
      command: mediaAction,
    );
  }

  /// Create an addon command
  factory RemoteCommand.addon(String addonAction, {String? manifestUrl}) {
    return RemoteCommand(
      action: RemoteAction.addon,
      command: addonAction,
      data: manifestUrl,
    );
  }

  /// Create a text input command
  factory RemoteCommand.text(String textAction, {String? text}) {
    return RemoteCommand(
      action: RemoteAction.text,
      command: textAction,
      data: text,
    );
  }

  /// Create a config command (for sending setup/credentials to TV)
  factory RemoteCommand.config(String configType, {String? configData}) {
    return RemoteCommand(
      action: RemoteAction.config,
      command: configType,
      data: configData,
    );
  }

  @override
  String toString() => 'RemoteCommand($action: $command${data != null ? ', data: $data' : ''})';
}

/// Service for sending/receiving UDP commands
class UdpCommandService {
  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _connectionCheckTimer;
  DateTime? _lastHeartbeatReceived;
  final bool _isTv;
  String? _connectedIp;

  // Callbacks
  void Function(RemoteCommand command)? onCommandReceived;
  void Function()? onConnectionLost;
  void Function()? onHeartbeatReceived;
  void Function(String error)? onError;

  UdpCommandService({
    required bool isTv,
  }) : _isTv = isTv;

  /// Start the command service
  Future<void> start({String? targetIp}) async {
    try {
      await stop();

      _connectedIp = targetIp;

      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _isTv ? kCommandPort : 0, // TV uses fixed port, mobile uses any
        reuseAddress: true,
        reusePort: true,
      );

      _socket!.listen(
        _handleDatagram,
        onError: (error) {
          debugPrint('UdpCommandService: Socket error: $error');
          onError?.call(error.toString());
        },
        onDone: () {
          debugPrint('UdpCommandService: Socket closed');
        },
      );

      // Start heartbeat
      _startHeartbeat();

      // Start connection check
      _startConnectionCheck();

      debugPrint('UdpCommandService: Started ${_isTv ? "TV" : "Mobile"} mode');
    } catch (e) {
      debugPrint('UdpCommandService: Failed to start: $e');
      onError?.call(e.toString());
    }
  }

  /// Stop the command service
  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = null;
    _socket?.close();
    _socket = null;
    _connectedIp = null;
    _lastHeartbeatReceived = null;
  }

  /// Send a command to the connected device
  void sendCommand(RemoteCommand command) {
    if (_socket == null || _connectedIp == null) {
      debugPrint('UdpCommandService: Cannot send command - not connected');
      return;
    }

    final message = jsonEncode(command.toJson());

    try {
      _socket!.send(
        utf8.encode(message),
        InternetAddress(_connectedIp!),
        kCommandPort,
      );
      debugPrint('UdpCommandService: Sent command: $command');
    } catch (e) {
      debugPrint('UdpCommandService: Failed to send command: $e');
    }
  }

  /// Send a command to a specific IP address (without requiring connection)
  static Future<bool> sendCommandToIp(RemoteCommand command, String targetIp) async {
    RawDatagramSocket? tempSocket;
    try {
      // Create a temporary socket if we don't have one
      tempSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final message = jsonEncode(command.toJson());

      tempSocket.send(
        utf8.encode(message),
        InternetAddress(targetIp),
        kCommandPort,
      );
      debugPrint('UdpCommandService: Sent command to $targetIp: $command');
      return true;
    } catch (e) {
      debugPrint('UdpCommandService: Failed to send command to $targetIp: $e');
      return false;
    } finally {
      tempSocket?.close();
    }
  }

  /// Send a heartbeat message
  void sendHeartbeat() {
    if (_socket == null) return;

    final message = jsonEncode({
      'type': RemoteMessageType.heartbeat,
      'sender': _isTv ? RemoteSender.tv : RemoteSender.mobile,
    });

    try {
      if (_connectedIp != null) {
        _socket!.send(
          utf8.encode(message),
          InternetAddress(_connectedIp!),
          kCommandPort,
        );
      }
    } catch (e) {
      debugPrint('UdpCommandService: Failed to send heartbeat: $e');
    }
  }

  void _startHeartbeat() {
    // Send heartbeat immediately
    sendHeartbeat();

    // Then every 5 seconds
    _heartbeatTimer = Timer.periodic(kHeartbeatInterval, (_) {
      sendHeartbeat();
    });
  }

  void _startConnectionCheck() {
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_lastHeartbeatReceived != null) {
        final elapsed = DateTime.now().difference(_lastHeartbeatReceived!);
        if (elapsed > kConnectionTimeout) {
          debugPrint('UdpCommandService: Connection lost - no heartbeat received');
          onConnectionLost?.call();
        }
      }
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

      // Update connected IP if we receive a message
      if (_connectedIp == null) {
        _connectedIp = datagram.address.address;
        debugPrint('UdpCommandService: Connected to $_connectedIp');
      }

      if (type == RemoteMessageType.heartbeat) {
        _lastHeartbeatReceived = DateTime.now();
        onHeartbeatReceived?.call();
      } else if (type == RemoteMessageType.command) {
        final command = RemoteCommand.fromJson(json);
        debugPrint('UdpCommandService: Received command: $command');
        onCommandReceived?.call(command);
      }
    } catch (e) {
      debugPrint('UdpCommandService: Failed to parse message: $e');
    }
  }

  /// Set the target IP for sending commands
  void setTargetIp(String ip) {
    _connectedIp = ip;
  }

  /// Check if service is running
  bool get isRunning => _socket != null;

  /// Check if connected to a device
  bool get isConnected => _connectedIp != null && _lastHeartbeatReceived != null;
}
