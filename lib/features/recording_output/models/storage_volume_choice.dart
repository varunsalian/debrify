// A drive a recordings folder can live on where the device has no system
// folder picker: the app's own folder on a USB stick or SD card. Pure data,
// decoded from the native storage-volumes channel.

import 'package:flutter/foundation.dart';

@immutable
class StorageVolumeChoice {
  const StorageVolumeChoice({
    required this.path,
    this.label,
    this.freeBytes,
    this.totalBytes,
  });

  /// The folder recordings are written to on this drive.
  final String path;

  /// The system's name for the drive ("SanDisk USB drive"), when it has one.
  final String? label;

  /// Free and total space; null when the drive did not say.
  final int? freeBytes;
  final int? totalBytes;

  /// What the drive is called in the chooser and in "Save recordings to".
  String get name => label ?? 'USB drive';

  /// One entry of the native list, or null when it has no usable path.
  static StorageVolumeChoice? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    if (path is! String || path.isEmpty) return null;
    final label = raw['label'];
    int? bytes(String field) {
      final value = raw[field];
      return value is int && value >= 0 ? value : null;
    }

    return StorageVolumeChoice(
      path: path,
      label: label is String && label.trim().isNotEmpty ? label.trim() : null,
      freeBytes: bytes('freeBytes'),
      totalBytes: bytes('totalBytes'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StorageVolumeChoice &&
      other.path == path &&
      other.label == label &&
      other.freeBytes == freeBytes &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(path, label, freeBytes, totalBytes);
}

/// "12.3 GB free of 64.0 GB", or null when the drive reported no space.
String? storageVolumeSpaceText(StorageVolumeChoice volume) {
  final free = volume.freeBytes;
  if (free == null) return null;
  final total = volume.totalBytes;
  final freeText = '${_gigabytes(free)} free';
  return total == null || total == 0
      ? freeText
      : '$freeText of ${_gigabytes(total)}';
}

String _gigabytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  if (bytes < gb) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  return '${(bytes / gb).toStringAsFixed(1)} GB';
}
