import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';

import '../../models/profiles/profile_avatar.dart';
import 'profile_avatar_mutation.dart';
import 'profile_avatar_policy.dart';
import 'profile_avatar_storage.dart';
import 'profile_registry.dart';

/// Why a picture was refused. Carries a sentence fit to show a user — every
/// rejection is a thing they can act on, not a log line.
class ProfileAvatarRejected implements Exception {
  final String message;

  const ProfileAvatarRejected(this.message);

  @override
  String toString() => message;
}

/// A validated, normalized avatar that has not touched profile storage yet.
///
/// Keeping preparation separate from writing lets callers include the avatar
/// key in their own transaction without pruning the currently committed file
/// first. The bytes are already bounded and safe to preview or transfer.
class PreparedProfileAvatar {
  final ProfileAvatar avatar;
  final Uint8List bytes;

  const PreparedProfileAvatar({required this.avatar, required this.bytes});
}

/// Turns arbitrary picked bytes into a stored avatar.
///
/// **GIFs are never transcoded.** `dart:ui` can decode anything but only
/// re-encodes to PNG, so a "downscale and re-encode" pipeline would silently
/// flatten every animation to a single frame. Adding a Dart image encoder to
/// avoid that is the wrong trade against an APK that is already too big. So
/// static images are downscaled and re-encoded, and GIFs are validated against
/// caps and stored byte-for-byte or rejected with a reason.
class ProfileAvatarIngest {
  ProfileAvatarIngest._();

  /// Comfortably under [ProfilePortableFiles.maxFileBytes] (4 MiB) so a full
  /// roster of avatars cannot blow the 64 MiB package total or the restore
  /// guard.
  static const int maxBytes = 1024 * 1024;
  static const int maxInputBytes = 12 * 1024 * 1024;
  static const int maxRemoteBytes = 256 * 1024;
  static const int maxDimension = 512;
  static const int maxGifFrames = 120;

  /// Progressively smaller targets: a noisy 512² PNG can still exceed [maxBytes],
  /// and shrinking is a better answer than refusing a picture the user chose.
  static const List<int> _downscaleLadder = <int>[512, 384, 256, 160];
  static const List<int> _remoteDownscaleLadder = <int>[384, 256, 160, 128];

  /// Validates and normalizes picked bytes without writing or deleting files.
  static Future<PreparedProfileAvatar> prepare(Uint8List bytes) =>
      _prepare(bytes, maxOutputBytes: maxBytes, ladder: _downscaleLadder);

  /// A smaller static-image target for the paced phone-to-TV UDP transport.
  /// Animated images remain byte-for-byte and must already fit the cap.
  static Future<PreparedProfileAvatar> prepareForRemote(Uint8List bytes) =>
      _prepare(
        bytes,
        maxOutputBytes: maxRemoteBytes,
        ladder: _remoteDownscaleLadder,
      );

  static Future<PreparedProfileAvatar> _prepare(
    Uint8List bytes, {
    required int maxOutputBytes,
    required List<int> ladder,
  }) async {
    if (!ProfileAvatarPolicy.userImagesSupported) {
      throw const ProfileAvatarRejected(
        'This device uses built-in avatars only.',
      );
    }
    if (bytes.isEmpty) {
      throw const ProfileAvatarRejected('That file is empty.');
    }
    if (bytes.length > maxInputBytes) {
      throw ProfileAvatarRejected(
        'That image is ${_mb(bytes.length)} — the input limit is '
        '${_mb(maxInputBytes)}.',
      );
    }

    final format = _sniff(bytes);
    if (format == null) {
      throw const ProfileAvatarRejected(
        'That is not a PNG, JPEG, WebP or GIF image.',
      );
    }

    final ({Uint8List bytes, String extension, int colour}) stored =
        format == _Format.gif
        ? await _prepareGif(bytes, maxOutputBytes: maxOutputBytes)
        : await _prepareStatic(
            bytes,
            maxOutputBytes: maxOutputBytes,
            ladder: ladder,
          );
    final name = '${await _digest(stored.bytes)}.${stored.extension}';
    return PreparedProfileAvatar(
      avatar: ProfileAvatar.image(
        '${ProfileAvatar.directory}/$name',
        dominantColor: stored.colour,
      ),
      bytes: stored.bytes,
    );
  }

