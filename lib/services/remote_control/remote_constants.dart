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
  // --- Protocol v2 (encrypted sessions). Old peers drop unknown types. ---
  static const String hs1 = 'hs1'; // sender → receiver: sid + commitment
  static const String hs2 = 'hs2'; // receiver → sender: ephemeral + static key
  static const String hs3 = 'hs3'; // sender → receiver: reveal + confirm tag
  static const String hs4 = 'hs4'; // receiver → sender: confirm tag
  static const String ecmd = 'ecmd'; // encrypted RemoteCommand envelope
  static const String serr = 'serr'; // plaintext advisory: unknown session
}

/// Protocol version advertised in discovery. v1 = plaintext only (implied by
/// the field's absence), v2 = X25519/AES-GCM sessions + pairing codes.
const int kProtoVersion = 2;

/// Session handshake / lifetime tuning.
const Duration kHandshakeRetransmit = Duration(milliseconds: 700);
const int kHandshakeMaxRetransmits = 3;
const Duration kHandshakeTimeout = Duration(seconds: 5);
const Duration kPendingHandshakeExpiry = Duration(seconds: 30);
const Duration kSessionIdleTimeout = Duration(minutes: 10);
const Duration kSessionMaxAge = Duration(hours: 12);
const int kMaxSessions = 8;

/// Pairing-code (SAS) UX guards.
const Duration kPairingCodeTimeout = Duration(seconds: 120);
const Duration kPairingMinDisplay = Duration(seconds: 3);
const int kPairingMaxAttempts = 3;
const Duration kPairingAttemptWindow = Duration(minutes: 5);

/// Whether a receiver remembers phones that completed a pairing code once
/// (persisted pubkey fingerprint skips the code on later transfers — still
/// encrypted). The store is written either way so flipping this later works
/// retroactively.
const bool kRememberPairedSenders = true;

/// What a sender does when the target never advertised protocol v2.
enum LegacySendPolicy {
  /// Refuse credential/config sends with an "update the TV app" message.
  block,

  /// Warn, but allow an explicit per-transfer plaintext override.
  allowWithOverride,
}

/// Product decision (2026-08): hard block — no plaintext credential path
/// survives on the sender side. The enum keeps the override branch
/// compilable should that ever need revisiting.
const LegacySendPolicy kLegacyCredentialPolicy = LegacySendPolicy.block;

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
  // v2: pairing-code exchange and session liveness probes. Both ride inside
  // ecmd envelopes, so an old TV never sees them.
  static const String pair = 'pair';
  static const String sys = 'sys';
}

/// Pairing commands (action: pair)
class PairCommand {
  static const String request = 'request'; // phone asks for authorization
  static const String challenge = 'challenge'; // TV: code is on screen
  static const String confirm = 'confirm'; // phone sends code proof
  static const String ok = 'ok'; // TV: session authorized
  static const String err = 'err'; // TV: refused (data = reason)
}

/// Session liveness commands (action: sys)
class SysCommand {
  static const String ping = 'ping';
  static const String pong = 'pong';
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
  static const String premiumize = 'premiumize';
  static const String allDebrid = 'alldebrid';
  static const String pikpak = 'pikpak';
  static const String trakt = 'trakt';
  static const String simkl = 'simkl';
  static const String searchEngines = 'search_engines';
  static const String webDav = 'webdav';
  static const String indexerManagers = 'indexer_managers';
  // IPTV travels as three commands rather than one blob so each can be
  // selected on its own. Order matters on the wire: memberships name the
  // provider they came from, so playlists must be sent (and applied) first.
  static const String iptvPlaylists = 'iptv_playlists';
  static const String iptvFavorites = 'iptv_favorites';
  static const String iptvLists = 'iptv_lists';
  static const String debrifyChannel = 'debrify_channel';
  // The chunked-transfer envelope. Named for Debrify TV channels because that
  // was the first thing big enough to need it, but the start packet carries a
  // `kind` naming the command its reassembled payload belongs to, so any
  // config command can travel this way.
  static const String debrifyChannelStart = 'debrify_channel_start';
  static const String debrifyChannelChunk = 'debrify_channel_chunk';
  // A picked avatar image from the paired phone. NOT setup data: it applies
  // to the active profile immediately instead of joining the staged import.
  static const String profileAvatar = 'profile_avatar';
  static const String complete =
      'complete'; // Signals all configs sent, TV should restart
}

/// Chunked transfer constants
const int kChunkMaxBytes =
    1400; // Safe single-fragment UDP payload (MTU 1500 - IP/UDP headers)
const int kChunkJsonOverhead = 120; // JSON envelope overhead per chunk packet
const int kChunkDataMaxBytes =
    kChunkMaxBytes - kChunkJsonOverhead; // 1280 — max raw string in direct path
// Chunk data is double-JSON-encoded (inner chunkData JSON stringified inside outer RemoteCommand JSON).
// Inner non-data overhead: transferId (~27), index (~4), field names/braces (~36) = ~67 chars.
// Quote escaping of inner JSON's 10 double-quotes: +10 chars.
// Outer envelope: ~80 chars. Total non-data overhead: ~157 chars.
// Safe base64 budget: 1400 - 157 = 1243 chars → floor(1243 * 3/4) = 932, rounded to 930 (divisible by 3).
// Verify: 930 bytes → 1240 base64 chars + 157 overhead = 1397 bytes ≤ 1400.
const int kChunkRawBytesPerChunk = 930;
const Duration kChunkTransferTimeout = Duration(seconds: 30);

/// Worst-case JSON overhead of the ecmd envelope around an encrypted command
/// ({"type":"ecmd","sid":...,"n":...,"ct":...} minus the ct payload itself):
/// type+field names/braces ~44, sid 12 b64 chars + quotes, n up to 16 digits.
/// Pinned by a budget test rather than trusted arithmetic.
const int kEcmdEnvelopeOverhead = 90;
