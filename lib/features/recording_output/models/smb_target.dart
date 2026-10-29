// Where recordings are pushed over SMB. Pure data so the uploader, the
// settings storage and the settings UI all share one definition.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Immutable description of an SMB share a recording can be uploaded to.
@immutable
final class SmbTarget {
  const SmbTarget({
    this.enabled = false,
    this.host = '',
    this.share = '',
    this.folder = '',
    this.user = '',
    this.domain = '',
    this.deleteLocalAfterUpload = false,
  });

  final bool enabled;
  final String host;
  final String share;
  final String folder;
  final String user;
  final String domain;
  final bool deleteLocalAfterUpload;

  /// Host and share (trimmed) are non-empty and share contains no '/' or '\'.
  bool get isComplete =>
      host.trim().isNotEmpty &&
      share.trim().isNotEmpty &&
      !share.contains('/') &&
      !share.contains(r'\');

  /// [folder] with '\' turned into '/', split on '/', each segment trimmed,
  /// and empty, '.' and '..' segments dropped.
  List<String> get folderSegments {
    final segments = <String>[];
    for (final raw in folder.replaceAll(r'\', '/').split('/')) {
      final segment = raw.trim();
      if (segment.isEmpty || segment == '.' || segment == '..') continue;
      segments.add(segment);
    }
    return segments;
  }

  /// Folder segments joined with '/' then '/' + [fileName]; just [fileName]
  /// when there is no folder.
  String remotePathFor(String fileName) {
    final segments = folderSegments;
    if (segments.isEmpty) return fileName;
    return '${segments.join('/')}/$fileName';
  }

  /// `\\host\share` or `\\host\share\a\b`; '' when not [isComplete].
  String get displayAddress {
    if (!isComplete) return '';
    final base = r'\\' + host.trim() + r'\' + share.trim();
    final segments = folderSegments;
    if (segments.isEmpty) return base;
    return '$base\\${segments.join(r'\')}';
  }

  /// Parses what users paste: `smb://host/share/a/b`, `\\host\share\a`,
  /// `//host/share`, `host/share/a`. Returns null when no host or no share.
  /// Only host/share/folder are set; every other field keeps its default.
  static SmbTarget? parseAddress(String input) {
    var rest = input.trim();
    final scheme = rest.indexOf('://');
    if (scheme != -1) rest = rest.substring(scheme + 3);
    final segments = <String>[];
    for (final raw in rest.split(RegExp(r'[/\\]'))) {
      final segment = raw.trim();
      if (segment.isNotEmpty) segments.add(segment);
    }
    if (segments.length < 2) return null;
    return SmbTarget(
      host: segments[0],
      share: segments[1],
      folder: segments.length > 2 ? segments.sublist(2).join('/') : '',
    );
  }

  SmbTarget copyWith({
    bool? enabled,
    String? host,
    String? share,
    String? folder,
    String? user,
    String? domain,
    bool? deleteLocalAfterUpload,
  }) {
    return SmbTarget(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      share: share ?? this.share,
      folder: folder ?? this.folder,
      user: user ?? this.user,
      domain: domain ?? this.domain,
      deleteLocalAfterUpload:
          deleteLocalAfterUpload ?? this.deleteLocalAfterUpload,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'host': host,
    'share': share,
    'folder': folder,
    'user': user,
    'domain': domain,
    'deleteLocalAfterUpload': deleteLocalAfterUpload,
  };

  /// Tolerant: non-map input yields the default target; a wrong-typed field
  /// yields its default.
  static SmbTarget fromJson(Object? json) {
    if (json is! Map) return const SmbTarget();
    String text(String key) => json[key] is String ? json[key] as String : '';
    bool flag(String key) => json[key] is bool ? json[key] as bool : false;
    return SmbTarget(
      enabled: flag('enabled'),
      host: text('host'),
      share: text('share'),
      folder: text('folder'),
      user: text('user'),
      domain: text('domain'),
      deleteLocalAfterUpload: flag('deleteLocalAfterUpload'),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Null, empty, or invalid JSON yields the default target.
  static SmbTarget decode(String? raw) {
    if (raw == null || raw.isEmpty) return const SmbTarget();
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return const SmbTarget();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SmbTarget &&
      other.enabled == enabled &&
      other.host == host &&
      other.share == share &&
      other.folder == folder &&
      other.user == user &&
      other.domain == domain &&
      other.deleteLocalAfterUpload == deleteLocalAfterUpload;

  @override
  int get hashCode => Object.hash(
    enabled,
    host,
    share,
    folder,
    user,
    domain,
    deleteLocalAfterUpload,
  );
}
