import 'dart:convert';

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_hot_models.dart';

/// One independently mergeable nullable registry leaf.
///
/// A null value is the record tombstone. It intentionally carries exactly the
/// same stamp as a live value and is retained by merge indefinitely.
final class WebDavSyncCircleLeaf<T> {
  const WebDavSyncCircleLeaf({required this.stamp, required this.value});

  final WebDavSyncStamp stamp;
  final T? value;

  Map<String, Object?> toJson(Object? Function(T value) encode) =>
      <String, Object?>{
        'stamp': stamp.toJson(),
        'value': value == null ? null : encode(value as T),
      };
}

final class WebDavSyncResourceMetadata {
  const WebDavSyncResourceMetadata({
    required this.type,
    required this.label,
    required this.ownerCircleProfileId,
    required this.publicConfig,
    required this.publicSchemaVersion,
    required this.enabled,
  });

  final ConnectionResourceType type;
  final String label;
  final String ownerCircleProfileId;
  final Map<String, Object?> publicConfig;
  final int publicSchemaVersion;
  final bool enabled;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.name,
    'label': label,
    'ownerCircleProfileId': ownerCircleProfileId,
    'publicConfig': publicConfig,
    'publicSchemaVersion': publicSchemaVersion,
    'enabled': enabled,
  };

  factory WebDavSyncResourceMetadata.fromJson(Object? source) {
    final json = _object(source, 'resource metadata');
    _onlyKeys(json, const <String>{
      'type',
      'label',
      'ownerCircleProfileId',
      'publicConfig',
      'publicSchemaVersion',
      'enabled',
    });
    final type = _enumByName(
      ConnectionResourceType.values,
      json['type'],
      'resource type',
    );
    final label = _nonEmptyString(json['label'], 'resource label', max: 1024);
    final owner = _syncId(json['ownerCircleProfileId'], 'resource owner');
    final publicConfig = _jsonObject(
      json['publicConfig'],
      'resource public config',
    );
    final schema = _positiveInt(
      json['publicSchemaVersion'],
      'resource public schema',
    );
    if (publicConfig['schemaVersion'] != schema || json['enabled'] is! bool) {
      throw const FormatException('Invalid WebDAV sync resource metadata');
    }
    return WebDavSyncResourceMetadata(
      type: type,
      label: label,
      ownerCircleProfileId: owner,
      publicConfig: publicConfig,
      publicSchemaVersion: schema,
      enabled: json['enabled']! as bool,
    );
  }
}

final class WebDavSyncResourceSecretConfig {
  const WebDavSyncResourceSecretConfig({
    required this.semanticDigest,
    required this.type,
    required this.ownerCircleProfileId,
    required this.publicSchemaVersion,
    required this.payloadVersion,
    required this.envelope,
  });

  final String semanticDigest;
  final ConnectionResourceType type;
  final String ownerCircleProfileId;
  final int publicSchemaVersion;
  final int payloadVersion;
  final String envelope;

  Map<String, Object?> toJson() => <String, Object?>{
    'semanticDigest': semanticDigest,
    'type': type.name,
    'ownerCircleProfileId': ownerCircleProfileId,
    'publicSchemaVersion': publicSchemaVersion,
    'payloadVersion': payloadVersion,
    'envelope': envelope,
  };

  factory WebDavSyncResourceSecretConfig.fromJson(Object? source) {
    final json = _object(source, 'resource secret config');
    _onlyKeys(json, const <String>{
      'semanticDigest',
      'type',
      'ownerCircleProfileId',
      'publicSchemaVersion',
      'payloadVersion',
      'envelope',
    });
    final digest = _digest(json['semanticDigest'], 'resource secret digest');
    final envelope = _nonEmptyString(
      json['envelope'],
      'resource secret envelope',
      max: WebDavSyncLimits.maxGraphDocumentBytes,
    );
    try {
      final decoded = base64Decode(envelope);
      if (base64Encode(decoded) != envelope) {
        throw const FormatException('Invalid WebDAV sync resource envelope');
      }
    } on FormatException {
      throw const FormatException('Invalid WebDAV sync resource envelope');
    }
    return WebDavSyncResourceSecretConfig(
      semanticDigest: digest,
      type: _enumByName(
        ConnectionResourceType.values,
        json['type'],
        'resource secret type',
      ),
      ownerCircleProfileId: _syncId(
        json['ownerCircleProfileId'],
        'resource secret owner',
      ),
      publicSchemaVersion: _positiveInt(
        json['publicSchemaVersion'],
        'resource secret public schema',
      ),
      payloadVersion: _positiveInt(
        json['payloadVersion'],
        'resource secret payload version',
      ),
      envelope: envelope,
    );
  }
}

