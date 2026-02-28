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
  static const String addon = 'addon';
  static const String text = 'text';
  static const String config = 'config';
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

/// Addon commands
class AddonCommand {
  static const String install = 'install';
}

/// Text input commands
class TextCommand {
  static const String type = 'type'; // data contains the text to type
  static const String backspace = 'backspace'; // delete one character
  static const String clear = 'clear'; // clear the field
  static const String enter = 'enter'; // submit/done key (KEYCODE_ENTER)
}

/// Config commands (for sending setup/credentials to TV)
class ConfigCommand {
  static const String realDebrid = 'real_debrid';
  static const String torbox = 'torbox';
  static const String pikpak = 'pikpak';
  static const String searchEngines = 'search_engines';
  static const String debrifyChannel = 'debrify_channel';
  static const String debrifyChannelStart = 'debrify_channel_start';
  static const String debrifyChannelChunk = 'debrify_channel_chunk';
  static const String complete = 'complete'; // Signals all configs sent, TV should restart
}

/// Chunked transfer constants
const int kChunkMaxBytes = 1400; // Safe single-fragment UDP payload (MTU 1500 - IP/UDP headers)
const int kChunkJsonOverhead = 120; // JSON envelope overhead per chunk packet
const int kChunkDataMaxBytes = kChunkMaxBytes - kChunkJsonOverhead; // 1280 — max raw string in direct path
// Chunk data is double-JSON-encoded (inner chunkData JSON stringified inside outer RemoteCommand JSON).
// Inner non-data overhead: transferId (~27), index (~4), field names/braces (~36) = ~67 chars.
// Quote escaping of inner JSON's 10 double-quotes: +10 chars.
// Outer envelope: ~80 chars. Total non-data overhead: ~157 chars.
// Safe base64 budget: 1400 - 157 = 1243 chars → floor(1243 * 3/4) = 932, rounded to 930 (divisible by 3).
// Verify: 930 bytes → 1240 base64 chars + 157 overhead = 1397 bytes ≤ 1400.
const int kChunkRawBytesPerChunk = 930;
const Duration kChunkTransferTimeout = Duration(seconds: 30);
