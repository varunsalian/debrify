// Recordings that live on the profile's SMB share, as the Recordings page
// lists them. Pure data: the share library repository fills it, the page
// renders it, and the stream server plays it.

import 'package:flutter/foundation.dart';

/// One recording file on the share.
@immutable
final class ShareRecording {
  const ShareRecording({
    required this.name,
    required this.path,
    required this.bytes,
    required this.modified,
  });

  /// File name, e.g. `UK SKY SPORT GOLF 2026-10-30 12-31.ts`.
  final String name;

  /// Share-relative path with '/' separators.
  final String path;
  final int bytes;
  final DateTime modified;

  /// When it was recorded: the `_YYYYMMDD_HHMM[SS]` stamp recordings carry
  /// in their names (local time; a trailing `_2` or ` (2)` from a name clash
  /// is allowed), else the file's modification time. The share stamps a
  /// copied file with the moment of the copy, not the recording.
  DateTime get recordedAt {
    final match = _stamp.firstMatch(title);
    if (match == null) return modified;
    int part(int group) => int.parse(match.group(group) ?? '0');
    final at = DateTime(part(1), part(2), part(3), part(4), part(5), part(6));
    // Reject what is not a real date (month 13 rolls over silently).
    final real =
        at.month == part(2) &&
        at.day == part(3) &&
        at.hour == part(4) &&
        at.minute == part(5);
    return real ? at : modified;
  }

  static final _stamp = RegExp(
    r'_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})?(?:_\d+| \(\d+\))?$',
  );

  /// The name without its extension.
  String get title {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  @override
  bool operator ==(Object other) =>
      other is ShareRecording &&
      other.path == path &&
      other.bytes == bytes &&
      other.modified == modified;

  @override
  int get hashCode => Object.hash(path, bytes, modified);
}

/// What the Recordings page knows about the share. Null (from the
/// repository) means no share is set up.
@immutable
final class ShareLibrary {
  const ShareLibrary({
    required this.address,
    required this.recordsDirect,
    this.recordings = const [],
    this.error,
  });

  /// `\\host\share\folder`.
  final String address;

  /// New recordings are written straight to the share (otherwise they are
  /// copied there after they finish).
  final bool recordsDirect;

  /// Newest first.
  final List<ShareRecording> recordings;

  /// Why the share could not be listed; [recordings] is empty then.
  final String? error;

  int get totalBytes => recordings.fold(0, (sum, r) => sum + r.bytes);
}