final class WebDavSyncResourceEntry {
  const WebDavSyncResourceEntry({required this.metadata, this.secretConfig});

  final WebDavSyncCircleLeaf<WebDavSyncResourceMetadata> metadata;
  final WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>? secretConfig;

  Map<String, Object?> toJson() => <String, Object?>{
    'metadata': metadata.toJson((value) => value.toJson()),
    if (secretConfig != null)
      'secretConfig': secretConfig!.toJson((value) => value.toJson()),
  };

  factory WebDavSyncResourceEntry.fromJson(Object? source) {
    final json = _object(source, 'resource entry');
    _onlyKeysWithOptional(
      json,
      required: const <String>{'metadata'},
      optional: const <String>{'secretConfig'},
    );
    if (!json.containsKey('metadata')) {
      throw const FormatException('Resource metadata is required');
    }
    return WebDavSyncResourceEntry(
      metadata: _leaf(
        json['metadata'],
        'resource metadata leaf',
        WebDavSyncResourceMetadata.fromJson,
      ),
      secretConfig: json.containsKey('secretConfig')
          ? _leaf(
              json['secretConfig'],
              'resource secret leaf',
              WebDavSyncResourceSecretConfig.fromJson,
            )
          : null,
    );
  }
}

final class WebDavSyncGrantValue {
  const WebDavSyncGrantValue({required this.permissions});

  final int permissions;

  Map<String, Object?> toJson() => <String, Object?>{
    'permissions': permissions,
  };

  factory WebDavSyncGrantValue.fromJson(Object? source) {
    final json = _object(source, 'grant value');
    _onlyKeys(json, const <String>{'permissions'});
    final permissions = json['permissions'];
    final known = ResourcePermission.values.fold<int>(
      0,
      (mask, permission) => mask | permission.bit,
    );
    if (permissions is! int || permissions < 0 || permissions & ~known != 0) {
      throw const FormatException('Invalid WebDAV sync grant permissions');
    }
    return WebDavSyncGrantValue(permissions: permissions);
  }
}

final class WebDavSyncSettingsValue {
  const WebDavSyncSettingsValue({
    required this.enabled,
    required this.settings,
  });

  final bool enabled;
  final Map<String, Object?> settings;

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'settings': settings,
  };

  factory WebDavSyncSettingsValue.fromJson(Object? source) {
    final json = _object(source, 'settings value');
    _onlyKeys(json, const <String>{'enabled', 'settings'});
    if (json['enabled'] is! bool) {
      throw const FormatException('Invalid WebDAV sync resource settings');
    }
    final settings = _jsonObject(json['settings'], 'resource settings');
    if (utf8.encode(WebDavSyncCodec.canonicalJson(settings)).length >
        64 * 1024) {
      throw const FormatException('WebDAV sync resource settings too large');
    }
    return WebDavSyncSettingsValue(
      enabled: json['enabled']! as bool,
      settings: settings,
    );
  }
}

final class WebDavSyncBindingValue {
  const WebDavSyncBindingValue({required this.circleResourceId});

  final String circleResourceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'circleResourceId': circleResourceId,
  };

  factory WebDavSyncBindingValue.fromJson(Object? source) {
    final json = _object(source, 'binding value');
    _onlyKeys(json, const <String>{'circleResourceId'});
    return WebDavSyncBindingValue(
      circleResourceId: _syncId(
        json['circleResourceId'],
        'binding resource ID',
      ),
    );
  }
}

final class WebDavSyncResourcesDocument {
  const WebDavSyncResourcesDocument({
    required this.resources,
    required this.grants,
    required this.settings,
    required this.bindings,
  });

  static const int schemaVersion = 1;

  final Map<String, WebDavSyncResourceEntry> resources;
  final Map<String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>
  grants;
  final Map<String, Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>>
  settings;
  final Map<String, Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>>
  bindings;

