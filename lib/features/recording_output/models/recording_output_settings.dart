// Where IPTV recordings are saved and how far a scheduled recording's window
// is padded. Pure data so the schedulers, the Android bridge and the settings
// UI all share one definition.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Platforms whose recording defaults differ.
enum RecordingPlatform { android, desktop }

/// Immutable snapshot of the recording-output settings.
///
/// Null folder fields mean the unchanged default folder; null padding means
/// "use the platform default" (Android ends 2 minutes late, desktop no
/// padding).
@immutable
class RecordingOutputSettings {
  const RecordingOutputSettings({
    this.treeUri,
    this.treeDisplayName,
    this.directoryPath,
    this.startPadMinutes,
    this.endPadMinutes,
  });

  /// Android SAF tree, null = default folder.
  final String? treeUri;

  /// Label shown in settings for the picked tree.
  final String? treeDisplayName;

  /// Windows/Linux folder, null = default folder.
  final String? directoryPath;

  /// Explicit "start early" minutes; null = platform default.
  final int? startPadMinutes;

  /// Explicit "end late" minutes; null = platform default.
  final int? endPadMinutes;

  static const startPadChoices = [0, 1, 2, 5, 10];
  static const endPadChoices = [0, 1, 2, 3, 5, 10, 15];
  static const maxPadMinutes = 15;

  int startPadFor(RecordingPlatform platform) =>
      (startPadMinutes ?? 0).clamp(0, maxPadMinutes);

  int endPadFor(RecordingPlatform platform) =>
      (endPadMinutes ?? (platform == RecordingPlatform.android ? 2 : 0)).clamp(
        0,
        maxPadMinutes,
      );

  /// True when a folder was picked: a non-empty tree URI or directory path.
  bool get hasCustomFolder =>
      (treeUri != null && treeUri!.isNotEmpty) ||
      (directoryPath != null && directoryPath!.isNotEmpty);

  Map<String, Object?> toJson() => {
    if (treeUri != null) 'treeUri': treeUri,
    if (treeDisplayName != null) 'treeDisplayName': treeDisplayName,
    if (directoryPath != null) 'directoryPath': directoryPath,
    if (startPadMinutes != null) 'startPadMinutes': startPadMinutes,
    if (endPadMinutes != null) 'endPadMinutes': endPadMinutes,
  };

  /// Tolerant decode: anything that is not a map with string keys and
  /// string/int values falls back to the field default, never throws.
  static RecordingOutputSettings fromJson(Object? json) {
    if (json is! Map) return const RecordingOutputSettings();
    String? text(String field) {
      final value = json[field];
      return value is String && value.isNotEmpty ? value : null;
    }

    int? minutes(String field) {
      final value = json[field];
      return value is int ? value : null;
    }

    return RecordingOutputSettings(
      treeUri: text('treeUri'),
      treeDisplayName: text('treeDisplayName'),
      directoryPath: text('directoryPath'),
      startPadMinutes: minutes('startPadMinutes'),
      endPadMinutes: minutes('endPadMinutes'),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Null, unparsable or wrongly-shaped input yields the defaults.
  static RecordingOutputSettings decode(String? raw) {
    if (raw == null || raw.isEmpty) return const RecordingOutputSettings();
    try {
      return fromJson(jsonDecode(raw));
    } on FormatException {
      return const RecordingOutputSettings();
    } on Object catch (_) {
      return const RecordingOutputSettings();
    }
  }

  /// [clearFolder] nulls all three folder fields regardless of the folder
  /// arguments, so "Use default folder" can never leave half a folder behind.
  RecordingOutputSettings copyWith({
    String? treeUri,
    String? treeDisplayName,
    String? directoryPath,
    int? startPadMinutes,
    int? endPadMinutes,
    bool clearFolder = false,
  }) {
    if (clearFolder) {
      return RecordingOutputSettings(
        startPadMinutes: startPadMinutes ?? this.startPadMinutes,
        endPadMinutes: endPadMinutes ?? this.endPadMinutes,
      );
    }
    return RecordingOutputSettings(
      treeUri: treeUri ?? this.treeUri,
      treeDisplayName: treeDisplayName ?? this.treeDisplayName,
      directoryPath: directoryPath ?? this.directoryPath,
      startPadMinutes: startPadMinutes ?? this.startPadMinutes,
      endPadMinutes: endPadMinutes ?? this.endPadMinutes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecordingOutputSettings &&
      other.treeUri == treeUri &&
      other.treeDisplayName == treeDisplayName &&
      other.directoryPath == directoryPath &&
      other.startPadMinutes == startPadMinutes &&
      other.endPadMinutes == endPadMinutes;

  @override
  int get hashCode => Object.hash(
    treeUri,
    treeDisplayName,
    directoryPath,
    startPadMinutes,
    endPadMinutes,
  );
}

/// The window a scheduled recording actually captures: the padded start is
/// earlier by [RecordingOutputSettings.startPadFor] and the padded end later
/// by [RecordingOutputSettings.endPadFor]. The stored schedule keeps its
/// original window; only the capture timers move.
({int startMs, int endMs}) paddedRecordingWindow({
  required int startMs,
  required int endMs,
  required RecordingOutputSettings settings,
  required RecordingPlatform platform,
}) {
  return (
    startMs: startMs - settings.startPadFor(platform) * 60000,
    endMs: endMs + settings.endPadFor(platform) * 60000,
  );
}

/// Plain-English label for where recordings are saved. Custom SAF trees show
/// their display name when the picker gave one; a folder path shows its
/// label (an Android drive's name) or else the path itself.
String recordingLocationLabel(RecordingOutputSettings settings) {
  final treeUri = settings.treeUri;
  if (treeUri != null && treeUri.isNotEmpty) {
    final displayName = settings.treeDisplayName;
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return 'Chosen folder';
  }
  final directoryPath = settings.directoryPath;
  if (directoryPath != null && directoryPath.isNotEmpty) {
    final label = settings.treeDisplayName;
    return label != null && label.isNotEmpty ? label : directoryPath;
  }
  return 'Downloads/Debrify/Recordings';
}
