import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'profile_database_snapshot.dart';
import 'profile_avatar_ingest.dart';
import 'sanitized_profile_preferences.dart';
import '../../models/profiles/profile_avatar.dart';

class PortableProfilePackage {
  static const int version = 3;
  static const int maxEnvelopeBytes = 128 * 1024 * 1024;
  static const int maxExpandedBytes = 256 * 1024 * 1024;
  static const int maxProfiles = 64;
  static const int maxResources = 1024;
  static const int maxRecords = 250000;
  static const int maxDepth = 32;
  static const int maxStringBytes = 4 * 1024 * 1024;
  static const int maxAttachmentBytes = 64 * 1024 * 1024;
  static const int maxTotalAttachmentBytes = 128 * 1024 * 1024;

  final String mode;
  final DateTime createdAt;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> resources;
  final Map<String, dynamic> sections;
  final Map<String, dynamic> omissions;

  const PortableProfilePackage({
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
  ) => _decodeMap(decoded, authenticatedEncryption: false);

  static Future<PortableProfilePackage> _decodeMap(
    Map<String, dynamic> decoded, {
    required bool authenticatedEncryption,
  }) async {
    if (decoded['encrypted'] == true) {
      throw const FormatException('Encrypted package must be unlocked first');
    }
    if (decoded['format'] != 'debrify-profile-package' ||
        decoded['version'] != version) {
      throw const FormatException('Unsupported profile backup format');
    }
    final integrity = decoded['integrity'];
    if (integrity is! Map ||
        integrity['algorithm'] != 'sha256' ||
        integrity['digest'] is! String) {
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
    final profiles = body['profiles'];
    final resources = body['resources'];
    final sections = body['sections'];
    if (profiles is! List ||
        resources is! List ||
        sections is! Map<String, dynamic> ||
        profiles.length > maxProfiles ||
        resources.length > maxResources) {
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
    await _verifySections(profileMaps, sections);
    return PortableProfilePackage(
      mode: body['mode'] as String? ?? 'singleProfile',
      createdAt: DateTime.parse(body['createdAt']! as String).toUtc(),
      profiles: profileMaps,
      resources: resourceMaps,
      sections: Map<String, dynamic>.from(sections),
      omissions: body['omissions'] is Map
          ? Map<String, dynamic>.from(body['omissions'] as Map)
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
    final salt = _randomBytes(16);
    final key = await Argon2id(
      parallelism: parallelism,
      memory: memory,
      iterations: iterations,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    const aadText = 'debrify-profile-backup-v3';
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
      throw const FormatException(
        'Backup is too large to export as one portable package',
      );
    }
  }

  static Future<PortableProfilePackage> decrypt(
    Map<String, dynamic> envelope,
    String passphrase,
  ) async {
    final kdf = envelope['kdf'];
    final aead = envelope['aead'];
    if (envelope['format'] != 'debrify-profile-package' ||
        envelope['version'] != version ||
        envelope['encrypted'] != true ||
        kdf is! Map ||
        aead is! Map ||
        kdf['algorithm'] != 'argon2id' ||
        aead['algorithm'] != 'aes-256-gcm' ||
        aead['aad'] != 'debrify-profile-backup-v3') {
      throw const FormatException('Unsupported encrypted profile backup');
    }
    int bounded(Object? value, int min, int max) {
      if (value is! num) throw const FormatException('Invalid KDF parameters');
      final number = value.toInt();
      if (number < min || number > max) {
        throw const FormatException('Unsafe KDF parameters');
      }
      return number;
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
      return _decodeMap(decoded, authenticatedEncryption: true);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong passphrase or tampered backup');
    }
  }

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
      if ((!attachmentData && bytes > maxStringBytes) ||
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
    Map<String, dynamic> sections,
  ) async {
    final referenced = <String>{};
    for (final profile in profiles) {
      final id = profile['preferencesSection'];
      if (id is! String || id.isEmpty || !referenced.add(id)) {
        throw const FormatException('Invalid profile preference section');
      }
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
              attachment['bytes'] is! num ||
              attachment['sha256'] is! String ||
              attachment['data'] is! String) {
            throw const FormatException('Invalid portable file attachment');
          }
          final claimedBytes = (attachment['bytes'] as num).toInt();
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
            avatarFile['bytes'] is! num ||
            avatarFile['sha256'] is! String ||
            avatarFile['data'] is! String) {
          throw const FormatException('Invalid portable avatar attachment');
        }
        final claimed = (avatarFile['bytes'] as num).toInt();
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
        if (attachment['encoding'] != 'base64' ||
            attachment['bytes'] is! num ||
            attachment['sha256'] is! String ||
            attachment['data'] is! String) {
          throw const FormatException('Invalid database attachment');
        }
        final claimedBytes = (attachment['bytes'] as num).toInt();
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
