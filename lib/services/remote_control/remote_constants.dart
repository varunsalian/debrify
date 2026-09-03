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
/// the field's absence), v2 = X25519/AES-GCM sessions + pairing codes, v3 =
/// correlated receiver outcomes for single-addon transfers, v4 = correlated
/// outcomes for configuration batches and Debrify TV channels, v5 = complete
/// profile-graph transfers (including disabled resources, profile-local
/// settings, lock policy, reference remapping, and bounded compression).
const int kProtoVersion = 5;

const int kAddonResultProtocolVersion = 3;
const int kRemoteTransferResultProtocolVersion = 4;
const int kComprehensiveProfileGraphProtocolVersion = 5;

/// First Debrify release whose RECEIVER speaks [kProtoVersion] 2, quoted to
/// the user when a send is refused. v2 landed after 0.8.1-alpha.1 shipped, so
/// every build released before this one is a v1 receiver and cannot be set up
/// from a phone. Bump only if the v2 receiver's first release changes.
const String kFirstV2ReceiverVersion = '0.8.2';

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
  static const String mdblist = 'mdblist';
  static const String trackingPreferences = 'tracking_preferences';
  static const String searchEngines = 'search_engines';
  static const String webDav = 'webdav';
  static const String indexerManagers = 'indexer_managers';
  // IPTV travels as three commands rather than one blob so each can be
  // selected on its own. Order matters on the wire: memberships name the
  // provider they came from, so playlists must be sent (and applied) first.
  static const String iptvPlaylists = 'iptv_playlists';
  static const String iptvFavorites = 'iptv_favorites';
  static const String iptvLists = 'iptv_lists';

  /// Stream badge rulesets (imported badges.json sources), as one JSON array.
  static const String streamBadges = 'stream_badges';
  static const String debrifyChannel = 'debrify_channel';
  // The chunked-transfer envelope. Named for Debrify TV channels because that
  // was the first thing big enough to need it, but the start packet carries a
  // `kind` naming the command its reassembled payload belongs to, so any
  // config command can travel this way.
  static const String debrifyChannelStart = 'debrify_channel_start';
  static const String debrifyChannelChunk = 'debrify_channel_chunk';
  // Gap repair, receiver → sender: "these chunk indices never arrived,
  // resend them." This is what lets the sender pace aggressively — a lost
  // datagram costs one small repair round instead of the whole transfer.
  // v2-only by construction: it rides the encrypted session, and v1 senders
  // (which keep the old slow pace) never receive one.
  static const String debrifyChannelNeed = 'debrify_channel_need';
  // A picked avatar image from the paired phone. NOT setup data: it applies
  // to the active profile immediately instead of joining the staged import.
  static const String profileAvatar = 'profile_avatar';
  // A complete profile graph (exportAllProfiles package, integrity-stamped)
  // from an Admin phone. Applied atomically through the same
  // restoreDeviceGraph path a file restore uses — it never joins the staged
  // per-command import, and it supersedes the piecemeal send when chosen.
  // v5 receiver capability required: older receivers can authenticate this
  // command but do not understand every field in today's complete graph.
  static const String profileGraph = 'profile_graph';
  // Receiver → sender: the real outcome of a profile-graph transfer
  // (delivered is not applied — the TV user confirms, authorization can
  // refuse, the import can fail). Consumed in RemoteControlState._dispatch
  // on any role; never routed to the command router.
  static const String profileGraphResult = 'profile_graph_result';
  // Receiver → sender: correlated result for a single-addon transfer. The
  // sender must not treat local UDP acceptance as proof that the TV applied
  // the add-on.
  static const String addonTransferResult = 'addon_transfer_result';
  // Receiver → sender: correlated application outcome for v4 configuration
  // batches and Debrify TV channel imports.
  static const String remoteTransferResult = 'remote_transfer_result';
  // Sender → receiver: opens a fresh correlated v4 batch before any config
  // or addon items are emitted, preventing reuse of stale staged data.
  static const String remoteTransferStart = 'remote_transfer_start';
  static const String complete =
      'complete'; // Signals all configs sent, TV should restart
}

/// Chunked transfer constants
///
/// Pace and repair tuning. The old design paced 50ms/chunk with no recovery
/// — ~18 KB/s, so a 1 MB channel took 75 seconds and ONE lost datagram lost
/// the whole transfer anyway. The current design paces fast and repairs:
/// the receiver watches for stalls, asks for exactly the missing indices
/// over the encrypted session, and the sender replays them from a short-
/// lived cache.
const Duration kChunkPace = Duration(milliseconds: 4);

/// Quiet time on the receiver before it asks for missing chunks. Long enough
/// that in-flight datagrams land first; short enough that a repair round is
/// cheap.
const Duration kChunkRepairStall = Duration(milliseconds: 1200);

/// Repair rounds before the receiver gives up. Bounds the worst case at
/// roughly rounds × stall on a dead link.
const int kChunkRepairMaxRounds = 8;

/// Missing indices per need packet — the whole request must fit one SEALED
/// datagram (ecmd envelope: ~880 payload bytes; five-digit indices cost 6
/// each). The budget test pins this. A round that cannot name every gap
/// catches the rest on the next round.
const int kChunkNeedMaxIndices = 100;

/// How long a sender keeps a finished transfer's chunks for repair.
const Duration kChunkResendCacheTtl = Duration(seconds: 90);

/// Largest profile-graph payload a sender will put on the wire. The receiver's
/// chunk reassembly buffer caps at 16 MB and holds the sealed blob as base64
/// (x4/3), so 10 MB leaves transport headroom.
const int kMaxProfileGraphWireBytes = 10 * 1024 * 1024;

/// Soft expanded-JSON threshold for a full profile graph. Above this size the
/// sender offers a compact re-export: rebuildable IPTV caches are removed and
/// Debrify TV channels are omitted together with their saved hash pools after
/// explicit user confirmation, keeping the receiver's working set near 32 MB.
const int kProfileGraphCompactionThresholdBytes = 32 * 1024 * 1024;

/// Hard JSON limit after an authenticated profile-graph gzip wrapper is
/// expanded, including after the cache-compaction retry. File backups may use
/// the package format's much larger envelope, but a low-memory TV must hold the
/// compressed transport, expanded UTF-8, parsed JSON, and restored attachments
/// at the same time.
///
/// SQLite snapshots expand by another 4/3 when embedded as base64. A 48 MB
/// ceiling therefore admits roughly 36 MB of compact durable database data
/// while remaining far below the 128 MB file-package envelope. The receiver
/// releases its chunk reassembly storage before expansion to keep that budget
/// bounded.
const int kMaxProfileGraphExpandedBytes = 48 * 1024 * 1024;

bool profileGraphTransportNeedsCompaction({
  required int wireBytes,
  required int expandedBytes,
}) =>
    wireBytes > kMaxProfileGraphWireBytes ||
    expandedBytes > kProfileGraphCompactionThresholdBytes;

/// Authenticated package metadata used to correlate a profile-graph result
/// with the exact send attempt that caused it.
const String kProfileGraphRequestIdOmission = 'remoteTransferRequestId';

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