  int get leafCount =>
      resources.values.fold<int>(
        0,
        (count, value) => count + 1 + (value.secretConfig == null ? 0 : 1),
      ) +
      _nestedLeafCount(grants) +
      _nestedLeafCount(settings) +
      _nestedLeafCount(bindings);

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'resources': <String, Object?>{
      for (final entry in resources.entries) entry.key: entry.value.toJson(),
    },
    'grants': _encodeNested(grants, (value) => value.toJson()),
    'settings': _encodeNested(settings, (value) => value.toJson()),
    'bindings': _encodeNested(bindings, (value) => value.toJson()),
  };

  String get semanticDigest => semanticDigestOf(toJson());

  factory WebDavSyncResourcesDocument.fromJson(Object? source) {
    final json = _object(source, 'resources document');
    if (utf8.encode(WebDavSyncCodec.canonicalJson(json)).length >
        WebDavSyncLimits.maxGraphDocumentBytes) {
      throw const FormatException('WebDAV sync resources exceed size limit');
    }
    _onlyKeys(json, const <String>{
      'version',
      'resources',
      'grants',
      'settings',
      'bindings',
    });
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported WebDAV sync resources schema');
    }
    final rawResources = _object(json['resources'], 'resources');
    final resources = <String, WebDavSyncResourceEntry>{};
    for (final entry in rawResources.entries) {
      resources[_syncId(entry.key, 'circle resource ID')] =
          WebDavSyncResourceEntry.fromJson(entry.value);
    }
    final document = WebDavSyncResourcesDocument(
      resources: Map<String, WebDavSyncResourceEntry>.unmodifiable(resources),
      grants: _decodeNested(
        json['grants'],
        'grants',
        WebDavSyncGrantValue.fromJson,
      ),
      settings: _decodeNested(
        json['settings'],
        'settings',
        WebDavSyncSettingsValue.fromJson,
      ),
      bindings: _decodeNested(
        json['bindings'],
        'bindings',
        WebDavSyncBindingValue.fromJson,
        secondIsSlot: true,
      ),
    );
    if (document.leafCount > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException('Too many WebDAV sync resource records');
    }
    return document;
  }

  static Map<String, Object?> _encodeNested<T>(
    Map<String, Map<String, WebDavSyncCircleLeaf<T>>> source,
    Object? Function(T value) encode,
  ) => <String, Object?>{
    for (final outer in source.entries)
      outer.key: <String, Object?>{
        for (final inner in outer.value.entries)
          inner.key: inner.value.toJson(encode),
      },
  };
}

final class WebDavSyncProfilePin {
  const WebDavSyncProfilePin({
    this.hash,
    this.salt,
    this.paramsJson,
    this.recoveryHash,
    this.recoverySalt,
    this.recoveryParamsJson,
    required this.resetRequired,
  });

  final String? hash;
  final String? salt;
  final String? paramsJson;
  final String? recoveryHash;
  final String? recoverySalt;
  final String? recoveryParamsJson;
  final bool resetRequired;

  bool get hasPin => hash != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'hash': hash,
    'salt': salt,
    'paramsJson': paramsJson,
    'recoveryHash': recoveryHash,
    'recoverySalt': recoverySalt,
    'recoveryParamsJson': recoveryParamsJson,
    'resetRequired': resetRequired,
  };

  factory WebDavSyncProfilePin.fromJson(Object? source) {
    final json = _object(source, 'profile PIN');
    _onlyKeys(json, const <String>{
      'hash',
      'salt',
      'paramsJson',
      'recoveryHash',
      'recoverySalt',
      'recoveryParamsJson',
      'resetRequired',
    });
    if (json['resetRequired'] is! bool) {
      throw const FormatException('Invalid WebDAV sync PIN record');
    }
    String? optionalBytes(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.isEmpty || value.length > 64 * 1024) {
        throw const FormatException('Invalid WebDAV sync PIN record');
      }
      try {
        final decoded = base64Decode(value);
        if (decoded.isEmpty || base64Encode(decoded) != value) {
          throw const FormatException('Invalid WebDAV sync PIN record');
        }
      } on FormatException {
        throw const FormatException('Invalid WebDAV sync PIN record');
      }
      return value;
    }

    String? optionalJson(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.isEmpty || value.length > 64 * 1024) {
        throw const FormatException('Invalid WebDAV sync PIN record');
      }
      _jsonObject(jsonDecode(value), 'PIN params');
      return value;
    }

    final result = WebDavSyncProfilePin(
      hash: optionalBytes('hash'),
      salt: optionalBytes('salt'),
      paramsJson: optionalJson('paramsJson'),
      recoveryHash: optionalBytes('recoveryHash'),
      recoverySalt: optionalBytes('recoverySalt'),
      recoveryParamsJson: optionalJson('recoveryParamsJson'),
      resetRequired: json['resetRequired']! as bool,
    );
    final pinParts = <Object?>[result.hash, result.salt, result.paramsJson];
    final recoveryParts = <Object?>[
      result.recoveryHash,
      result.recoverySalt,
      result.recoveryParamsJson,
    ];
    final pinCount = pinParts.where((value) => value != null).length;
    final recoveryCount = recoveryParts.where((value) => value != null).length;
    if ((pinCount != 0 && pinCount != 3) ||
        (recoveryCount != 0 && recoveryCount != 3) ||
        (recoveryCount == 3 && pinCount != 3)) {
      throw const FormatException('Incomplete WebDAV sync PIN record');
    }
    return result;
  }
}

