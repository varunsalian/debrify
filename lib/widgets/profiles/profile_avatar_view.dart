import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/profile_policy.dart';
import '../../services/profiles/profile_avatar_storage.dart';
import 'profile_art.dart';

/// Renders any avatar kind — icon, procedural art, static image or GIF.
///
/// **Focus-only animation is the DPAD contract**, and it means something
/// different per kind, so the mechanisms are deliberately not shared:
///
/// * procedural art holds a controller and simply stops ticking when unfocused
///   — no decode, no cache, nothing to free;
/// * a GIF shows a cached still first frame when unfocused and swaps to an
///   animated `Image` when focused;
/// * static images and icons never animate at all.
///
/// One moving element is also how the eye finds focus across a room, so the
/// animation doubles as the focus indicator rather than competing with it.
/// That reasoning is a TV room's: on touch surfaces nothing is ever focused,
/// which silently demoted every GIF to its first frame — a person who chose
/// an animated avatar never saw it move. Touch surfaces therefore opt in via
/// [animateWhenIdle], which animates without claiming the focus styling.
///
/// A missing file is an ordinary state, never an error: a package restored on
/// tvOS keeps its key without materialising bytes, and files can vanish
/// underneath us anywhere. That falls back to the avatar's colour and the
/// profile's initial, which still reads as *theirs*.
class ProfileAvatarView extends StatefulWidget {
  final String profileId;
  final String? avatarKey;
  final UserProfileRole role;
  final String name;
  final bool focused;

  /// Whether animation is permitted at all. The editor's "animate on the gate"
  /// switch feeds this; it is not a platform gate — phones and desktops
  /// animate normally.
  final bool allowAnimation;

  /// Animate even while unfocused — the touch surfaces' opt-in (there is no
  /// cursor there, so focus-gated animation meant GIFs and living art never
  /// moved at all). Does NOT imply the focused visual treatment; it only
  /// widens when the GIF codec / art ticker may run. [allowAnimation] still
  /// outranks it.
  final bool animateWhenIdle;

  const ProfileAvatarView({
    super.key,
    required this.profileId,
    required this.avatarKey,
    required this.role,
    required this.name,
    this.focused = false,
    this.allowAnimation = true,
    this.animateWhenIdle = false,
  });

  /// The gate's ambient wash for a key, without building anything or touching
  /// the filesystem: art declares its colour, user images carry theirs inside
  /// the key, and everything else falls back by role.
  static Color washColor(String? avatarKey, UserProfileRole role) {
    final avatar = ProfileAvatar.tryParse(avatarKey);
    switch (avatar?.kind) {
      case ProfileAvatarKind.art:
        final art = ProfileArtRegistry.byId(avatar!.id);
        if (art != null) return art.color;
      case ProfileAvatarKind.image:
        final colour = avatar!.dominantColor;
        if (colour != null) return Color(0xFF000000 | colour);
      case ProfileAvatarKind.icon:
      case null:
        break;
    }
    return _roleColor(role);
  }

  static Color _roleColor(UserProfileRole role) => switch (role) {
    UserProfileRole.admin => const Color(0xFF5B8CFF),
    UserProfileRole.member => const Color(0xFF3D8B8B),
    UserProfileRole.child => const Color(0xFFE2864A),
  };

  static IconData iconFor(String? avatarKey, UserProfileRole role) {
    final avatar = ProfileAvatar.tryParse(avatarKey);
    final id = avatar?.kind == ProfileAvatarKind.icon ? avatar!.id : null;
    return switch (id) {
      'child' => Icons.child_care_rounded,
      'movie' => Icons.movie_filter_rounded,
      'rocket' => Icons.rocket_launch_rounded,
      'sports' => Icons.sports_esports_rounded,
      'music' => Icons.headphones_rounded,
      'person' => Icons.person_rounded,
      _ =>
        role == UserProfileRole.child
            ? Icons.child_care_rounded
            : Icons.person_rounded,
    };
  }

  /// Identifies the procedural-art painter in a widget tree.
  static const Key artPaintKey = ValueKey<String>('profile-art-paint');

  /// Identifies the frozen-first-frame branch taken by an unfocused GIF.
  static const Key stillFrameKey = ValueKey<String>('profile-still-frame');

