/// Constants for UDP remote control communication between mobile and TV devices
library;

/// UDP port for discovery (broadcast)
const int kDiscoveryPort = 5555;

/// UDP port for commands (direct communication)
const int kCommandPort = 5556;

/// Broadcast address for discovery
const String kBroadcastAddress = '255.255.255.255';

/// Timeout durations
const Duration kDiscoveryTimeout = Duration(seconds: 10);
const Duration kHeartbeatInterval = Duration(seconds: 5);
const Duration kConnectionTimeout = Duration(seconds: 15);
const Duration kReconnectDelay = Duration(seconds: 2);

/// Message types
class RemoteMessageType {
  static const String discovery = 'discovery';
  static const String discoveryResponse = 'discovery_response';
  static const String command = 'command';
  static const String heartbeat = 'heartbeat';
}

/// Sender identifiers
class RemoteSender {
  static const String mobile = 'mobile';
  static const String tv = 'tv';
}

/// Command actions
class RemoteAction {
  static const String navigate = 'navigate';
  static const String media = 'media';
}

/// Navigation commands
class NavigateCommand {
  static const String up = 'up';
  static const String down = 'down';
  static const String left = 'left';
  static const String right = 'right';
  static const String select = 'select';
  static const String back = 'back';
}

/// Media commands
class MediaCommand {
  static const String playPause = 'play_pause';
  static const String seekForward = 'seek_forward';
  static const String seekBackward = 'seek_backward';
}