final class WebDavSyncProfileValue {
  const WebDavSyncProfileValue({
    required this.name,
    this.avatarKey,
    required this.role,
    required this.policy,
    required this.enabled,
    required this.lockOnResume,
    this.inactivityTimeoutMinutes,
    required this.setupComplete,
    required this.lifecycle,
    required this.pin,
  });

  final String name;
  final String? avatarKey;
  final UserProfileRole role;
  final Map<String, Object?> policy;
  final bool enabled;
  final bool lockOnResume;
  final int? inactivityTimeoutMinutes;
  final bool setupComplete;
  final UserProfileLifecycle lifecycle;
  final WebDavSyncProfilePin pin;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'avatarKey': avatarKey,
    'role': role.name,
    'policy': policy,
    'enabled': enabled,
    'lockOnResume': lockOnResume,
    'inactivityTimeoutMinutes': inactivityTimeoutMinutes,
    'setupComplete': setupComplete,
    'lifecycle': lifecycle.name,
    'pin': pin.toJson(),
  };

  factory WebDavSyncProfileValue.fromJson(Object? source) {
    final json = _object(source, 'profile value');
    _onlyKeys(json, const <String>{
      'name',
      'avatarKey',
      'role',
      'policy',
      'enabled',
      'lockOnResume',
      'inactivityTimeoutMinutes',
      'setupComplete',
      'lifecycle',
      'pin',
    });
    final role = _enumByName(
      UserProfileRole.values,
      json['role'],
      'profile role',
    );
    final policy = _jsonObject(json['policy'], 'profile policy');
    // Decode through the authority model as well as checking JSON shape.
    ProfilePolicy.decode(jsonEncode(policy), role);
    final avatar = json['avatarKey'];
    if (avatar != null) {
      if (avatar is! String) {
        throw const FormatException('Invalid WebDAV sync profile avatar');
      }
      final parsed = ProfileAvatar.tryParse(avatar);
      if (parsed == null || parsed.kind == ProfileAvatarKind.image) {
        throw const FormatException('Invalid WebDAV sync profile avatar');
      }
    }
    final timeout = json['inactivityTimeoutMinutes'];
    if (timeout != null &&
        (timeout is! int || !const <int>{5, 15, 30, 60}.contains(timeout))) {
      throw const FormatException('Invalid WebDAV sync inactivity timeout');
    }
    if (json['enabled'] is! bool ||
        json['lockOnResume'] is! bool ||
        json['setupComplete'] is! bool) {
      throw const FormatException('Invalid WebDAV sync profile flags');
    }
    return WebDavSyncProfileValue(
      name: _nonEmptyString(json['name'], 'profile name', max: 1024),
      avatarKey: avatar as String?,
      role: role,
      policy: policy,
      enabled: json['enabled']! as bool,
      lockOnResume: json['lockOnResume']! as bool,
      inactivityTimeoutMinutes: timeout as int?,
      setupComplete: json['setupComplete']! as bool,
      lifecycle: _enumByName(
        UserProfileLifecycle.values,
        json['lifecycle'],
        'profile lifecycle',
      ),
      pin: WebDavSyncProfilePin.fromJson(json['pin']),
    );
  }
}

final class WebDavSyncProfilesDocument {
  const WebDavSyncProfilesDocument({required this.profiles});

  static const int schemaVersion = 1;

  final Map<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>> profiles;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'profiles': <String, Object?>{
      for (final entry in profiles.entries)
        entry.key: entry.value.toJson((value) => value.toJson()),
    },
  };

  String get semanticDigest => semanticDigestOf(toJson());

  factory WebDavSyncProfilesDocument.fromJson(Object? source) {
    final json = _object(source, 'profiles document');
    if (utf8.encode(WebDavSyncCodec.canonicalJson(json)).length >
        WebDavSyncLimits.maxHotDocumentBytes) {
      throw const FormatException('WebDAV sync profiles exceed size limit');
    }
    _onlyKeys(json, const <String>{'version', 'profiles'});
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported WebDAV sync profiles schema');
    }
    final raw = _object(json['profiles'], 'profiles');
    if (raw.length > WebDavSyncLimits.maxMapEntries) {
      throw const FormatException('Too many WebDAV sync profiles');
    }
    return WebDavSyncProfilesDocument(
      profiles:
          Map<
            String,
            WebDavSyncCircleLeaf<WebDavSyncProfileValue>
          >.unmodifiable(<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            for (final entry in raw.entries)
              _syncId(entry.key, 'circle profile ID'): _leaf(
                entry.value,
                'profile leaf',
                WebDavSyncProfileValue.fromJson,
              ),
          }),
    );
  }
}