  @override
  State<ProfileAvatarView> createState() => _ProfileAvatarViewState();
}

class _ProfileAvatarViewState extends State<ProfileAvatarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  ProfileAvatar? _avatar;
  File? _file;
  int _resolveSerial = 0;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  @override
  void didUpdateWidget(ProfileAvatarView old) {
    super.didUpdateWidget(old);
    if (old.avatarKey != widget.avatarKey ||
        old.profileId != widget.profileId) {
      _adopt();
    } else {
      if (old.focused != widget.focused ||
          old.allowAnimation != widget.allowAnimation ||
          old.animateWhenIdle != widget.animateWhenIdle) {
        _syncTicker();
      }
      // Restore or ingest can repair missing bytes under the same
      // content-addressed key. Parent roster refreshes must retry that lookup;
      // otherwise a mounted fallback can never observe the materialized file.
      if (_file == null && _avatar?.kind == ProfileAvatarKind.image) {
        final serial = ++_resolveSerial;
        _resolveFile(serial, _avatar!, widget.profileId);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _adopt() {
    final serial = ++_resolveSerial;
    _avatar = ProfileAvatar.tryParse(widget.avatarKey);
    _file = null;
    _syncTicker();
    if (_avatar?.kind == ProfileAvatarKind.image) {
      _resolveFile(serial, _avatar!, widget.profileId);
    }
  }

  Future<void> _resolveFile(
    int serial,
    ProfileAvatar avatar,
    String profileId,
  ) async {
    final file = await ProfileAvatarStorage.resolveExisting(profileId, avatar);
    if (!mounted || serial != _resolveSerial || _avatar != avatar) return;
    setState(() => _file = file);
  }

  /// The whole of focus-only animation for procedural art: run the controller
  /// while focused, hold it still otherwise.
  void _syncTicker() {
    final art = _avatar?.kind == ProfileAvatarKind.art
        ? ProfileArtRegistry.byId(_avatar!.id)
        : null;
    final shouldRun =
        (widget.focused || widget.animateWhenIdle) &&
        widget.allowAnimation &&
        !(art?.isAsset ?? false) &&
        (art?.animated ?? false);
    if (shouldRun) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _avatar;
    switch (avatar?.kind) {
      case ProfileAvatarKind.art:
        final art = ProfileArtRegistry.byId(avatar!.id);
        if (art != null) return _buildArt(art);
      case ProfileAvatarKind.image:
        final file = _file;
        if (file != null) return _buildImage(avatar!, file);
        // Absent file: fall through to the colour-and-initial floor.
        return _buildFallback();
      case ProfileAvatarKind.icon:
      case null:
        break;
    }
    return _buildIcon();
  }

  Widget _buildArt(ProfileArt art) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final assetPath = art.assetPath;
      if (assetPath != null) return _buildAssetArt(art, assetPath);
      return CustomPaint(
        // Keyed so a test can find *this* painter: a MaterialApp is full of
        // framework CustomPaints, and `find.byType(CustomPaint).first` picks one
        // of those instead.
        key: ProfileAvatarView.artPaintKey,
        painter: _ArtPainter(art: art, t: _controller.value),
        isComplex: true,
        willChange: _controller.isAnimating,
        size: Size.infinite,
      );
    },
  );

  Widget _buildAssetArt(ProfileArt art, String assetPath) {
    if ((widget.focused || widget.animateWhenIdle) &&
        widget.allowAnimation &&
        art.animated) {
      return Image.asset(
        assetPath,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }
    return _StillFrame.asset(
      key: ProfileAvatarView.stillFrameKey,
      assetPath: assetPath,
      placeholderColor: art.color,
    );
  }

  Widget _buildImage(ProfileAvatar avatar, File file) {
    if (!avatar.isAnimatedImage) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }
    if ((widget.focused || widget.animateWhenIdle) && widget.allowAnimation) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }
    return _StillFrame.file(
      key: ProfileAvatarView.stillFrameKey,
      file: file,
      placeholderColor: ProfileAvatarView.washColor(
        widget.avatarKey,
        widget.role,
      ),
    );
  }

  Widget _buildIcon() {
    final color = ProfileAvatarView._roleColor(widget.role);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color, Color.lerp(color, Colors.black, 0.45)!],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Icon(
          ProfileAvatarView.iconFor(widget.avatarKey, widget.role),
          size: constraints.biggest.shortestSide * 0.44,
          color: Colors.white.withValues(alpha: 0.92),
        ),
      ),
    );
  }

  /// Colour plus initial — recognisably theirs, and never a broken tile.
  Widget _buildFallback() {
    final color = ProfileAvatarView.washColor(widget.avatarKey, widget.role);
    final initial = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim().characters.first.toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color, Color.lerp(color, Colors.black, 0.5)!],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: constraints.biggest.shortestSide * 0.42,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.94),
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  final ProfileArt art;
  final double t;

  const _ArtPainter({required this.art, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.clipRect(Offset.zero & size);
    art.paint!(canvas, size, t);
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.t != t || old.art.id != art.id;
}

/// The first frame of an animation, decoded once and cached.
///
/// This is what keeps a wall of GIFs affordable: only the focused tile holds a
/// live decoder, and every other tile is a single static bitmap.
class _StillFrame extends StatefulWidget {
  final File? file;
  final String? assetPath;
  final Color placeholderColor;

  const _StillFrame.file({
    super.key,
    required File this.file,
    required this.placeholderColor,
  }) : assetPath = null;

  const _StillFrame.asset({
    super.key,
    required String this.assetPath,
    required this.placeholderColor,
  }) : file = null;

  String get cacheKey => file?.path ?? 'asset:$assetPath';

  Future<Uint8List> readBytes() async {
    final sourceFile = file;
    if (sourceFile != null) return sourceFile.readAsBytes();
    final data = await rootBundle.load(assetPath!);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  State<_StillFrame> createState() => _StillFrameState();
}

class _StillFrameState extends State<_StillFrame> {
  static const int _cacheLimit = 32;
  static final LinkedHashMap<String, _StillFrameCacheEntry> _cache =
      LinkedHashMap<String, _StillFrameCacheEntry>();

  _StillFrameCacheEntry? _entry;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_StillFrame old) {
    super.didUpdateWidget(old);
    if (old.cacheKey != widget.cacheKey) {
      _releaseEntry();
      _load();
    }
  }

  @override
  void dispose() {
    _loadSerial++;
    _releaseEntry();
    super.dispose();
  }

  Future<void> _load() async {
    final serial = ++_loadSerial;
    final path = widget.cacheKey;
    // A hit becomes most-recently used, rather than leaving the map FIFO.
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached;
      cached.users++;
      _entry = cached;
      return;
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      final bytes = await widget.readBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width.clamp(1, 512),
        targetHeight: descriptor.height.clamp(1, 512),
      );
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      if (!mounted || serial != _loadSerial || widget.cacheKey != path) {
        decoded.dispose();
        decoded = null;
        return;
      }
      // Another mounted tile may have completed the same path first.
      final raced = _cache.remove(path);
      late final _StillFrameCacheEntry entry;
      if (raced != null) {
        decoded.dispose();
        decoded = null;
        entry = raced;
      } else {
        entry = _StillFrameCacheEntry(decoded);
        decoded = null;
      }
      entry.users++;
      _entry = entry;
      _cache[path] = entry;
      _evict();
      setState(() {});
    } catch (_) {
      decoded?.dispose();
      // An unreadable frame is not an error worth surfacing — the placeholder
      // colour already reads as the profile's own.
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static void _evict() {
    while (_cache.length > _cacheLimit) {
      final oldest = _cache.remove(_cache.keys.first)!;
      oldest.cached = false;
      if (oldest.users == 0) oldest.image.dispose();
    }
  }

  void _releaseEntry() {
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    entry.users--;
    if (!entry.cached && entry.users == 0) entry.image.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    if (entry == null) {
      return ColoredBox(color: widget.placeholderColor);
    }
    return RawImage(image: entry.image, fit: BoxFit.cover);
  }
}

class _StillFrameCacheEntry {
  final ui.Image image;
  int users = 0;
  bool cached = true;

  _StillFrameCacheEntry(this.image);
}

@visibleForTesting
int debugStillFrameCacheSize() => _StillFrameState._cache.length;
