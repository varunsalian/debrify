import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'profile_database_snapshot.dart';
import 'profile_avatar_ingest.dart';
import 'sanitized_profile_preferences.dart';
import '../../models/profiles/profile_avatar.dart';

const String _profilePackageTooLargeMessage =
    'Backup is too large to export as one portable package';

/// Typed retry signal for callers that may remove only documented,
/// rebuildable data and encode the package again.
///
/// This remains a [FormatException] for existing UI/error handling, while
/// avoiding substring-matched control flow that could mistake an unrelated
/// exception quoting the same sentence for an oversize package.
final class ProfilePackageTooLargeException extends FormatException {
  const ProfilePackageTooLargeException()
    : super(_profilePackageTooLargeMessage);
}

class PortableProfilePackage {
  static const int version = 4;
  static const int oldestSupportedVersion = 3;
  static const int maxEnvelopeBytes = 128 * 1024 * 1024;
  static const int maxExpandedBytes = 256 * 1024 * 1024;
  static const int maxProfiles = 64;
  static const int maxResources = 1024;
  static const int maxRecords = 250000;
  static const int maxDepth = 32;
  static const int maxStringBytes = 4 * 1024 * 1024;
  static const int maxResourceContentBytes = 64 * 1024 * 1024;
  static const int maxAttachmentBytes = 64 * 1024 * 1024;
  static const int maxTotalAttachmentBytes = 128 * 1024 * 1024;
  static const String exportTooLargeMessage = _profilePackageTooLargeMessage;

  /// Expected product exclusions are explained in the surrounding backup
  /// dialogs and do not need repeating in the completion snackbar. Every
  /// unknown/future omission is surfaced by default so adding one cannot
  /// silently hide lost data from the user.
  static const Set<String> routineOmissionKeys = <String>{
    'downloadAndRecordingBinaries',
    'downloadsAndRecordings',
    'activeJobsAndSchedules',
    'jobsAndSchedules',
    'deviceWidePreferencesAndRuntimeState',
    'devicePathsOsGrantsAndImportedFonts',
    'devicePathsAndOsGrants',
    'devicePathsAndGrants',
    'remoteIdentityAndPeers',
    'remotePairings',
    'destinationNameAvatarRolePolicyPinAndEnabledState',
    'pinAttemptCountersAndLockout',
    'pinsAndLockout',
    'pinHashesAndLockout',
    'pins',
    'deviceKeysExecutablesCommandsAndCustomSchemes',
    'deviceKeysAndExecutables',
    'localFilesystemBindingsAndResolvedPlaybackSources',
    'transientPreferenceAndFileCaches',
    'cachesAndTransientEpg',
    'profiles',
    'historyAndResume',
    'localFiles',
    DebrifyTvBackupOmission.key,
  };

  /// Format version read from the source envelope. Newly created packages use
  /// [version]; decoded v3 packages retain 3 so restore can apply the narrow
  /// compatibility policy without weakening validation for current exports.
  final int sourceVersion;
  final String mode;
  final DateTime createdAt;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> resources;
  final Map<String, dynamic> sections;
  final Map<String, dynamic> omissions;

  const PortableProfilePackage({
    this.sourceVersion = version,
    required this.mode,
    required this.createdAt,
    required this.profiles,
    required this.resources,
    required this.sections,
    this.omissions = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{
      'format': 'debrify-profile-package',
      'version': version,
      'mode': mode,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'profiles': profiles,
      'resources': resources,
      'sections': sections,
      'omissions': omissions,
    };
    return body;
  }

  static Map<String, dynamic> userVisibleOmissions(
    Map<String, dynamic> omissions,
  ) => <String, dynamic>{
    for (final entry in omissions.entries)
      if (!routineOmissionKeys.contains(entry.key) &&
          entry.value != null &&
          entry.value != false &&
          entry.value != 0 &&
          entry.value != '')
        entry.key: entry.value,
  };

  static Future<Map<String, dynamic>> buildSection(
    Map<String, Object?> values, {
    int schemaVersion = 1,
  }) async {
    final canonical = jsonEncode(values);
    final digest = await Sha256().hash(utf8.encode(canonical));
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'recordCount': values.length,
      'sha256': base64UrlEncode(digest.bytes).replaceAll('=', ''),
      'values': values,
    };
  }

  static Future<Map<String, dynamic>> withIntegrity(
    PortableProfilePackage package,
  ) async {
    final body = package.toJson();
    final canonical = jsonEncode(body);
    final digest = await Sha256().hash(utf8.encode(canonical));
    final envelope = <String, dynamic>{
      ...body,
      'integrity': <String, dynamic>{
        'algorithm': 'sha256',
        'digest': base64UrlEncode(digest.bytes).replaceAll('=', ''),
      },
    };
    _ensureEnvelopeFits(envelope);
    return envelope;
  }