WebDavSyncCircleLeaf<T> _leaf<T>(
  Object? source,
  String label,
  T Function(Object? source) parse,
) {
  final json = _object(source, label);
  _onlyKeys(json, const <String>{'stamp', 'value'});
  return WebDavSyncCircleLeaf<T>(
    stamp: WebDavSyncStamp.fromJson(json['stamp']),
    value: json['value'] == null ? null : parse(json['value']),
  );
}

Map<String, Map<String, WebDavSyncCircleLeaf<T>>> _decodeNested<T>(
  Object? source,
  String label,
  T Function(Object? source) parse, {
  bool secondIsSlot = false,
}) {
  final raw = _object(source, label);
  final result = <String, Map<String, WebDavSyncCircleLeaf<T>>>{};
  for (final outer in raw.entries) {
    final profileId = _syncId(outer.key, '$label profile ID');
    final inner = _object(outer.value, '$label entries');
    result[profileId] = Map<String, WebDavSyncCircleLeaf<T>>.unmodifiable(
      <String, WebDavSyncCircleLeaf<T>>{
        for (final entry in inner.entries)
          secondIsSlot
              ? _logicalKey(entry.key, 'binding slot')
              : _syncId(entry.key, '$label resource ID'): _leaf(
            entry.value,
            '$label leaf',
            parse,
          ),
      },
    );
  }
  return Map<String, Map<String, WebDavSyncCircleLeaf<T>>>.unmodifiable(result);
}

int _nestedLeafCount<T>(
  Map<String, Map<String, WebDavSyncCircleLeaf<T>>> source,
) => source.values.fold<int>(0, (count, values) => count + values.length);

Map<String, Object?> _object(Object? source, String label) {
  if (source is! Map) throw FormatException('Invalid WebDAV sync $label');
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    if (entry.key is! String) {
      throw FormatException('Invalid WebDAV sync $label');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, Object?> _jsonObject(Object? source, String label) {
  final object = _object(source, label);
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final entry in object.entries)
      entry.key: _jsonValue(entry.value, depth: 0),
  });
}

Object? _jsonValue(Object? value, {required int depth}) {
  if (depth > 32) throw const FormatException('WebDAV sync JSON too deep');
  if (value == null || value is bool || value is int || value is String) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map((item) => _jsonValue(item, depth: depth + 1)),
    );
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid WebDAV sync JSON object');
      }
      result[entry.key as String] = _jsonValue(entry.value, depth: depth + 1);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  throw const FormatException('Invalid WebDAV sync JSON value');
}

void _onlyKeys(Map<String, Object?> value, Set<String> allowed) {
  if (value.length != allowed.length ||
      value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unexpected WebDAV sync field');
  }
}

void _onlyKeysWithOptional(
  Map<String, Object?> value, {
  required Set<String> required,
  required Set<String> optional,
}) {
  if (required.any((key) => !value.containsKey(key)) ||
      value.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const FormatException('Unexpected WebDAV sync field');
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? source, String label) {
  if (source is! String) throw FormatException('Invalid WebDAV sync $label');
  for (final value in values) {
    if (value.name == source) return value;
  }
  throw FormatException('Invalid WebDAV sync $label');
}

String _syncId(Object? source, String label) {
  if (source is! String || !_safeId.hasMatch(source)) {
    throw FormatException('Invalid WebDAV sync $label');
  }
  return source;
}

String _logicalKey(Object? source, String label) {
  if (source is! String ||
      source.isEmpty ||
      utf8.encode(source).length > WebDavSyncLimits.maxLogicalKeyBytes ||
      source.contains('\u0000')) {
    throw FormatException('Invalid WebDAV sync $label');
  }
  return source;
}

String _nonEmptyString(Object? source, String label, {required int max}) {
  if (source is! String || source.trim().isEmpty || source.length > max) {
    throw FormatException('Invalid WebDAV sync $label');
  }
  return source;
}

int _positiveInt(Object? source, String label) {
  if (source is! int || source < 1 || source > 0x7fffffff) {
    throw FormatException('Invalid WebDAV sync $label');
  }
  return source;
}

String _digest(Object? source, String label) {
  if (source is! String || !_safeDigest.hasMatch(source)) {
    throw FormatException('Invalid WebDAV sync $label');
  }
  return source;
}

final RegExp _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$');
final RegExp _safeDigest = RegExp(r'^[0-9a-f]{64}$');