  /// Writes a prepared candidate without pruning the currently committed
  /// avatar. Call [commit] only after the profile key has been persisted.
  static Future<void> writeCandidate({
    required String profileId,
    required PreparedProfileAvatar prepared,
  }) async {
    final file = await ProfileAvatarStorage.fileFor(profileId, prepared.avatar);
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      final existing = await file.readAsBytes();
      if (_sameBytes(existing, prepared.bytes)) return;
      // A content-address collision or an externally modified current file must
      // never be repaired by truncating bytes that may still be authoritative.
      throw StateError('Avatar content address already contains other bytes');
    }
    final temp = File('${file.path}.candidate.tmp');
    if (await temp.exists()) await temp.delete();
    try {
      await temp.writeAsBytes(prepared.bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Finalizes the file lifecycle for a successfully persisted selection.
  /// Art and icon selections remove all former user images.
  static Future<void> commit({
    required String profileId,
    required String? avatarKey,
  }) async {
    final avatar = ProfileAvatar.tryParse(avatarKey);
    if (avatar?.kind == ProfileAvatarKind.image) {
      await ProfileAvatarStorage.pruneExcept(profileId, avatar!);
    } else {
      await ProfileAvatarStorage.deleteAll(profileId);
    }
  }

  /// Removes an uncommitted candidate while preserving the previously
  /// referenced file (including the content-addressed same-image case).
  static Future<void> discardCandidate({
    required String profileId,
    required ProfileAvatar candidate,
    ProfileAvatar? preserve,
  }) => ProfileAvatarStorage.deleteCandidate(
    profileId,
    candidate,
    preserve: preserve,
  );

  /// Publishes one avatar selection together with a caller-owned registry
  /// mutation. All production avatar writers use this boundary so a newer key
  /// cannot be pruned by an older writer.
  ///
  /// [wasPersisted] must verify the complete caller mutation, not only the
  /// avatar key. Registry methods checkpoint after their database transaction,
  /// so a thrown Future can still mean the mutation is authoritative.
  static Future<void> publish({
    required ProfileRegistry registry,
    required String profileId,
    required String avatarKey,
    required Future<void> Function() persist,
    required Future<bool> Function() wasPersisted,
    PreparedProfileAvatar? prepared,
  }) => ProfileAvatarMutation.runExclusive(profileId, () async {
    final managedAvatar = ProfileAvatar.tryParse(avatarKey);
    if (prepared != null && managedAvatar == null) {
      throw ArgumentError('A prepared avatar requires a valid avatar key');
    }
    final mutationStarted = managedAvatar != null;
    if (mutationStarted) {
      await ProfileAvatarMutation.begin(profileId, avatarKey);
    }

    try {
      if (prepared != null) {
        await writeCandidate(profileId: profileId, prepared: prepared);
      }
    } catch (error, stackTrace) {
      await _rollbackCandidate(
        registry: registry,
        profileId: profileId,
        prepared: prepared,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    try {
      await persist();
    } catch (error, stackTrace) {
      bool committed;
      try {
        committed = await wasPersisted();
      } catch (_) {
        // The durable intent remains for bootstrap; deleting a candidate while
        // registry authority is unknown would recreate the dangling-key bug.
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (!committed) {
        if (mutationStarted) {
          await _rollbackCandidate(
            registry: registry,
            profileId: profileId,
            prepared: prepared,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      // SQLite may only be a cache projection on tvOS. A second successful
      // checkpoint is therefore required before old bytes can be pruned and
      // the durable mutation intent cleared. It also repairs a transient
      // projection-callback failure on every other platform.
      await registry.checkpointTvOsRecovery();
    }

    if (!mutationStarted) return;
    await commit(profileId: profileId, avatarKey: avatarKey);
    try {
      await ProfileAvatarMutation.complete(profileId);
    } catch (_) {
      // Publication is complete. A stale intent is safe and bootstrap will
      // reconcile it idempotently if clearing the ledger failed.
    }
  });

  static Future<void> _rollbackCandidate({
    required ProfileRegistry registry,
    required String profileId,
    required PreparedProfileAvatar? prepared,
  }) async {
    try {
      final current = await registry.getProfile(profileId);
      if (prepared != null) {
        await discardCandidate(
          profileId: profileId,
          candidate: prepared.avatar,
          preserve: ProfileAvatar.tryParse(current?.avatarKey),
        );
      }
      await ProfileAvatarStorage.cleanupTemporary(profileId);
      await ProfileAvatarMutation.complete(profileId);
    } catch (_) {
      // Leave the durable intent in place when cleanup cannot be proven. It is
      // safer for bootstrap to retry than to discard possibly authoritative bytes.
    }
  }

  /// Decodes, validates, normalises and stores [bytes] as [profileId]'s avatar,
  /// returning the key to persist. Previous avatar files for that profile are
  /// pruned, so trying pictures cannot grow the directory without bound.
  ///
  /// The caller is responsible for authorization: a profile may always set its
  /// own avatar, changing another profile's requires `manageProfiles`. This
  /// runs after that check, never instead of it.
  static Future<ProfileAvatar> ingest({
    required String profileId,
    required Uint8List bytes,
  }) async {
    final prepared = await prepare(bytes);
    await ProfileAvatarMutation.runExclusive(profileId, () async {
      await writeCandidate(profileId: profileId, prepared: prepared);
      await commit(profileId: profileId, avatarKey: prepared.avatar.format());
    });
    return prepared.avatar;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  /// Validates bytes restored under an already-normalized avatar path. Unlike
  /// [prepare], this never re-encodes: the package key and its bytes must stay
  /// byte-for-byte associated.
  static Future<void> validateStored({
    required String relativePath,
    required Uint8List bytes,
  }) async {
    final avatar = ProfileAvatar.tryParse('file:$relativePath');
    if (avatar?.kind != ProfileAvatarKind.image || bytes.isEmpty) {
      throw const FormatException('Invalid portable avatar');
    }
    if (bytes.length > maxBytes) {
      throw const FormatException('Portable avatar exceeds limit');
    }
    final format = _sniff(bytes);
    final expected = pExtension(avatar!.id);
    final matches = switch (format) {
      _Format.png => expected == '.png',
      _Format.jpeg => expected == '.jpg' || expected == '.jpeg',
      _Format.webp => expected == '.webp',
      _Format.gif => expected == '.gif',
      null => false,
    };
    if (!matches) throw const FormatException('Portable avatar type mismatch');

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > maxDimension || descriptor.height > maxDimension) {
        throw const FormatException('Portable avatar dimensions exceed limit');
      }
      codec = await descriptor.instantiateCodec();
      if (format == _Format.gif) {
        if (codec.frameCount > maxGifFrames) {
          throw const FormatException('Portable avatar has too many frames');
        }
      } else if (codec.frameCount != 1) {
        throw const FormatException('Animated portable avatar must be a GIF');
      }
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('Portable avatar could not be decoded');
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static String pExtension(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot).toLowerCase();
  }

  /// Animated: validated and kept verbatim, or refused. No transcode.
  static Future<({Uint8List bytes, String extension, int colour})> _prepareGif(
    Uint8List bytes, {
    required int maxOutputBytes,
  }) async {
    if (bytes.length > maxOutputBytes) {
      throw ProfileAvatarRejected(
        'That GIF is ${_mb(bytes.length)} — the limit is '
        '${_mb(maxOutputBytes)}. '
        'Try a shorter or smaller one.',
      );
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? firstFrame;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > maxDimension || descriptor.height > maxDimension) {
        throw ProfileAvatarRejected(
          'That GIF is ${descriptor.width}×${descriptor.height}. '
          'Animated avatars must be $maxDimension×$maxDimension or smaller.',
        );
      }
      codec = await descriptor.instantiateCodec();
      if (codec.frameCount > maxGifFrames) {
        throw ProfileAvatarRejected(
          'That GIF has ${codec.frameCount} frames — the limit is '
          '$maxGifFrames.',
        );
      }
      final frame = await codec.getNextFrame();
      firstFrame = frame.image;
      final colour = await _dominantColor(firstFrame);
      return (bytes: bytes, extension: 'gif', colour: colour);
    } on ProfileAvatarRejected {
      rethrow;
    } catch (_) {
      throw const ProfileAvatarRejected('That GIF could not be read.');
    } finally {
      firstFrame?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Static: downscaled to fit and re-encoded as PNG.
  static Future<({Uint8List bytes, String extension, int colour})>
  _prepareStatic(
    Uint8List bytes, {
    required int maxOutputBytes,
    required List<int> ladder,
  }) async {
    Object? failure;
    for (final target in ladder) {
      final ui.Image image;
      try {
        image = await _decodeScaled(bytes, target);
      } catch (error) {
        failure = error;
        break;
      }
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      final colour = await _dominantColor(image);
      image.dispose();
      if (encoded == null) {
        failure = StateError('encode failed');
        break;
      }
      final out = encoded.buffer.asUint8List(
        encoded.offsetInBytes,
        encoded.lengthInBytes,
      );
      if (out.length <= maxOutputBytes) {
        return (
          bytes: Uint8List.fromList(out),
          extension: 'png',
          colour: colour,
        );
      }
    }
    if (failure != null) {
      throw const ProfileAvatarRejected('That image could not be read.');
    }
    throw const ProfileAvatarRejected(
      'That image is too detailed to store. Try a simpler picture.',
    );
  }

  /// Decodes at most [target] on the long edge, preserving aspect ratio.
  static Future<ui.Image> _decodeScaled(Uint8List bytes, int target) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      final longest = width > height ? width : height;
      final scale = longest > target ? target / longest : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (width * scale).round().clamp(1, target),
        targetHeight: (height * scale).round().clamp(1, target),
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// A representative wash colour, computed once here so the gate never decodes
  /// a file to paint its backdrop.
  ///
  /// Picks the most populated bucket of a coarse RGB histogram, ignoring
  /// near-transparent, near-black and near-white pixels — an average would turn
  /// any colourful picture into grey mud.
  static Future<int> _dominantColor(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return 0x5B8CFF;
    final pixels = data.buffer.asUint8List();
    final counts = <int, int>{};
    // Sample rather than sweep: at 512² that is ~4k reads instead of 262k.
    final stride = ((pixels.length ~/ 4) ~/ 4096).clamp(1, 1 << 20) * 4;
    var fallbackR = 0, fallbackG = 0, fallbackB = 0, fallbackN = 0;
    for (var i = 0; i + 3 < pixels.length; i += stride) {
      final a = pixels[i + 3];
      if (a < 128) continue;
      final r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
      fallbackR += r;
      fallbackG += g;
      fallbackB += b;
      fallbackN++;
      final max = [r, g, b].reduce((x, y) => x > y ? x : y);
      final min = [r, g, b].reduce((x, y) => x < y ? x : y);
      if (max < 40 || min > 225) continue; // near-black / near-white
      final bucket = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      if (fallbackN == 0) return 0x5B8CFF;
      return (fallbackR ~/ fallbackN) << 16 |
          (fallbackG ~/ fallbackN) << 8 |
          (fallbackB ~/ fallbackN);
    }
    var best = counts.keys.first;
    var bestCount = -1;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    // Bucket centre, so the colour is not systematically dark.
    final r = ((best >> 8) & 0xF) * 16 + 8;
    final g = ((best >> 4) & 0xF) * 16 + 8;
    final b = (best & 0xF) * 16 + 8;
    return r << 16 | g << 8 | b;
  }

  static _Format? _sniff(Uint8List b) {
    bool at(int offset, List<int> magic) {
      if (b.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (b[offset + i] != magic[i]) return false;
      }
      return true;
    }

    if (at(0, <int>[0x47, 0x49, 0x46, 0x38])) return _Format.gif;
    if (at(0, <int>[0x89, 0x50, 0x4E, 0x47])) return _Format.png;
    if (at(0, <int>[0xFF, 0xD8, 0xFF])) return _Format.jpeg;
    if (at(0, <int>[0x52, 0x49, 0x46, 0x46]) &&
        at(8, <int>[0x57, 0x45, 0x42, 0x50])) {
      return _Format.webp;
    }
    return null;
  }

  static Future<String> _digest(List<int> bytes) async {
    final hash = await Sha256().hash(bytes);
    return base64Url
        .encode(hash.bytes)
        .replaceAll('=', '')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .substring(0, 16);
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

enum _Format { png, jpeg, webp, gif }