  // ---- Off-main-isolate pipeline ------------------------------------------
  //
  // The KDF, AEAD, digests, and whole-envelope JSON work below are pure Dart
  // (package:cryptography with no platform delegate registered), and on a
  // 100 MB library backup they cost tens of seconds — run on the UI isolate
  // they freeze every frame of it. These entry points move the complete
  // pipeline into a short-lived worker isolate; UI callers should prefer
  // them over the raw methods further down.

  /// Sanitized/plain export: integrity-stamp and pretty-print the package.
  /// Pretty output is deliberate here — a sanitized backup is small and meant
  /// to be human-inspectable.
  static Future<Uint8List> encodePlainBytes(PortableProfilePackage package) {
    return Isolate.run(() async {
      final envelope = await withIntegrity(package);
      return Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(envelope)),
      );
    });
  }

  /// Encrypted export, compact-encoded: the envelope's bulk is one opaque
  /// base64 ciphertext, so indentation would only inflate the file.
  static Future<Uint8List> encodeEncryptedBytes(
    PortableProfilePackage package,
    String passphrase, {
    int memory = 19456,
    int iterations = 2,
  }) {
    if (passphrase.length < 8) {
      throw ArgumentError.value(
        passphrase,
        'passphrase',
        'Minimum 8 characters',
      );
    }
    return Isolate.run(() async {
      final envelope = await encrypt(
        package,
        passphrase,
        memory: memory,
        iterations: iterations,
      );
      return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    });
  }

  /// Reads just enough of a picked backup file to route it: is it a profile
  /// package, and does it need a passphrase prompt before the real parse?
  /// Legacy-format sources come back whole (they are small preference blobs)
  /// so the legacy adapter can parse them without a second read.
  static Future<({bool isProfilePackage, bool encrypted, String? legacySource})>
  probeFile(String path) {
    return Isolate.run(() async {
      final source = await readBoundedUtf8(File(path).openRead());
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Backup must be a JSON object');
      }
      final isPackage = decoded['format'] == 'debrify-profile-package';
      return (
        isProfilePackage: isPackage,
        encrypted: isPackage && decoded['encrypted'] == true,
        legacySource: isPackage ? null : source,
      );
    });
  }

  /// Full unlock of an encrypted package file. Re-reads the file rather than
  /// accepting a pre-parsed envelope so the 100 MB parse never happens on the
  /// caller's isolate; wrong-passphrase retries repeat the read, which the
  /// KDF dominates anyway.
  static Future<PortableProfilePackage> decryptFile(
    String path,
    String passphrase,
  ) {
    return Isolate.run(() async {
      return decrypt(await _readEnvelopeFile(path), passphrase);
    });
  }

  /// Off-main parse+validate of an unencrypted package file.
  static Future<PortableProfilePackage> decodeFile(String path) {
    return Isolate.run(() async => decodeMap(await _readEnvelopeFile(path)));
  }

  static Future<Map<String, dynamic>> _readEnvelopeFile(String path) async {
    final decoded = jsonDecode(await readBoundedUtf8(File(path).openRead()));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup must be a JSON object');
    }
    return decoded;
  }

  static Future<PortableProfilePackage> decode(String source) async {
    if (utf8.encode(source).length > maxEnvelopeBytes) {
      throw const FormatException('Backup exceeds the input limit');
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup must be an object');
    }
    return decodeMap(decoded);
  }

  /// Reads a provider/file stream without trusting a prior metadata length.
  /// The budget is enforced before appending each chunk, so a source replaced
  /// or grown after selection cannot force an unbounded whole-file read.
  static Future<String> readBoundedUtf8(
    Stream<List<int>> source, {
    int maxBytes = maxEnvelopeBytes,
  }) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in source) {
      if (chunk.isEmpty) continue;
      if (length > maxBytes - chunk.length) {
        throw const FormatException('Backup exceeds the input limit');
      }
      bytes.add(chunk);
      length += chunk.length;
    }
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw const FormatException('Backup is not valid UTF-8');
    }
  }

  static Future<PortableProfilePackage> decodeMap(
    Map<String, dynamic> decoded,
  ) => _decodeMap(
    decoded,
    authenticatedEncryption: false,
    allowMissingPreferences: false,
  );

  /// Decode for the local archive format, whose database attachments are
  /// `{encoding: file, entry, bytes, sha256}` references to archive entries
  /// the caller has already extracted and verified. Every other structural
  /// check and the integrity digest still run; base64 attachments remain
  /// accepted. Local archives are unencrypted by product decision (the
  /// creation dialog discloses it), so the passphrase requirement that
  /// guards plain JSON packages does not apply here.
  static Future<PortableProfilePackage> decodeFileBackedMap(
    Map<String, dynamic> decoded,
  ) => _decodeMap(
    decoded,
    authenticatedEncryption: true,
    allowMissingPreferences: false,
    allowFileBackedDatabases: true,
  );

  /// Decode for transports that already provide authenticated encryption —
  /// the paired remote session's AEAD stands in for the passphrase layer.
  /// Every structural validation and the integrity digest still run.
  static Future<PortableProfilePackage> decodeAuthenticatedMap(
    Map<String, dynamic> decoded, {
    bool allowMissingPreferences = false,
  }) => _decodeMap(
    decoded,
    authenticatedEncryption: true,
    allowMissingPreferences: allowMissingPreferences,
  );

  /// Off-main integrity-stamp + compact encode for session-authenticated
  /// transports (remote transfer). No passphrase layer: the wire seals it.
  static Future<String> encodeAuthenticatedJson(
    PortableProfilePackage package,
  ) {
    return Isolate.run(() async => jsonEncode(await withIntegrity(package)));
  }

  /// Compact authenticated transport used only when the ordinary remote JSON
  /// exceeds its wire budget. Text-heavy local M3U data and SQLite images
  /// compress well; the receiver still verifies the inner package integrity.
  static Future<String> encodeCompressedAuthenticatedJson(
    PortableProfilePackage package, {
    String? requestId,
    int maxExpandedPayloadBytes = maxEnvelopeBytes,
  }) async {
    return (await encodeAuthenticatedTransport(
      package,
      requestId: requestId,
      maxExpandedPayloadBytes: maxExpandedPayloadBytes,
    )).payload;
  }

  /// Builds the preferred raw-or-gzip authenticated transport in one worker
  /// pass and returns its byte counts. Remote callers can enforce both wire
  /// and expanded-memory budgets without repeatedly UTF-8 encoding a
  /// multi-megabyte String on the UI isolate.
  static Future<
    ({String payload, int wireBytes, int expandedBytes, bool compressed})
  >
  encodeAuthenticatedTransport(
    PortableProfilePackage package, {
    String? requestId,
    int maxExpandedPayloadBytes = maxEnvelopeBytes,
  }) {
    if (requestId != null && (requestId.isEmpty || requestId.length > 128)) {
      throw ArgumentError.value(requestId, 'requestId', 'Invalid request ID');
    }
    if (maxExpandedPayloadBytes < 1 ||
        maxExpandedPayloadBytes > maxEnvelopeBytes) {
      throw RangeError.range(
        maxExpandedPayloadBytes,
        1,
        maxEnvelopeBytes,
        'maxExpandedPayloadBytes',
      );
    }
    return Isolate.run(() async {
      final plain = utf8.encode(jsonEncode(await withIntegrity(package)));
      if (plain.length > maxExpandedPayloadBytes) {
        throw const ProfilePackageTooLargeException();
      }
      final compressed = gzip.encode(plain);
      final wrapped = jsonEncode(<String, Object?>{
        'format': 'debrify-profile-transport',
        'version': 1,
        'compression': 'gzip',
        'expandedBytes': plain.length,
        'data': base64Encode(compressed),
        if (requestId != null) 'requestId': requestId,
      });
      final wrappedBytes = utf8.encode(wrapped).length;
      return wrappedBytes < plain.length
          ? (
              payload: wrapped,
              wireBytes: wrappedBytes,
              expandedBytes: plain.length,
              compressed: true,
            )
          : (
              payload: utf8.decode(plain),
              wireBytes: plain.length,
              expandedBytes: plain.length,
              compressed: false,
            );
    });
  }

  /// Off-main counterpart for the receiving side: parse + validate a
  /// session-authenticated payload without stalling the UI isolate.
  static Future<PortableProfilePackage> decodeAuthenticatedJson(
    String json, {
    int maxExpandedPayloadBytes = maxEnvelopeBytes,
    bool allowMissingPreferences = false,
  }) {
    if (maxExpandedPayloadBytes < 1 ||
        maxExpandedPayloadBytes > maxEnvelopeBytes) {
      throw RangeError.range(
        maxExpandedPayloadBytes,
        1,
        maxEnvelopeBytes,
        'maxExpandedPayloadBytes',
      );
    }
    return Isolate.run(() async {
      final outer = jsonDecode(json);
      if (outer is! Map<String, dynamic>) {
        throw const FormatException('Profile graph must be an object');
      }
      Map<String, dynamic> decoded = outer;
      if (outer['format'] == 'debrify-profile-transport') {
        if (outer['version'] != 1 ||
            outer['compression'] != 'gzip' ||
            outer['expandedBytes'] is! int ||
            outer['data'] is! String ||
            (outer['requestId'] != null &&
                (outer['requestId'] is! String ||
                    (outer['requestId'] as String).isEmpty ||
                    (outer['requestId'] as String).length > 128)) ||
            (outer.length != 5 && outer.length != 6)) {
          throw const FormatException('Invalid compressed profile graph');
        }
        final claimed = outer['expandedBytes'] as int;
        final encoded = outer['data'] as String;
        if (claimed < 0 ||
            claimed > maxExpandedPayloadBytes ||
            encoded.length > ((maxEnvelopeBytes + 2) ~/ 3) * 4) {
          throw const FormatException('Compressed profile graph exceeds limit');
        }
        late final List<int> compressed;
        try {
          compressed = base64Decode(encoded);
        } on FormatException {
          throw const FormatException('Compressed profile graph is corrupt');
        }
        final expanded = await _gunzipBounded(
          compressed,
          maxExpandedPayloadBytes,
        );
        if (expanded.length != claimed) {
          throw const FormatException('Compressed profile graph size mismatch');
        }
        final inner = jsonDecode(utf8.decode(expanded));
        if (inner is! Map<String, dynamic>) {
          throw const FormatException('Profile graph must be an object');
        }
        decoded = inner;
      } else if (utf8.encode(json).length > maxExpandedPayloadBytes) {
        throw const FormatException('Profile graph exceeds expanded limit');
      }
      return _decodeMap(
        decoded,
        authenticatedEncryption: true,
        allowMissingPreferences: allowMissingPreferences,
      );
    });
  }

  static Future<List<int>> _gunzipBounded(
    List<int> compressed,
    int maxBytes,
  ) async {
    final output = BytesBuilder(copy: false);
    var length = 0;
    try {
      await for (final chunk in Stream<List<int>>.value(
        compressed,
      ).transform(gzip.decoder)) {
        if (length > maxBytes - chunk.length) {
          throw const FormatException('Compressed profile graph exceeds limit');
        }
        output.add(chunk);
        length += chunk.length;
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Compressed profile graph is corrupt');
    }
    return output.takeBytes();
  }

  static Future<PortableProfilePackage> _decodeMap(
    Map<String, dynamic> decoded, {
    required bool authenticatedEncryption,
    required bool allowMissingPreferences,
    bool allowFileBackedDatabases = false,
  }) async {
    if (decoded['encrypted'] == true) {
      throw const FormatException('Encrypted package must be unlocked first');
    }
    if (decoded['format'] != 'debrify-profile-package' ||
        !_supportsVersion(decoded['version'])) {
      throw const FormatException('Unsupported profile backup format');
    }
    final integrity = decoded['integrity'];
    if (integrity is! Map ||
        integrity['algorithm'] != 'sha256' ||
        integrity['digest'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(integrity['digest'] as String)) {
      throw const FormatException('Backup integrity record is missing');
    }
    final body = Map<String, dynamic>.from(decoded)..remove('integrity');
    final digest = await Sha256().hash(utf8.encode(jsonEncode(body)));
    if (!_constantTimeEquals(
      base64UrlEncode(digest.bytes).replaceAll('=', ''),
      integrity['digest']! as String,
    )) {
      throw const FormatException('Backup integrity check failed');
    }
    if (!authenticatedEncryption && body['mode'] != 'sanitizedSettings') {
      throw const FormatException(
        'Sensitive profile backups must be passphrase encrypted',
      );
    }
    _validateTree(body, 0, _Counter(), path: r'$');
    final omissions = body['omissions'];
    if (omissions is Map &&
        omissions.containsKey(DebrifyTvBackupOmission.key) &&
        DebrifyTvBackupOmission.fromOmissions(
              Map<String, dynamic>.from(omissions),
            ) ==
            null) {
      throw const FormatException('Invalid Debrify TV backup omission');
    }
    final profiles = body['profiles'];
    final resources = body['resources'];
    final sections = body['sections'];
    final mode = body['mode'];
    final createdAtSource = body['createdAt'];
    final createdAt = createdAtSource is String
        ? DateTime.tryParse(createdAtSource)
        : null;
    if (profiles is! List ||
        resources is! List ||
        sections is! Map<String, dynamic> ||
        profiles.length > maxProfiles ||
        resources.length > maxResources ||
        profiles.any((value) => value is! Map) ||
        resources.any((value) => value is! Map) ||
        mode != null && mode is! String ||
        createdAt == null ||
        omissions != null && omissions is! Map) {
      throw const FormatException('Backup collection limits exceeded');
    }
    final profileMaps = profiles
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
    final resourceMaps = resources
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
    _rejectDuplicateIds(profileMaps, 'profile');
    _rejectDuplicateIds(resourceMaps, 'resource');
    if (body['mode'] == 'sanitizedSettings') {
      _validateSanitizedPackage(profileMaps, resourceMaps, sections);
    }
    await _verifySections(
      profileMaps,
      sections,
      allowMissingPreferences: allowMissingPreferences,
      allowFileBackedDatabases: allowFileBackedDatabases,
    );
    return PortableProfilePackage(
      sourceVersion: body['version']! as int,
      mode: mode as String? ?? 'singleProfile',
      createdAt: createdAt.toUtc(),
      profiles: profileMaps,
      resources: resourceMaps,
      sections: Map<String, dynamic>.from(sections),
      omissions: omissions is Map
          ? Map<String, dynamic>.from(omissions)
          : const <String, dynamic>{},
    );
  }

  static Future<Map<String, dynamic>> encrypt(
    PortableProfilePackage package,
    String passphrase, {
    int memory = 19456,
    int iterations = 2,
    int parallelism = 1,
  }) async {
    if (passphrase.length < 8) {
      throw ArgumentError.value(
        passphrase,
        'passphrase',
        'Minimum 8 characters',
      );
    }
    final plain = utf8.encode(jsonEncode(await withIntegrity(package)));
    final aadText = _aadForVersion(version);
    _ensureEncryptedPayloadFits(
      plainBytes: plain.length,
      createdAt: package.createdAt,
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      aadText: aadText,
    );
    final salt = _randomBytes(16);
    final key = await Argon2id(
      parallelism: parallelism,
      memory: memory,
      iterations: iterations,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: key,
      aad: utf8.encode(aadText),
    );
    final envelope = <String, dynamic>{
      'format': 'debrify-profile-package',
      'version': version,
      'encrypted': true,
      'createdAt': package.createdAt.toUtc().toIso8601String(),
      'kdf': <String, dynamic>{
        'algorithm': 'argon2id',
        'salt': base64Encode(salt),
        'memory': memory,
        'iterations': iterations,
        'parallelism': parallelism,
      },
      'aead': <String, dynamic>{
        'algorithm': 'aes-256-gcm',
        'aad': aadText,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(<int>[...box.cipherText, ...box.mac.bytes]),
      },
    };
    _ensureEnvelopeFits(envelope);
    return envelope;
  }

  static void _ensureEnvelopeFits(Map<String, dynamic> envelope) {
    if (utf8.encode(jsonEncode(envelope)).length > maxEnvelopeBytes) {
      throw const ProfilePackageTooLargeException();
    }
  }

  /// True only for the bounded-package error callers may retry in compact
  /// mode. Compact mode can omit Debrify TV, so callers must obtain explicit
  /// user consent before saving or sending the resulting package.
  static bool isExportTooLarge(Object error) =>
      error is ProfilePackageTooLargeException;

  static void _ensureEncryptedPayloadFits({
    required int plainBytes,
    required DateTime createdAt,
    required int memory,
    required int iterations,
    required int parallelism,
    required String aadText,
  }) {
    final shell = <String, dynamic>{
      'format': 'debrify-profile-package',
      'version': version,
      'encrypted': true,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'kdf': <String, dynamic>{
        'algorithm': 'argon2id',
        'salt': base64Encode(Uint8List(16)),
        'memory': memory,
        'iterations': iterations,
        'parallelism': parallelism,
      },
      'aead': <String, dynamic>{
        'algorithm': 'aes-256-gcm',
        'aad': aadText,
        'nonce': base64Encode(Uint8List(12)),
        'ciphertext': '',
      },
    };
    final shellBytes = utf8.encode(jsonEncode(shell)).length;
    final encodedCiphertextBytes = ((plainBytes + 16 + 2) ~/ 3) * 4;
    if (shellBytes + encodedCiphertextBytes > maxEnvelopeBytes) {
      throw const ProfilePackageTooLargeException();
    }
  }

  static Future<PortableProfilePackage> decrypt(
    Map<String, dynamic> envelope,
    String passphrase,
  ) async {
    final kdf = envelope['kdf'];
    final aead = envelope['aead'];
    final envelopeVersion = envelope['version'];
    final expectedAad = _supportsVersion(envelopeVersion)
        ? _aadForVersion(envelopeVersion as int)
        : null;
    if (envelope['format'] != 'debrify-profile-package' ||
        expectedAad == null ||
        envelope['encrypted'] != true ||
        kdf is! Map ||
        aead is! Map ||
        kdf['algorithm'] != 'argon2id' ||
        aead['algorithm'] != 'aes-256-gcm' ||
        aead['aad'] != expectedAad) {
      throw const FormatException('Unsupported encrypted profile backup');
    }
    int bounded(Object? value, int min, int max) {
      if (value is! int) throw const FormatException('Invalid KDF parameters');
      if (value < min || value > max) {
        throw const FormatException('Unsafe KDF parameters');
      }
      return value;
    }

    try {
      final salt = base64Decode(kdf['salt']! as String);
      final nonce = base64Decode(aead['nonce']! as String);
      final packed = base64Decode(aead['ciphertext']! as String);
      if (salt.length < 8 ||
          salt.length > 64 ||
          nonce.length != 12 ||
          packed.length < 16 ||
          packed.length > maxExpandedBytes) {
        throw const FormatException('Encrypted backup is corrupt');
      }
      final parallelism = bounded(kdf['parallelism'], 1, 8);
      final memory = bounded(kdf['memory'], 8 * parallelism, 131072);
      final iterations = bounded(kdf['iterations'], 1, 16);
      final key = await Argon2id(
        parallelism: parallelism,
        memory: memory,
        iterations: iterations,
        hashLength: 32,
      ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          packed.sublist(0, packed.length - 16),
          nonce: nonce,
          mac: Mac(packed.sublist(packed.length - 16)),
        ),
        secretKey: key,
        aad: utf8.encode(aead['aad']! as String),
      );
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Decrypted backup must be an object');
      }
      if (decoded['version'] != envelopeVersion) {
        throw const FormatException('Encrypted backup version mismatch');
      }
      return _decodeMap(
        decoded,
        authenticatedEncryption: true,
        allowMissingPreferences: false,
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong passphrase or tampered backup');
    }
  }

  static bool _supportsVersion(Object? value) =>
      value is int && value >= oldestSupportedVersion && value <= version;

  static String _aadForVersion(int packageVersion) =>
      'debrify-profile-backup-v$packageVersion';

  static void _validateTree(
    Object? value,
    int depth,
    _Counter counter, {
    required String path,
  }) {
    if (depth > maxDepth) {
      throw const FormatException('Backup is too deeply nested');
    }
    counter.value++;
    if (counter.value > maxRecords) {
      throw const FormatException('Backup has too many records');
    }
    if (value is String) {
      final bytes = utf8.encode(value).length;
      final attachmentData =
          path.endsWith('.data') && path.contains('.sections.');
      final largeResourceContent =
          path.contains('.resources[') &&
          path.endsWith('.secretConfig.content');
      if ((!attachmentData &&
              !largeResourceContent &&
              bytes > maxStringBytes) ||
          (largeResourceContent && bytes > maxResourceContentBytes) ||
          (attachmentData && bytes > ((maxAttachmentBytes + 2) ~/ 3) * 4)) {
        throw const FormatException('Backup string exceeds the limit');
      }
      if (attachmentData) {
        counter.attachmentEncodedBytes += bytes;
        if (counter.attachmentEncodedBytes >
            ((maxTotalAttachmentBytes + 2) ~/ 3) * 4) {
          throw const FormatException('Backup attachments exceed the limit');
        }
      }
      if (value.contains('\u0000')) {
        throw const FormatException('Invalid text value');
      }
    } else if (value is List) {
      for (var index = 0; index < value.length; index++) {
        _validateTree(value[index], depth + 1, counter, path: '$path[$index]');
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String) throw const FormatException('Non-string key');
        _validateTree(entry.key, depth + 1, counter, path: '$path.<key>');
        _validateTree(
          entry.value,
          depth + 1,
          counter,
          path: '$path.${entry.key}',
        );
      }
    } else if (value != null && value is! bool && value is! num) {
      throw const FormatException('Unsupported backup value');
    }
  }

  static void _rejectDuplicateIds(
    List<Map<String, dynamic>> records,
    String kind,
  ) {
    final ids = <String>{};
    for (final record in records) {
      final id = record['backupId'];
      if (id is! String || id.isEmpty || !ids.add(id)) {
        throw FormatException('Invalid or duplicate $kind ID');
      }
    }
  }

  static void _validateSanitizedPackage(
    List<Map<String, dynamic>> profiles,
    List<Map<String, dynamic>> resources,
    Map<String, dynamic> sections,
  ) {
    if (profiles.length != 1) {
      throw const FormatException('Sanitized backup must contain one profile');
    }
    final profile = profiles.single;
    const allowedProfileKeys = <String>{'backupId', 'preferencesSection'};
    if (profile.keys.any((key) => !allowedProfileKeys.contains(key))) {
      throw const FormatException('Sanitized backup contains profile identity');
    }
    if (resources.isNotEmpty) {
      throw const FormatException(
        'Sanitized backup contains connection details',
      );
    }
    final section = sections[profile['preferencesSection']];
    if (section is! Map || section['values'] is! Map) {
      throw const FormatException('Sanitized preferences are missing');
    }
    for (final entry in (section['values'] as Map).entries) {
      if (!SanitizedProfilePreferences.allowsEntry(entry.key, entry.value)) {
        throw const FormatException('Sanitized backup contains private data');
      }
    }
  }

  static Future<void> _verifySections(
    List<Map<String, dynamic>> profiles,
    Map<String, dynamic> sections, {
    required bool allowMissingPreferences,
    bool allowFileBackedDatabases = false,
  }) async {
    final referenced = <String>{};
    for (final profile in profiles) {
      final id = profile['preferencesSection'];
      if (id == null && allowMissingPreferences) {
        // Structure-only sync graphs deliberately exclude preference payloads;
        // the adoption flow carries local preferences forward before pruning.
      } else if (id is! String || id.isEmpty || !referenced.add(id)) {
        throw const FormatException('Invalid profile preference section');
      } else {
        final section = sections[id];
        if (section is! Map ||
            section['schemaVersion'] != 1 ||
            section['values'] is! Map ||
            section['recordCount'] is! int) {
          throw const FormatException('Invalid profile preference section');
        }
        final values = Map<String, Object?>.from(section['values'] as Map);
        if (section['recordCount'] != values.length) {
          throw const FormatException('Profile section count mismatch');
        }
        final claimed = section['sha256'];
        if (claimed is! String) {
          throw const FormatException('Profile section digest is missing');
        }
        final digest = await Sha256().hash(utf8.encode(jsonEncode(values)));
        if (!_constantTimeEquals(
          base64UrlEncode(digest.bytes).replaceAll('=', ''),
          claimed,
        )) {
          throw const FormatException('Profile section digest mismatch');
        }
      }

      final filesSectionId = profile['filesSection'];
      if (filesSectionId != null) {
        if (filesSectionId is! String ||
            filesSectionId.isEmpty ||
            !referenced.add(filesSectionId)) {
          throw const FormatException('Invalid portable files section');
        }
        final filesSection = sections[filesSectionId];
        if (filesSection is! Map ||
            filesSection['schemaVersion'] != 1 ||
            filesSection['values'] is! Map ||
            filesSection['recordCount'] is! int) {
          throw const FormatException('Invalid portable files section');
        }
        final fileValues = Map<String, Object?>.from(
          filesSection['values'] as Map,
        );
        if (filesSection['recordCount'] != fileValues.length) {
          throw const FormatException('Portable files count mismatch');
        }
        final sectionClaimed = filesSection['sha256'];
        if (sectionClaimed is! String) {
          throw const FormatException('Portable files digest is missing');
        }
        final sectionDigest = await Sha256().hash(
          utf8.encode(jsonEncode(fileValues)),
        );
        if (!_constantTimeEquals(
          base64UrlEncode(sectionDigest.bytes).replaceAll('=', ''),
          sectionClaimed,
        )) {
          throw const FormatException('Portable files digest mismatch');
        }
        var fileBytes = 0;
        for (final entry in fileValues.entries) {
          final normalized = entry.key.replaceAll(r'\', '/');
          final segments = normalized.split('/');
          final allowedPath =
              normalized == entry.key &&
              segments.length >= 2 &&
              segments.first == 'engines' &&
              !segments.any(
                (segment) =>
                    segment.isEmpty || segment == '.' || segment == '..',
              ) &&
              !RegExp(r'^[A-Za-z]:').hasMatch(normalized) &&
              const <String>{'.yaml', '.yml', '.json'}.any(
                (extension) => normalized.toLowerCase().endsWith(extension),
              );
          if (!allowedPath || entry.value is! Map) {
            throw const FormatException('Invalid portable profile path');
          }
          final attachment = entry.value! as Map;
          if (attachment['encoding'] != 'base64' ||
              attachment['bytes'] is! int ||
              attachment['sha256'] is! String ||
              attachment['data'] is! String) {
            throw const FormatException('Invalid portable file attachment');
          }
          final claimedBytes = attachment['bytes'] as int;
          if (claimedBytes < 0 || claimedBytes > maxStringBytes) {
            throw const FormatException('Portable file exceeds limit');
          }
          final bytes = base64Decode(attachment['data'] as String);
          fileBytes += bytes.length;
          if (bytes.length != claimedBytes || fileBytes > maxAttachmentBytes) {
            throw const FormatException('Portable file size mismatch');
          }
          final digest = await Sha256().hash(bytes);
          if (!_constantTimeEquals(
            base64UrlEncode(digest.bytes).replaceAll('=', ''),
            attachment['sha256'] as String,
          )) {
            throw const FormatException('Portable file digest mismatch');
          }
        }
      }

      // Kept on the profile record rather than in filesSection so builds that
      // only allow `engines/` paths ignore the optional field and still import
      // the rest of the package. New builds authenticate and cap it here;
      // restore performs the image/dimension/frame validation before staging.
      final avatarFile = profile['avatarFile'];
      if (avatarFile != null) {
        final avatarKey = profile['avatarKey'];
        final avatar = avatarKey is String
            ? ProfileAvatar.tryParse(avatarKey)
            : null;
        if (avatar?.kind != ProfileAvatarKind.image ||
            avatarFile is! Map ||
            avatarFile['path'] != avatar!.id ||
            avatarFile['encoding'] != 'base64' ||
            avatarFile['bytes'] is! int ||
            avatarFile['sha256'] is! String ||
            avatarFile['data'] is! String) {
          throw const FormatException('Invalid portable avatar attachment');
        }
        final claimed = avatarFile['bytes'] as int;
        final encoded = avatarFile['data'] as String;
        if (claimed < 0 ||
            claimed > ProfileAvatarIngest.maxBytes ||
            encoded.length > ((ProfileAvatarIngest.maxBytes + 2) ~/ 3) * 4) {
          throw const FormatException('Portable avatar exceeds limit');
        }
        late final List<int> bytes;
        try {
          bytes = base64Decode(encoded);
        } on FormatException {
          throw const FormatException('Portable avatar is not valid base64');
        }
        if (bytes.length != claimed) {
          throw const FormatException('Portable avatar size mismatch');
        }
        final digest = await Sha256().hash(bytes);
        if (!_constantTimeEquals(
          base64UrlEncode(digest.bytes).replaceAll('=', ''),
          avatarFile['sha256'] as String,
        )) {
          throw const FormatException('Portable avatar digest mismatch');
        }
      }

      final databaseSectionId = profile['databasesSection'];
      if (databaseSectionId == null) continue;
      if (databaseSectionId is! String ||
          databaseSectionId.isEmpty ||
          !referenced.add(databaseSectionId)) {
        throw const FormatException('Invalid profile database section');
      }
      final databaseSection = sections[databaseSectionId];
      if (databaseSection is! Map ||
          databaseSection['schemaVersion'] != 1 ||
          databaseSection['values'] is! Map ||
          databaseSection['recordCount'] is! int) {
        throw const FormatException('Invalid profile database section');
      }
      final databaseValues = Map<String, Object?>.from(
        databaseSection['values'] as Map,
      );
      if (databaseSection['recordCount'] != databaseValues.length) {
        throw const FormatException('Database section count mismatch');
      }
      final databaseClaimed = databaseSection['sha256'];
      if (databaseClaimed is! String) {
        throw const FormatException('Database section digest is missing');
      }
      final databaseDigest = await Sha256().hash(
        utf8.encode(jsonEncode(databaseValues)),
      );
      if (!_constantTimeEquals(
        base64UrlEncode(databaseDigest.bytes).replaceAll('=', ''),
        databaseClaimed,
      )) {
        throw const FormatException('Database section digest mismatch');
      }
      var totalAttachmentBytes = 0;
      for (final entry in databaseValues.entries) {
        if (!ProfileDatabaseSnapshot.databaseNames.contains(entry.key) ||
            entry.value is! Map) {
          throw const FormatException('Unknown database attachment');
        }
        final attachment = entry.value! as Map;
        if (allowFileBackedDatabases && attachment['encoding'] == 'file') {
          // The staged file's size and digest are verified by the archive
          // reader before decode and again by the snapshot restore; here
          // only the record shape and its disk-oriented bound are checked.
          final reference = attachment['entry'];
          final fileBytes = attachment['bytes'];
          if (reference is! String ||
              reference.isEmpty ||
              reference.length > 240 ||
              reference.contains('\u0000') ||
              fileBytes is! int ||
              fileBytes < 0 ||
              fileBytes >
                  ProfileDatabaseSnapshot.maxFileBackedAttachmentBytes ||
              attachment['sha256'] is! String ||
              attachment.containsKey('data')) {
            throw const FormatException('Invalid database attachment');
          }
          continue;
        }
        if (attachment['encoding'] != 'base64' ||
            attachment['bytes'] is! int ||
            attachment['sha256'] is! String ||
            attachment['data'] is! String) {
          throw const FormatException('Invalid database attachment');
        }
        final claimedBytes = attachment['bytes'] as int;
        if (claimedBytes < 0 || claimedBytes > maxAttachmentBytes) {
          throw const FormatException('Database attachment exceeds limit');
        }
        final bytes = base64Decode(attachment['data'] as String);
        totalAttachmentBytes += bytes.length;
        if (bytes.length != claimedBytes ||
            totalAttachmentBytes > maxTotalAttachmentBytes) {
          throw const FormatException('Database attachment size mismatch');
        }
        final digest = await Sha256().hash(bytes);
        if (!_constantTimeEquals(
          base64UrlEncode(digest.bytes).replaceAll('=', ''),
          attachment['sha256'] as String,
        )) {
          throw const FormatException('Database attachment digest mismatch');
        }
      }
    }
    final unknownSections = sections.keys.where(
      (id) =>
          !referenced.contains(id) &&
          id != 'legacyFollowUp' &&
          id != 'legacyInventory',
    );
    if (unknownSections.isNotEmpty) {
      throw const FormatException('Backup contains an unreferenced section');
    }
  }

  static bool _constantTimeEquals(String left, String right) {
    var difference = left.length ^ right.length;
    final length = min(left.length, right.length);
    for (var index = 0; index < length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

class _Counter {
  int value = 0;
  int attachmentEncodedBytes = 0;
}
