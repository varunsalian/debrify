import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'webdav_sync_models.dart';

typedef WebDavSyncRandomBytes = Uint8List Function(int length);
typedef WebDavSyncPayloadTransformer = Object? Function(Object? payload);

final class WebDavSyncWrongPassphraseException extends FormatException {
  const WebDavSyncWrongPassphraseException()
    : super('Invalid WebDAV sync key or tampered sync data');
}

final class WebDavSyncCircleKey {
  const WebDavSyncCircleKey._(this.secretKey);

  final SecretKey secretKey;
}

final class OpenedWebDavSyncRoot {
  const OpenedWebDavSyncRoot({required this.document, required this.key});

  final WebDavSyncRootDocument document;
  final WebDavSyncCircleKey key;
}

/// Versioned authenticated envelopes for the immutable root marker and every
/// manifest/section document beneath it.
///
/// Root KDF parameters are visible so a joining device can derive the key,
/// but the complete canonical header is AEAD associated data. A server cannot
/// weaken or swap those parameters without authentication failing. Documents
/// reuse the already-derived circle key and bind their root, author, logical
/// name, and schema version in their own AAD.
final class WebDavSyncCodec {
  WebDavSyncCodec({WebDavSyncRandomBytes? randomBytes})
    : _randomBytes = randomBytes ?? _secureRandomBytes;

  static const int rootFormatVersion = 1;
  static const int documentFormatVersion = 1;
  static const int currentSchemaFloor = 1;
  static const int rootMarkerMaxBytes = 64 * 1024;
  static const int defaultDocumentMaxBytes = 4 * 1024 * 1024;
  static const int defaultArgonMemoryKiB = 19456;
  static const int defaultArgonIterations = 2;
  static const int defaultArgonParallelism = 1;

  static const String _rootFormat = 'debrify-webdav-sync-root';
  static const String _documentFormat = 'debrify-webdav-sync-document';
  static const String _aeadAlgorithm = 'aes-256-gcm';
  static const String _kdfAlgorithm = 'argon2id';
  static const String _keyCheckContext = 'debrify-webdav-sync-key-check-v1';
  // A canonical legacy JSON payload can only begin with `null`, `true`,
  // `false`, a quote, a number, `[` or `{`. The leading NUL therefore makes
  // this in-plaintext marker impossible to confuse with any document emitted
  // by the legacy codec, without changing the authenticated envelope header.
  static const List<int> _compressedDocumentPrefix = <int>[
    0x00,
    0x44,
    0x42,
    0x52,
    0x46,
    0x59,
    0x2d,
    0x5a,
    0x4c,
    0x49,
    0x42,
    0x01,
  ];

  final WebDavSyncRandomBytes _randomBytes;

  static String generateSyncSecret() =>
      base64UrlEncode(_secureRandomBytes(32)).replaceAll('=', '');

  Future<Uint8List> sealRoot({
    required String passphrase,
    required String circleId,
    required DateTime createdAt,
    int schemaFloor = currentSchemaFloor,
    int memoryKiB = defaultArgonMemoryKiB,
    int iterations = defaultArgonIterations,
    int parallelism = defaultArgonParallelism,
    bool runInBackground = false,
  }) async {
    validatePassphrase(passphrase);
    _validateIdentifier(circleId, 'circle ID');
    _validateSchemaFloor(schemaFloor);
    _validateKdf(memoryKiB, iterations, parallelism);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    if (salt.length != 16 || nonce.length != 12) {
      throw StateError('Secure random source returned the wrong byte count');
    }
    if (runInBackground) {
      return Isolate.run(
        () => WebDavSyncCodec()._sealRoot(
          passphrase: passphrase,
          circleId: circleId,
          createdAt: createdAt,
          schemaFloor: schemaFloor,
          memoryKiB: memoryKiB,
          iterations: iterations,
          parallelism: parallelism,
          salt: salt,
          nonce: nonce,
        ),
      );
    }
    return _sealRoot(
      passphrase: passphrase,
      circleId: circleId,
      createdAt: createdAt,
      schemaFloor: schemaFloor,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      salt: salt,
      nonce: nonce,
    );
  }

