import 'package:path/path.dart' as p;

/// What a profile's `avatarKey` points at.
///
/// The kind is encoded in the string itself rather than in a new column: the
/// key already crosses the wire in portable packages and rides the tvOS
/// Keychain recovery envelope, so keeping it a plain `String` means no schema
/// change and no migration. A build that predates a given prefix simply fails
/// to parse it and falls back to the role's default icon.
///
/// ```
/// person                              legacy icon (unchanged)
/// art:aurora                          built-in art, drawn in code
/// file:avatars/<uuid>.gif#4A90D9      user image, with its wash colour
/// ```
enum ProfileAvatarKind { icon, art, image }

class ProfileAvatar {
  /// Legacy icon keys. These predate every prefix and must keep resolving —
  /// existing profiles reference them directly.
  static const Set<String> legacyIconIds = <String>{
    'person',
    'child',
    'movie',
    'rocket',
    'sports',
    'music',
  };

  static const Set<String> imageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
  };

  /// The single directory a `file:` avatar may ever live in, relative to the
  /// profile root. Anything outside it is rejected, not sanitized.
  static const String directory = 'avatars';

  /// Bounded so a hostile package cannot store an enormous key.
  static const int maxKeyLength = 256;

  static final RegExp _artId = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');
  static final RegExp _fileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$');
  static final RegExp _colour = RegExp(r'^[0-9A-Fa-f]{6}$');

  final ProfileAvatarKind kind;

  /// Icon name, art id, or the `avatars/<file>` path — never absolute.
  final String id;

  /// 0xRRGGBB wash colour for image avatars, computed once at ingest so the
  /// gate never decodes a file to find it. Art declares its own colour in the
  /// art registry, so this stays null there.
  final int? dominantColor;

  const ProfileAvatar._(this.kind, this.id, this.dominantColor);

  const ProfileAvatar.icon(String id)
    : this._(ProfileAvatarKind.icon, id, null);

  const ProfileAvatar.art(String id) : this._(ProfileAvatarKind.art, id, null);

  /// Throws [FormatException] if [relativePath] is not a safe `avatars/<file>`.
  factory ProfileAvatar.image(String relativePath, {int? dominantColor}) {
    final normalized = _normalizeImagePath(relativePath);
    if (normalized == null) {
      throw FormatException('Unsafe avatar path: $relativePath');
    }
    return ProfileAvatar._(ProfileAvatarKind.image, normalized, dominantColor);
  }

  /// Parses a stored key. Returns null for anything unrecognised or unsafe, so
  /// the caller falls back to the role's default icon — a bad key degrades, it
  /// never throws into a render path and never yields a path to resolve.
  static ProfileAvatar? tryParse(String? key) {
    if (key == null) return null;
    final trimmed = key.trim();
    if (trimmed.isEmpty || trimmed.length > maxKeyLength) return null;

    if (trimmed.startsWith('art:')) {
      final id = trimmed.substring(4);
      return _artId.hasMatch(id) ? ProfileAvatar.art(id) : null;
    }

    if (trimmed.startsWith('file:')) {
      var rest = trimmed.substring(5);
      int? colour;
      final hash = rest.lastIndexOf('#');
      if (hash >= 0) {
        final raw = rest.substring(hash + 1);
        if (!_colour.hasMatch(raw)) return null;
        colour = int.parse(raw, radix: 16);
        rest = rest.substring(0, hash);
      }
      final normalized = _normalizeImagePath(rest);
      if (normalized == null) return null;
      return ProfileAvatar._(ProfileAvatarKind.image, normalized, colour);
    }

    if (legacyIconIds.contains(trimmed)) return ProfileAvatar.icon(trimmed);
    return null;
  }

  /// The stored form. Round-trips through [tryParse].
  String format() => switch (kind) {
    ProfileAvatarKind.icon => id,
    ProfileAvatarKind.art => 'art:$id',
    ProfileAvatarKind.image =>
      dominantColor == null
          ? 'file:$id'
          : 'file:$id#${(dominantColor! & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
  };

  /// True only for a GIF. Art animation is a property of its painter, decided
  /// by the art registry, not by the key.
  bool get isAnimatedImage =>
      kind == ProfileAvatarKind.image &&
      p.posix.extension(id).toLowerCase() == '.gif';

  /// A user file that must exist on disk — the only kind tvOS refuses and the
  /// only kind a portable package carries bytes for.
  bool get isUserFile => kind == ProfileAvatarKind.image;

  /// Rejects traversal, absolutes, drive letters, nesting, odd names and
  /// unknown extensions. Returns the canonical `avatars/<file>` or null.
  static String? _normalizeImagePath(String value) {
    if (value.isEmpty || value.contains(r'\') || value.contains('\u0000')) {
      return null;
    }
    final normalized = p.posix.normalize(value);
    if (p.posix.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized.startsWith('..')) {
      return null;
    }
    final segments = p.posix.split(normalized);
    // Exactly `avatars/<file>` — no nesting, no bare filenames.
    if (segments.length != 2 || segments.first != directory) return null;
    final name = segments.last;
    if (!_fileName.hasMatch(name)) return null;
    if (!imageExtensions.contains(p.posix.extension(name).toLowerCase())) {
      return null;
    }
    return p.posix.join(directory, name);
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileAvatar &&
      other.kind == kind &&
      other.id == id &&
      other.dominantColor == dominantColor;

  @override
  int get hashCode => Object.hash(kind, id, dominantColor);

  @override
  String toString() => 'ProfileAvatar(${format()})';
}
