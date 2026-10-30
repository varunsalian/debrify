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
