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
  String toString() {
    if (data == null) return 'RemoteCommand($action: $command)';
    final truncated = data!.length > 80 ? '${data!.substring(0, 80)}...[${data!.length}]' : data;
    return 'RemoteCommand($action: $command, data: $truncated)';
  }
}

/// The last endpoint (address + source port) a peer was actually seen on.
/// The phone binds an EPHEMERAL port, so replying to the fixed kCommandPort
/// silently loses every TV→phone message — replies must go to the observed
/// source port instead (fall back to kCommandPort only for v1 peers that
/// have never sent us anything).
class _PeerEndpoint {
  final int port;
  final DateTime lastSeen;
  const _PeerEndpoint(this.port, this.lastSeen);
}

/// Service for sending/receiving UDP commands
class UdpCommandService {
  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _connectionCheckTimer;
  DateTime? _lastHeartbeatReceived;
  final bool _isTv;
  String? _connectedIp;
  final Map<String, _PeerEndpoint> _peerEndpoints = {};

  /// v2 session message types that bypass RemoteCommand handling and go to
  /// the session layer instead.
  static const Set<String> _sessionTypes = {
    RemoteMessageType.hs1,
    RemoteMessageType.hs2,
    RemoteMessageType.hs3,
    RemoteMessageType.hs4,
    RemoteMessageType.ecmd,
    RemoteMessageType.serr,
  };

  // Callbacks. The source address rides along: plaintext senders have no
  // other identity, and the receiver's consent flow is keyed on it.
  void Function(RemoteCommand command, String sourceIp)? onCommandReceived;
  void Function()? onConnectionLost;
  void Function()? onHeartbeatReceived;
  void Function(String error)? onError;

  /// Raw tap for v2 session traffic (handshakes, encrypted envelopes,
  /// session errors) with the sender's observed endpoint, so the session
  /// layer can reply to where the datagram actually came from.
  void Function(Map<String, dynamic> json, InternetAddress address, int port)?
      onSessionMessage;

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
    _peerEndpoints.clear();
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
        portFor(_connectedIp!),
      );
      debugPrint('UdpCommandService: Sent command: $command');
    } catch (e) {
      debugPrint('UdpCommandService: Failed to send command: $e');
    }
  }

  /// The port to reach [ip] on: its AUTHENTICATED source port when the
  /// session layer has vouched for one, else the fixed command port (v1
  /// compat — packets to a phone's closed temp port just vanish, which
  /// matches today's behavior).
  int portFor(String ip) => _peerEndpoints[ip]?.port ?? kCommandPort;

  /// Record where [ip] actually talks from. Called by the session layer ONLY
  /// after a message from that endpoint authenticated (opened ecmd, accepted
  /// handshake) — never straight off a datagram header.
  void notePeerEndpoint(String ip, int port) {
    _peerEndpoints[ip] = _PeerEndpoint(port, DateTime.now());
  }

  /// Send an arbitrary JSON message on the persistent socket. This is the
  /// session layer's transport — handshakes and encrypted envelopes must ride
  /// a socket that stays open to receive the reply, never the self-closing
  /// [sendCommandToIp].
  bool sendRaw(Map<String, dynamic> json, String ip, {int? port}) {
    final socket = _socket;
    if (socket == null) return false;
    try {
      socket.send(
        utf8.encode(jsonEncode(json)),
        InternetAddress(ip),
        port ?? portFor(ip),
      );
      return true;
    } catch (e) {
      debugPrint('UdpCommandService: Failed to send raw message: $e');
      return false;
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
      if (command.command != ConfigCommand.debrifyChannelChunk) {
        debugPrint('UdpCommandService: Sent command to $targetIp: $command');
      }
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
          portFor(_connectedIp!),
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

      // Peer endpoints are NOT learned here: any datagram can spoof a type,
      // and caching a forged packet's source port would redirect replies and
      // heartbeats to an attacker-chosen (or long-dead one-shot) port. The
      // session layer calls [notePeerEndpoint] once a message actually
      // authenticates; until then replies fall back to kCommandPort, which
      // is correct for the TV (fixed port) and status quo for v1 phones
      // (whose ephemeral socket never received replies anyway).

      if (type != null && _sessionTypes.contains(type)) {
        onSessionMessage?.call(json, datagram.address, datagram.port);
      } else if (type == RemoteMessageType.heartbeat) {
        _lastHeartbeatReceived = DateTime.now();
        onHeartbeatReceived?.call();
      } else if (type == RemoteMessageType.command) {
        final command = RemoteCommand.fromJson(json);
        if (command.command != ConfigCommand.debrifyChannelChunk) {
          debugPrint('UdpCommandService: Received command: $command');
        }
        onCommandReceived?.call(command, datagram.address.address);
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