  Future<Uint8List> _sealRoot({
    required String passphrase,
    required String circleId,
    required DateTime createdAt,
    required int schemaFloor,
    required int memoryKiB,
    required int iterations,
    required int parallelism,
    required List<int> salt,
    required List<int> nonce,
  }) async {
    final header = <String, Object?>{
      'format': _rootFormat,
      'version': rootFormatVersion,
      'encrypted': true,
      'kdf': <String, Object?>{
        'algorithm': _kdfAlgorithm,
        'salt': base64Encode(salt),
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
      },
      'aead': _aeadAlgorithm,
    };
    final key = await _deriveKey(
      passphrase,
      salt,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );
    final body = <String, Object?>{
      'circleId': circleId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'schemaFloor': schemaFloor,
      'keyCheck': await _keyCheck(key),
    };
    final box = await AesGcm.with256bits().encrypt(
      canonicalJsonBytes(body),
      secretKey: key,
      nonce: nonce,
      aad: canonicalJsonBytes(header),
    );
    final result = Uint8List.fromList(
      utf8.encode(
        canonicalJson(<String, Object?>{
          'header': header,
          'nonce': base64Encode(box.nonce),
          'ciphertext': base64Encode(<int>[
            ...box.cipherText,
            ...box.mac.bytes,
          ]),
        }),
      ),
    );
    if (result.length > rootMarkerMaxBytes) {
      throw const FormatException('WebDAV sync root marker exceeds its limit');
    }
    return result;
  }

  Future<OpenedWebDavSyncRoot> openRoot(
    List<int> encoded,
    String passphrase, {
    bool runInBackground = false,
  }) {
    final immutableBytes = Uint8List.fromList(encoded);
    if (runInBackground) {
      return Isolate.run(
        () => WebDavSyncCodec()._openRoot(immutableBytes, passphrase),
      );
    }
    return _openRoot(immutableBytes, passphrase);
  }

  Future<({WebDavSyncAuthorityFile authority, OpenedWebDavSyncRoot root})>
  openAuthority(List<int> encoded, {bool runInBackground = false}) async {
    try {
      final authority = WebDavSyncAuthorityFile.parse(encoded);
      final root = await openRoot(
        authority.markerBytes,
        authority.syncPassphrase,
        runInBackground: runInBackground,
      );
      return (authority: authority, root: root);
    } on WebDavSyncAuthorityFileException {
      rethrow;
    } catch (_) {
      throw const WebDavSyncAuthorityFileFormatException();
    }
  }

  /// The passphrase comes exclusively from the device-sealed secrets. Old
  /// assembled pins are tolerated only to extract their encrypted marker.
  Future<OpenedWebDavSyncRoot> openPinnedAuthority(
    List<int> encoded,
    String sealedPassphrase, {
    bool runInBackground = false,
  }) async {
    try {
      return await openRoot(
        webDavSyncInnerMarker(encoded),
        sealedPassphrase,
        runInBackground: runInBackground,
      );
    } catch (_) {
      throw const WebDavSyncAuthorityFileFormatException();
    }
  }

  Future<OpenedWebDavSyncRoot> _openRoot(
    List<int> encoded,
    String passphrase,
  ) async {
    validatePassphrase(passphrase);
    if (encoded.isEmpty || encoded.length > rootMarkerMaxBytes) {
      throw const FormatException('Invalid WebDAV sync root marker size');
    }
    final envelope = _decodeObject(encoded, 'WebDAV sync root marker');
    _requireOnlyKeys(envelope, const <String>{'header', 'nonce', 'ciphertext'});
    final header = _stringMap(envelope['header'], 'root header');
    _requireOnlyKeys(header, const <String>{
      'format',
      'version',
      'encrypted',
      'kdf',
      'aead',
    });
    final version = _boundedInt(header['version'], 1, 1, 'root version');
    if (version != rootFormatVersion) {
      throw const FormatException('Unsupported WebDAV sync root version');
    }
    if (header['format'] != _rootFormat ||
        header['encrypted'] != true ||
        header['aead'] != _aeadAlgorithm) {
      throw const FormatException('Unsupported WebDAV sync root marker');
    }
    final kdf = _stringMap(header['kdf'], 'root KDF');
    _requireOnlyKeys(kdf, const <String>{
      'algorithm',
      'salt',
      'memoryKiB',
      'iterations',
      'parallelism',
    });
    if (kdf['algorithm'] != _kdfAlgorithm) {
      throw const FormatException('Unsupported WebDAV sync root KDF');
    }
    final memoryKiB = _boundedInt(kdf['memoryKiB'], 8, 131072, 'KDF memory');
    final iterations = _boundedInt(kdf['iterations'], 1, 16, 'KDF iterations');
    final parallelism = _boundedInt(
      kdf['parallelism'],
      1,
      8,
      'KDF parallelism',
    );
    _validateKdf(memoryKiB, iterations, parallelism);
    final salt = _decodeBase64(
      kdf['salt'],
      'root KDF salt',
      maxEncodedChars: 64,
    );
    final nonce = _decodeBase64(
      envelope['nonce'],
      'root nonce',
      maxEncodedChars: 64,
    );
    final ciphertext = _decodeBase64(
      envelope['ciphertext'],
      'root ciphertext',
      maxEncodedChars: rootMarkerMaxBytes,
    );
    if (salt.length != 16 || nonce.length != 12 || ciphertext.length < 16) {
      throw const FormatException('Corrupt WebDAV sync root marker');
    }
    final key = await _deriveKey(
      passphrase,
      salt,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );
    final List<int> clear;
    try {
      clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          ciphertext.sublist(0, ciphertext.length - 16),
          nonce: nonce,
          mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
        ),
        secretKey: key,
        aad: canonicalJsonBytes(header),
      );
    } on SecretBoxAuthenticationError {
      throw const WebDavSyncWrongPassphraseException();
    }
    final body = _decodeObject(clear, 'WebDAV sync root body');
    _requireOnlyKeys(body, const <String>{
      'circleId',
      'createdAt',
      'schemaFloor',
      'keyCheck',
    });
    final circleId = body['circleId'];
    final createdAtSource = body['createdAt'];
    final keyCheck = body['keyCheck'];
    if (circleId is! String ||
        createdAtSource is! String ||
        keyCheck is! String) {
      throw const FormatException('Invalid WebDAV sync root body');
    }
    _validateIdentifier(circleId, 'circle ID');
    final schemaFloor = _boundedInt(
      body['schemaFloor'],
      1,
      currentSchemaFloor,
      'schema floor',
    );
    _validateSchemaFloor(schemaFloor);
    final createdAt = DateTime.tryParse(createdAtSource);
    if (createdAt == null || createdAtSource.length > 40) {
      throw const FormatException('Invalid WebDAV sync root timestamp');
    }
    if (!_constantTimeEquals(await _keyCheck(key), keyCheck)) {
      throw const WebDavSyncWrongPassphraseException();
    }
    return OpenedWebDavSyncRoot(
      document: WebDavSyncRootDocument(
        circleId: circleId,
        createdAt: createdAt.toUtc(),
        schemaFloor: schemaFloor,
        kdfSalt: Uint8List.fromList(salt),
      ),
      key: WebDavSyncCircleKey._(key),
    );
  }

  Future<Uint8List> sealDocument({
    required WebDavSyncCircleKey key,
    required String circleId,
    required String deviceId,
    required String logicalName,
    required int schemaVersion,
    required Object? payload,
    WebDavSyncPayloadTransformer? payloadEncoder,
    int maxBytes = defaultDocumentMaxBytes,
    bool runInBackground = false,
  }) async {
    _validateDocumentIdentity(
      circleId: circleId,
      deviceId: deviceId,
      logicalName: logicalName,
      schemaVersion: schemaVersion,
    );
    _validateDocumentMaxBytes(maxBytes);
    final nonce = _randomBytes(12);
    if (nonce.length != 12) {
      throw StateError('Secure random source returned the wrong byte count');
    }
    if (runInBackground) {
      final keyBytes = Uint8List.fromList(await key.secretKey.extractBytes());
      return Isolate.run(
        () => WebDavSyncCodec()._sealDocument(
          key: WebDavSyncCircleKey._(SecretKey(keyBytes)),
          circleId: circleId,
          deviceId: deviceId,
          logicalName: logicalName,
          schemaVersion: schemaVersion,
          payload: payload,
          payloadEncoder: payloadEncoder,
          maxBytes: maxBytes,
          nonce: nonce,
        ),
      );
    }
    return _sealDocument(
      key: key,
      circleId: circleId,
      deviceId: deviceId,
      logicalName: logicalName,
      schemaVersion: schemaVersion,
      payload: payload,
      payloadEncoder: payloadEncoder,
      maxBytes: maxBytes,
      nonce: nonce,
    );
  }

  Future<Uint8List> _sealDocument({
    required WebDavSyncCircleKey key,
    required String circleId,
    required String deviceId,
    required String logicalName,
    required int schemaVersion,
    required Object? payload,
    required WebDavSyncPayloadTransformer? payloadEncoder,
    required int maxBytes,
    required List<int> nonce,
  }) async {
    final encodedPayload = canonicalJsonBytes(
      payloadEncoder == null ? payload : payloadEncoder(payload),
    );
    if (encodedPayload.length > maxBytes) {
      throw const FormatException('WebDAV sync document exceeds its limit');
    }
    final clear = Uint8List.fromList(<int>[
      ..._compressedDocumentPrefix,
      ...zlib.encode(encodedPayload),
    ]);
    final header = _documentHeader(
      circleId: circleId,
      deviceId: deviceId,
      logicalName: logicalName,
      schemaVersion: schemaVersion,
    );
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: key.secretKey,
      nonce: nonce,
      aad: canonicalJsonBytes(header),
    );
    final encoded = Uint8List.fromList(
      utf8.encode(
        canonicalJson(<String, Object?>{
          'header': header,
          'nonce': base64Encode(box.nonce),
          'ciphertext': base64Encode(<int>[
            ...box.cipherText,
            ...box.mac.bytes,
          ]),
        }),
      ),
    );
    if (encoded.length > maxBytes) {
      throw const FormatException('WebDAV sync document exceeds its limit');
    }
    return encoded;
  }

  Future<Object?> openDocument({
    required WebDavSyncCircleKey key,
    required List<int> encoded,
    required String circleId,
    required String deviceId,
    required String logicalName,
    required int schemaVersion,
    WebDavSyncPayloadTransformer? payloadDecoder,
    int maxBytes = defaultDocumentMaxBytes,
    bool runInBackground = false,
  }) async {
    _validateDocumentIdentity(
      circleId: circleId,
      deviceId: deviceId,
      logicalName: logicalName,
      schemaVersion: schemaVersion,
    );
    _validateDocumentMaxBytes(maxBytes);
    if (encoded.isEmpty || encoded.length > maxBytes) {
      throw const FormatException('Invalid WebDAV sync document size');
    }
    if (runInBackground) {
      final keyBytes = Uint8List.fromList(await key.secretKey.extractBytes());
      final encodedBytes = encoded is Uint8List
          ? encoded
          : Uint8List.fromList(encoded);
      final transferred = TransferableTypedData.fromList(<TypedData>[
        encodedBytes,
      ]);
      return Isolate.run(
        () => WebDavSyncCodec()._openDocument(
          key: WebDavSyncCircleKey._(SecretKey(keyBytes)),
          encoded: transferred.materialize().asUint8List(),
          circleId: circleId,
          deviceId: deviceId,
          logicalName: logicalName,
          schemaVersion: schemaVersion,
          payloadDecoder: payloadDecoder,
          maxBytes: maxBytes,
        ),
      );
    }
    return _openDocument(
      key: key,
      encoded: encoded,
      circleId: circleId,
      deviceId: deviceId,
      logicalName: logicalName,
      schemaVersion: schemaVersion,
      payloadDecoder: payloadDecoder,
      maxBytes: maxBytes,
    );
  }

  Future<Object?> _openDocument({
    required WebDavSyncCircleKey key,
    required List<int> encoded,
    required String circleId,
    required String deviceId,
    required String logicalName,
    required int schemaVersion,
    required WebDavSyncPayloadTransformer? payloadDecoder,
    required int maxBytes,
  }) async {
    final envelope = _decodeObject(encoded, 'WebDAV sync document');
    _requireOnlyKeys(envelope, const <String>{'header', 'nonce', 'ciphertext'});
    final header = _stringMap(envelope['header'], 'document header');
    final expectedHeader = _documentHeader(
      circleId: circleId,
      deviceId: deviceId,
      logicalName: logicalName,
      schemaVersion: schemaVersion,
    );
    _requireOnlyKeys(header, expectedHeader.keys.toSet());
    if (header.entries.any(
      (entry) => expectedHeader[entry.key] != entry.value,
    )) {
      throw const FormatException('WebDAV sync document identity mismatch');
    }
    final nonce = _decodeBase64(
      envelope['nonce'],
      'document nonce',
      maxEncodedChars: 64,
    );
    final ciphertext = _decodeBase64(
      envelope['ciphertext'],
      'document ciphertext',
      // The complete encoded envelope was already bounded above. Keep the
      // inner bound tied to the caller's section limit as well; a fixed small
      // ceiling would make valid near-limit graph packages unreadable.
      maxEncodedChars: maxBytes,
    );
    if (nonce.length != 12 || ciphertext.length < 16) {
      throw const FormatException('Corrupt WebDAV sync document');
    }
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          ciphertext.sublist(0, ciphertext.length - 16),
          nonce: nonce,
          mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
        ),
        secretKey: key.secretKey,
        aad: canonicalJsonBytes(header),
      );
      final payloadBytes = _openDocumentPayload(clear, maxBytes);
      final payload = jsonDecode(utf8.decode(payloadBytes));
      return payloadDecoder == null ? payload : payloadDecoder(payload);
    } on SecretBoxAuthenticationError {
      throw const FormatException('WebDAV sync document authentication failed');
    }
  }

  static Uint8List _openDocumentPayload(List<int> clear, int maxBytes) {
    if (clear.length > maxBytes) {
      throw const FormatException('WebDAV sync document exceeds its limit');
    }
    if (!_startsWith(clear, _compressedDocumentPrefix)) {
      return clear is Uint8List ? clear : Uint8List.fromList(clear);
    }
    try {
      return _inflateBounded(
        clear.sublist(_compressedDocumentPrefix.length),
        maxBytes,
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid compressed WebDAV sync document', error);
    }
  }

  static Uint8List _inflateBounded(List<int> compressed, int maxBytes) {
    final output = _BoundedByteSink(maxBytes);
    final input = zlib.decoder.startChunkedConversion(output);
    input.add(compressed);
    input.close();
    return output.takeBytes();
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }

  static Map<String, Object?> _documentHeader({
    required String circleId,
    required String deviceId,
    required String logicalName,
    required int schemaVersion,
  }) => <String, Object?>{
    'format': _documentFormat,
    'version': documentFormatVersion,
    'circleId': circleId,
    'deviceId': deviceId,
    'logicalName': logicalName,
    'schemaVersion': schemaVersion,
    'aead': _aeadAlgorithm,
  };

  static void _validateDocumentIdentity({
    required String circleId,
    required String deviceId,
    required String logicalName,
    required int schemaVersion,
  }) {
    _validateIdentifier(circleId, 'circle ID');
    _validateIdentifier(deviceId, 'device ID');
    if (logicalName.isEmpty ||
        logicalName.length > 160 ||
        logicalName.contains('..') ||
        logicalName.startsWith('/') ||
        logicalName.endsWith('/') ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$').hasMatch(logicalName)) {
      throw ArgumentError.value(logicalName, 'logicalName');
    }
    if (schemaVersion < 1 || schemaVersion > 0x7fffffff) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
  }

  static void _validateDocumentMaxBytes(int maxBytes) {
    if (maxBytes < 256 || maxBytes > 256 * 1024 * 1024) {
      throw RangeError.range(maxBytes, 256, 256 * 1024 * 1024, 'maxBytes');
    }
  }

  static Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt, {
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) => Argon2id(
    parallelism: parallelism,
    memory: memoryKiB,
    iterations: iterations,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);

  static Future<String> _keyCheck(SecretKey key) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(_keyCheckContext),
      secretKey: key,
    );
    return base64UrlEncode(mac.bytes).replaceAll('=', '');
  }

  static void validatePassphrase(String passphrase) {
    if (passphrase.length < 8 || utf8.encode(passphrase).length > 1024) {
      throw ArgumentError(
        'Sync passphrase must contain between 8 characters and 1024 bytes',
      );
    }
  }

  static void _validateIdentifier(String value, String label) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$').hasMatch(value)) {
      throw FormatException('Invalid WebDAV sync $label');
    }
  }

  static void _validateSchemaFloor(int value) {
    if (value < 1 || value > currentSchemaFloor) {
      throw const FormatException('Unsupported WebDAV sync schema floor');
    }
  }

  static void _validateKdf(int memoryKiB, int iterations, int parallelism) {
    if (parallelism < 1 ||
        parallelism > 8 ||
        memoryKiB < 8 * parallelism ||
        memoryKiB > 131072 ||
        iterations < 1 ||
        iterations > 16) {
      throw const FormatException('Unsafe WebDAV sync KDF parameters');
    }
  }

  static int _boundedInt(
    Object? value,
    int minimum,
    int maximum,
    String label,
  ) {
    if (value is! int || value < minimum || value > maximum) {
      throw FormatException('Invalid WebDAV sync $label');
    }
    return value;
  }

  static Map<String, dynamic> _decodeObject(List<int> bytes, String label) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('$label must be an object');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid $label', error);
    }
  }

  static Map<String, dynamic> _stringMap(Object? value, String label) {
    if (value is! Map) throw FormatException('Invalid WebDAV sync $label');
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw FormatException('Invalid WebDAV sync $label');
    }
  }

  static Uint8List _decodeBase64(
    Object? value,
    String label, {
    required int maxEncodedChars,
  }) {
    if (value is! String || value.length > maxEncodedChars) {
      throw FormatException('Invalid WebDAV sync $label');
    }
    try {
      return Uint8List.fromList(base64Decode(value));
    } on FormatException {
      throw FormatException('Invalid WebDAV sync $label');
    }
  }

  static void _requireOnlyKeys(
    Map<String, dynamic> value,
    Set<String> expected,
  ) {
    if (value.length != expected.length ||
        value.keys.any((key) => !expected.contains(key))) {
      throw const FormatException('Unexpected WebDAV sync envelope fields');
    }
  }

  static bool _constantTimeEquals(String left, String right) {
    final a = utf8.encode(left);
    final b = utf8.encode(right);
    var difference = a.length ^ b.length;
    final length = max(a.length, b.length);
    for (var index = 0; index < length; index++) {
      difference |=
          (index < a.length ? a[index] : 0) ^ (index < b.length ? b[index] : 0);
    }
    return difference == 0;
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List canonicalJsonBytes(Object? value) =>
      Uint8List.fromList(utf8.encode(canonicalJson(value)));

  static String canonicalJson(Object? value) => jsonEncode(_canonical(value));

  static Object? _canonical(Object? value) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const FormatException('Non-finite WebDAV sync number');
      }
      return value;
    }
    if (value is List) {
      return <Object?>[for (final item in value) _canonical(item)];
    }
    if (value is Map) {
      final keys = value.keys.toList(growable: false);
      if (keys.any((key) => key is! String)) {
        throw const FormatException('WebDAV sync maps require string keys');
      }
      final sorted = keys.cast<String>()..sort();
      return <String, Object?>{
        for (final key in sorted) key: _canonical(value[key]),
      };
    }
    throw const FormatException('Unsupported WebDAV sync JSON value');
  }
}

final class _BoundedByteSink implements Sink<List<int>> {
  _BoundedByteSink(this.maxBytes);

  final int maxBytes;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  var _length = 0;

  @override
  void add(List<int> data) {
    _length += data.length;
    if (_length > maxBytes) {
      throw const FormatException('WebDAV sync document exceeds its limit');
    }
    _bytes.add(data);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}
