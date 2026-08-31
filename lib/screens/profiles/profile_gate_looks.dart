import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../utils/platform_util.dart';
import '../../widgets/profiles/profile_avatar_view.dart';

/// The 2026-08-17 gate looks — Row, Marquee, Theater — plus Stage Cards
/// (2026-08-31, the default).
///
/// All share the wall's contract exactly: [onSelected] / [onManage] come from
/// `ProfileGate`, which owns activation, PIN routing and the management
/// authorization ladder — these widgets add no capability. They also share
/// its interaction grammar:
///  * DPAD: profile tiles are the only focus stops, OK/enter/space activates,
///    geometric traversal moves along the run (a single row/wrap, so it is
///    unambiguous). The first tile autofocuses.
///  * Touch: first tap focuses (repainting the room), a tap on the focused
///    tile enters.
///  * Only the focused tile's avatar animates on TV (the focus indicator);
///    touch surfaces opt in to idle animation so a chosen GIF actually moves.
const Color _kGround = Color(0xFF0D1420);
const Color _kNeutralWash = Color(0xFF31435F);

String _roleLabel(UserProfileRole role) => switch (role) {
  UserProfileRole.admin => 'ADMIN',
  UserProfileRole.member => 'MEMBER',
  UserProfileRole.child => 'KID',
};

/// Re-bounds a remembered focus index after the gate reloads a shorter
/// roster — otherwise the stage keeps announcing "Manage profiles" while
/// nothing holds focus (the deleted tile's node is gone).
int _clampFocusIndex(int index, int profileCount, {required bool hasManage}) {
  final last = hasManage ? profileCount : profileCount - 1;
  if (last < 0) return 0;
  return index > last ? last : index;
}

/// The shared focus/tap/OK contract around every tile body.
class _GateFocusable extends StatelessWidget {
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onPressed;
  final Widget Function(BuildContext context, bool hasFocus) builder;

  const _GateFocusable({
    required this.autofocus,
    required this.onFocus,
    required this.onPressed,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onFocusChange: (hasFocus) {
        if (hasFocus) onFocus();
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              if (hasFocus) {
                onPressed();
              } else {
                Focus.of(context).requestFocus();
              }
            },
            child: builder(context, hasFocus),
          );
        },
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  final double size;
  const _LockBadge({this.size = 13});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(size * 0.38),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(size * 0.6),
    ),
    child: Icon(Icons.lock_rounded, size: size, color: Colors.white),
  );
}

/// The TV footer key legend; nothing on touch (tap grammar needs no manual).
class _KeyLegend extends StatelessWidget {
  const _KeyLegend();

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtil.isTelevision) return const SizedBox.shrink();
    Widget item(String key, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: .3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: .55),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.white.withValues(alpha: .45),
          ),
        ),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        item('OK', 'Open profile'),
        const SizedBox(width: 16),
        item('← →', 'Choose'),
      ],
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'DEBRIFY',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 5,
          color: Colors.white.withValues(alpha: .38),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        "Who's watching?",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
          color: Colors.white,
        ),
      ),
    ],
  );
}

// ───────────────────────────────────────────────────────────── Row ────────

/// Netflix Row: one centred run of square plates on a flat ground. The
/// focused plate scales with a white ring; everything else dims. Manage is
/// the last plate in the run.
class ProfileRowGateScreen extends StatefulWidget {
  final List<UserProfile> profiles;
  final ValueChanged<UserProfile> onSelected;
  final VoidCallback? onManage;

  const ProfileRowGateScreen({
    super.key,
    required this.profiles,
    required this.onSelected,
    this.onManage,
  });

  @override
  State<ProfileRowGateScreen> createState() => _ProfileRowGateScreenState();
}

class _ProfileRowGateScreenState extends State<ProfileRowGateScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kGround,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;
            final plate = wide
                ? (constraints.maxWidth * 0.14).clamp(120.0, 190.0)
                : (constraints.maxWidth * 0.34).clamp(104.0, 150.0);
            final tiles = <Widget>[
              for (final p in widget.profiles)
                _tile(p, plate, autofocus: p == widget.profiles.first),
              if (widget.onManage != null) _manageTile(plate),
            ];
            return Column(
              children: [
                const Spacer(flex: 2),
                const _BrandHeader(),
                const Spacer(flex: 2),
                Flexible(
                  flex: 9,
                  child: wide
                      ? Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final t in tiles)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: t,
                                  ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 26),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 18,
                            runSpacing: 18,
                            children: tiles,
                          ),
                        ),
                ),
                const Spacer(flex: 2),
                const _KeyLegend(),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tile(UserProfile p, double side, {required bool autofocus}) {
    return _GateFocusable(
      autofocus: autofocus,
      onFocus: () {},
      onPressed: () => widget.onSelected(p),
      builder: (context, hasFocus) => _RowPlate(
        side: side,
        lifted: hasFocus,
        caption: p.name,
        locked: p.hasPin,
        child: ProfileAvatarView(
          profileId: p.id,
          avatarKey: p.avatarKey,
          role: p.role,
          name: p.name,
          focused: hasFocus,
          animateWhenIdle: !PlatformUtil.isTelevision,
        ),
      ),
    );
  }

  Widget _manageTile(double side) {
    return _GateFocusable(
      autofocus: false,
      onFocus: () {},
      onPressed: widget.onManage!,
      builder: (context, hasFocus) => _RowPlate(
        side: side,
        lifted: hasFocus,
        caption: 'Manage',
        locked: false,
        outlined: true,
        child: Center(
          child: Icon(
            Icons.manage_accounts_rounded,
            size: side * 0.34,
            color: Colors.white.withValues(alpha: .6),
          ),
        ),
      ),
    );
  }
}

class _RowPlate extends StatelessWidget {
  final double side;
  final bool lifted;
  final String caption;
  final bool locked;
  final bool outlined;
  final Widget child;

  const _RowPlate({
    required this.side,
    required this.lifted,
    required this.caption,
    required this.locked,
    required this.child,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: lifted ? 1.1 : 1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: lifted ? 1 : .55,
        duration: const Duration(milliseconds: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: side,
              height: side,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(side * 0.1),
                border: Border.all(
                  width: 2.5,
                  color: lifted
                      ? Colors.white
                      : outlined
                      ? Colors.white.withValues(alpha: .25)
                      : Colors.transparent,
                ),
                boxShadow: lifted
                    ? const [
                        BoxShadow(color: Color(0x99000000), blurRadius: 34),
                      ]
                    : const [],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  if (locked)
                    const Positioned(top: 8, right: 8, child: _LockBadge()),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: lifted ? 1 : .6),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── Marquee ──────────

/// Marquee: the cinematic, lighthouse-lit front door. A crop-safe background
/// carries the room while the household remains unmistakably in the foreground:
/// a focusable avatar rail on TV and desktop, a card grid on tablet, and big
/// tap targets on phones. The asset deliberately leaves its left half quiet,
/// so the same artwork remains readable at every aspect ratio.
class ProfileMarqueeGateScreen extends StatefulWidget {
  final List<UserProfile> profiles;
  final ValueChanged<UserProfile> onSelected;
  final VoidCallback? onManage;

  const ProfileMarqueeGateScreen({
    super.key,
    required this.profiles,
    required this.onSelected,
    this.onManage,
  });

  @override
  State<ProfileMarqueeGateScreen> createState() =>
      _ProfileMarqueeGateScreenState();
}

class _ProfileMarqueeGateScreenState extends State<ProfileMarqueeGateScreen> {
  int _focusedIndex = 0;

  @override
  void didUpdateWidget(covariant ProfileMarqueeGateScreen old) {
    super.didUpdateWidget(old);
    _focusedIndex = _clampFocusIndex(
      _focusedIndex,
      widget.profiles.length,
      hasManage: widget.onManage != null,
    );
  }

  bool get _manageFocused =>
      widget.onManage != null && _focusedIndex >= widget.profiles.length;

  UserProfile? get _focusedProfile {
    if (widget.profiles.isEmpty || _manageFocused) return null;
    return widget.profiles[_focusedIndex.clamp(0, widget.profiles.length - 1)];
  }

  Color get _wash {
    final p = _focusedProfile;
    if (p == null) return _kNeutralWash;
    return ProfileAvatarView.washColor(p.avatarKey, p.role);
  }

  @override
  Widget build(BuildContext context) {
    final wash = _wash;
    return Scaffold(
      backgroundColor: _kGround,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/profile_gate_lighthouse.png',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          // Preserve the lighthouse's warmth while guaranteeing text and
          // focus-ring contrast over every crop of the image.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0x330D1420), Color(0xAA0D1420), _kGround],
                stops: [0, .58, 1],
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-.8, .2),
                radius: 1.15,
                colors: [wash.withValues(alpha: .20), Colors.transparent],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= 720 &&
                    constraints.maxWidth >= constraints.maxHeight;
                if (wide) return _wide(constraints);
                if (constraints.maxWidth >= 600) return _tablet(constraints);
                return _phone();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wide(BoxConstraints constraints) {
    final tile = (constraints.maxHeight * .20).clamp(82.0, 130.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        (constraints.maxWidth * .065).clamp(32.0, 110.0),
        26,
        32,
        18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CinematicHeader(aligned: true),
          const Spacer(flex: 3),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: _rail(size: tile),
          ),
          const SizedBox(height: 22),
          if (widget.onManage != null) _manageLink(aligned: true),
          const Spacer(flex: 2),
          const Align(alignment: Alignment.center, child: _KeyLegend()),
        ],
      ),
    );
  }

  Widget _tablet(BoxConstraints constraints) {
    final cardWidth = (constraints.maxWidth - 68) / 2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
      children: [
        const _CinematicHeader(aligned: false),
        const SizedBox(height: 30),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < widget.profiles.length; i++)
              SizedBox(width: cardWidth, child: _card(i, compact: false)),
          ],
        ),
        if (widget.onManage != null) ...[
          const SizedBox(height: 16),
          _manageCard(),
        ],
      ],
    );
  }

  Widget _phone() => ListView(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
    children: [
      const _CinematicHeader(aligned: false),
      const SizedBox(height: 28),
      for (var i = 0; i < widget.profiles.length; i++) ...[
        _card(i, compact: true),
        const SizedBox(height: 12),
      ],
      if (widget.onManage != null) _manageCard(),
    ],
  );

  Widget _rail({required double size}) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < widget.profiles.length; i++)
        Padding(
          padding: const EdgeInsets.only(right: 24),
          child: _railProfile(i, size),
        ),
    ],
  );

  Widget _railProfile(int index, double size) {
    final p = widget.profiles[index];
    return _GateFocusable(
      autofocus: index == 0,
      onFocus: () => setState(() => _focusedIndex = index),
      onPressed: () => widget.onSelected(p),
      builder: (context, hasFocus) => _CinematicRailProfile(
        size: size,
        focused: hasFocus,
        caption: p.name,
        locked: p.hasPin,
        child: ProfileAvatarView(
          profileId: p.id,
          avatarKey: p.avatarKey,
          role: p.role,
          name: p.name,
          focused: hasFocus,
          animateWhenIdle: !PlatformUtil.isTelevision,
        ),
      ),
    );
  }

  Widget _card(int index, {required bool compact}) {
    final p = widget.profiles[index];
    return _GateFocusable(
      autofocus: index == 0,
      onFocus: () => setState(() => _focusedIndex = index),
      onPressed: () => widget.onSelected(p),
      builder: (context, hasFocus) => _CinematicProfileCard(
        profile: p,
        focused: hasFocus,
        compact: compact,
      ),
    );
  }

  Widget _manageCard() => _GateFocusable(
    autofocus: false,
    onFocus: () => setState(() => _focusedIndex = widget.profiles.length),
    onPressed: widget.onManage!,
    builder: (context, hasFocus) =>
        _CinematicManageCard(focused: hasFocus, compact: true),
  );

  Widget _manageLink({required bool aligned}) => _GateFocusable(
    autofocus: false,
    onFocus: () => setState(() => _focusedIndex = widget.profiles.length),
    onPressed: widget.onManage!,
    builder: (context, hasFocus) => AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasFocus
              ? const Color(0xFFFF7A6A)
              : Colors.white.withValues(alpha: .14),
        ),
        color: Colors.black.withValues(alpha: hasFocus ? .24 : .12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.manage_accounts_outlined,
            size: 18,
            color: Colors.white.withValues(alpha: .76),
          ),
          const SizedBox(width: 8),
          Text(
            'Manage profiles',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .82),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CinematicHeader extends StatelessWidget {
  final bool aligned;

  const _CinematicHeader({required this.aligned});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: aligned
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center,
    children: [
      Text(
        'DEBRIFY',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 5,
          color: const Color(0xFFFF9A81).withValues(alpha: .94),
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        "Who's watching?",
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -.8,
          color: Colors.white,
        ),
      ),
    ],
  );
}

class _CinematicRailProfile extends StatelessWidget {
  final double size;
  final bool focused;
  final String caption;
  final bool locked;
  final Widget child;

  const _CinematicRailProfile({
    required this.size,
    required this.focused,
    required this.caption,
    required this.locked,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: focused ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: focused ? 1 : .62,
        duration: const Duration(milliseconds: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: size,
                  height: size,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      width: 3,
                      color: focused
                          ? const Color(0xFFFF7A6A)
                          : Colors.white.withValues(alpha: .10),
                    ),
                    boxShadow: focused
                        ? const [
                            BoxShadow(
                              color: Color(0x66FF7A6A),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ]
                        : const [],
                  ),
                  child: child,
                ),
                if (locked)
                  Positioned(
                    bottom: -3,
                    right: -3,
                    child: _LockBadge(size: size * .16),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              caption,
              style: TextStyle(
                color: Colors.white.withValues(alpha: focused ? 1 : .65),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CinematicProfileCard extends StatelessWidget {
  final UserProfile profile;
  final bool focused;
  final bool compact;

  const _CinematicProfileCard({
    required this.profile,
    required this.focused,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact ? 78.0 : 142.0;
    final avatar = compact ? 52.0 : 74.0;
    final wash = ProfileAvatarView.washColor(profile.avatarKey, profile.role);
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      scale: focused ? 1.015 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: height,
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            width: focused ? 2 : 1,
            color: focused
                ? const Color(0xFFFF7A6A)
                : Colors.white.withValues(alpha: .12),
          ),
          gradient: LinearGradient(
            colors: [wash.withValues(alpha: .52), const Color(0xDD111A2A)],
          ),
          boxShadow: focused
              ? const [BoxShadow(color: Color(0x55000000), blurRadius: 22)]
              : const [],
        ),
        child: Row(
          children: [
            Container(
              width: avatar,
              height: avatar,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: ProfileAvatarView(
                profileId: profile.id,
                avatarKey: profile.avatarKey,
                role: profile.role,
                name: profile.name,
                focused: focused,
                animateWhenIdle: !PlatformUtil.isTelevision,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 17 : 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (profile.hasPin)
              Icon(
                Icons.lock_outline_rounded,
                color: Colors.white.withValues(alpha: .74),
              ),
          ],
        ),
      ),
    );
  }
}

class _CinematicManageCard extends StatelessWidget {
  final bool focused;
  final bool compact;

  const _CinematicManageCard({required this.focused, required this.compact});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    height: compact ? 62 : 100,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        width: focused ? 2 : 1,
        color: focused
            ? const Color(0xFFFF7A6A)
            : Colors.white.withValues(alpha: .16),
      ),
      color: Colors.black.withValues(alpha: .28),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.manage_accounts_outlined,
          color: Colors.white.withValues(alpha: .78),
        ),
        const SizedBox(width: 10),
        Text(
          'Manage profiles',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .88),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────── Theater ──────────

/// Theater (the DEFAULT): the focused profile floods the room — their wash
/// colour and a ghost monogram (or their actual picture, dimmed, when the
/// avatar is an image) become the backdrop, the name sits in marquee type up
/// top, and the household is a shelf of globes. The focused globe rises.
class ProfileTheaterGateScreen extends StatefulWidget {
  final List<UserProfile> profiles;
  final ValueChanged<UserProfile> onSelected;
  final VoidCallback? onManage;

  const ProfileTheaterGateScreen({
    super.key,
    required this.profiles,
    required this.onSelected,
    this.onManage,
  });

  @override
  State<ProfileTheaterGateScreen> createState() =>
      _ProfileTheaterGateScreenState();
}

class _ProfileTheaterGateScreenState extends State<ProfileTheaterGateScreen> {
  int _focusedIndex = 0;

  @override
  void didUpdateWidget(covariant ProfileTheaterGateScreen old) {
    super.didUpdateWidget(old);
    _focusedIndex = _clampFocusIndex(
      _focusedIndex,
      widget.profiles.length,
      hasManage: widget.onManage != null,
    );
  }

  bool get _manageFocused =>
      widget.onManage != null && _focusedIndex >= widget.profiles.length;

  UserProfile? get _focusedProfile {
    if (widget.profiles.isEmpty || _manageFocused) return null;
    return widget.profiles[_focusedIndex.clamp(0, widget.profiles.length - 1)];
  }

  Color get _wash {
    final p = _focusedProfile;
    if (p == null) return _kNeutralWash;
    return ProfileAvatarView.washColor(p.avatarKey, p.role);
  }

  bool get _focusedHasImage {
    final p = _focusedProfile;
    if (p == null) return false;
    return ProfileAvatar.tryParse(p.avatarKey)?.kind == ProfileAvatarKind.image;
  }

  @override
  Widget build(BuildContext context) {
    final wash = _wash;
    final p = _focusedProfile;
    return Scaffold(
      backgroundColor: _kGround,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The focused profile's own picture, dimmed to a presence — the
          // "use their dp" move. Only for image avatars; art/icon kinds keep
          // the pure wash (their gradient as a backdrop would fight the
          // ghost monogram). Still frame only: a full-screen GIF backdrop is
          // a distraction and a TV GPU tax.
          if (_focusedHasImage && p != null)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              child: Opacity(
                key: ValueKey<String>(p.id),
                opacity: .22,
                child: ProfileAvatarView(
                  profileId: p.id,
                  avatarKey: p.avatarKey,
                  role: p.role,
                  name: p.name,
                  allowAnimation: false,
                ),
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 1.15),
                radius: 1.35,
                colors: [
                  wash.withValues(alpha: .42),
                  _kGround.withValues(alpha: _focusedHasImage ? .78 : 1),
                ],
              ),
            ),
          ),
          // Ghost monogram — the room knows who it is about to become.
          Align(
            alignment: const Alignment(0, -.15),
            child: LayoutBuilder(
              builder: (context, constraints) => _manageFocused || p == null
                  ? Icon(
                      Icons.manage_accounts_rounded,
                      size: constraints.maxHeight * 0.5,
                      color: Colors.white.withValues(alpha: .05),
                    )
                  : Text(
                      p.name.isEmpty
                          ? '?'
                          : p.name.characters.first.toUpperCase(),
                      style: TextStyle(
                        fontSize: constraints.maxHeight * 0.55,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: .05),
                        height: 1,
                      ),
                    ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 700;
                final orb = wide
                    ? (constraints.maxWidth * 0.115).clamp(96.0, 150.0)
                    : (constraints.maxWidth * 0.26).clamp(88.0, 120.0);
                return Column(
                  children: [
                    const Spacer(flex: 2),
                    Text(
                      'DEBRIFY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 5,
                        color: Colors.white.withValues(alpha: .38),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          p?.name ?? 'Manage profiles',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: wide ? 54 : 38,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      p == null
                          ? 'HOUSEHOLD'
                          : '${_roleLabel(p.role)}'
                                '${p.hasPin ? ' · PIN' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 4,
                        color: Colors.white.withValues(alpha: .5),
                      ),
                    ),
                    const Spacer(flex: 3),
                    // Flexible + scroll, not a bare Wrap on Spacers: a large
                    // household at accessibility text scale must scroll, not
                    // overflow (found at 6 profiles × 1.5x text).
                    Flexible(
                      flex: 9,
                      child: _shelf(wide: wide, orb: orb),
                    ),
                    const Spacer(flex: 2),
                    const _KeyLegend(),
                    const SizedBox(height: 18),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _shelf({required bool wide, required double orb}) {
    final orbs = <Widget>[
      for (var i = 0; i < widget.profiles.length; i++) _orb(i, orb),
      if (widget.onManage != null) _manageOrb(orb),
    ];
    if (wide) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final o in orbs)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: o,
              ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 20,
        runSpacing: 20,
        children: orbs,
      ),
    );
  }

  Widget _orb(int index, double size) {
    final p = widget.profiles[index];
    return _GateFocusable(
      autofocus: index == 0,
      onFocus: () => setState(() => _focusedIndex = index),
      onPressed: () => widget.onSelected(p),
      builder: (context, hasFocus) => _TheaterOrb(
        size: size,
        lifted: hasFocus,
        caption: p.name,
        locked: p.hasPin,
        halo: ProfileAvatarView.washColor(p.avatarKey, p.role),
        child: ProfileAvatarView(
          profileId: p.id,
          avatarKey: p.avatarKey,
          role: p.role,
          name: p.name,
          focused: hasFocus,
          animateWhenIdle: !PlatformUtil.isTelevision,
        ),
      ),
    );
  }

  Widget _manageOrb(double size) {
    return _GateFocusable(
      autofocus: false,
      onFocus: () => setState(() => _focusedIndex = widget.profiles.length),
      onPressed: widget.onManage!,
      builder: (context, hasFocus) => _TheaterOrb(
        size: size,
        lifted: hasFocus,
        caption: 'Manage',
        locked: false,
        halo: _kNeutralWash,
        outlined: true,
        child: Center(
          child: Icon(
            Icons.manage_accounts_rounded,
            size: size * 0.36,
            color: Colors.white.withValues(alpha: .6),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────── Stage Cards ──────────

/// Stage Cards (the DEFAULT): tall glass portrait cards on a dark stage.
/// Each card is the person's own picture over their wash colour; the focused
/// card grows, wears a white rim and a colour bloom, and re-lights the room.
/// Landscape surfaces get a centred row (the growth is the focus indicator);
/// portrait/touch surfaces get an evenly-lit grid where focus reads as rim +
/// bloom only.
class ProfileStageCardsGateScreen extends StatefulWidget {
  final List<UserProfile> profiles;
  final ValueChanged<UserProfile> onSelected;
  final VoidCallback? onManage;

  const ProfileStageCardsGateScreen({
    super.key,
    required this.profiles,
    required this.onSelected,
    this.onManage,
  });

  @override
  State<ProfileStageCardsGateScreen> createState() =>
      _ProfileStageCardsGateScreenState();
}

class _ProfileStageCardsGateScreenState
    extends State<ProfileStageCardsGateScreen> {
  static const Color _stageGround = Color(0xFF08090D);

  /// The Manage pill's focus sentinel. A negative value can never collide
  /// with a profile index when the roster grows underneath us (an appended
  /// profile would have claimed `profiles.length`, silently re-lighting the
  /// room for a card nobody focused).
  static const int _manageFocus = -1;

  int _focusedIndex = 0;
  Timer? _greetingTimer;

  @override
  void initState() {
    super.initState();
    _scheduleGreetingTick();
  }

  @override
  void didUpdateWidget(covariant ProfileStageCardsGateScreen old) {
    super.didUpdateWidget(old);
    if (_focusedIndex == _manageFocus) {
      // The pill survives roster changes; it only vanishes with permission.
      if (widget.onManage == null) _focusedIndex = 0;
      return;
    }
    _focusedIndex = _clampFocusIndex(
      _focusedIndex,
      widget.profiles.length,
      hasManage: false,
    );
  }

  @override
  void dispose() {
    _greetingTimer?.cancel();
    super.dispose();
  }

  Color get _wash {
    if (widget.profiles.isEmpty ||
        _focusedIndex < 0 ||
        _focusedIndex >= widget.profiles.length) {
      return _kNeutralWash;
    }
    final p = widget.profiles[_focusedIndex];
    return ProfileAvatarView.washColor(p.avatarKey, p.role);
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  /// The greeting is clock-derived and a TV can sit on this screen for hours,
  /// so rebuild at the next boundary (noon / 5pm / midnight) instead of
  /// wishing a rebuild happens to come along.
  void _scheduleGreetingTick() {
    final now = DateTime.now();
    final nextHour = now.hour < 12 ? 12 : (now.hour < 17 ? 17 : 24);
    final next = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(hours: nextHour));
    _greetingTimer = Timer(
      next.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleGreetingTick();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wash = _wash;
    return Scaffold(
      backgroundColor: _stageGround,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.05),
            radius: 1.3,
            colors: [wash.withValues(alpha: .22), _stageGround],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 700 &&
                  constraints.maxWidth >= constraints.maxHeight;
              return wide ? _wide(constraints) : _grid(constraints);
            },
          ),
        ),
      ),
    );
  }

  // Landscape: one centred row on the stage floor; the focused card grows.
  Widget _wide(BoxConstraints constraints) {
    // Base size leaves headroom for the focused card's 1.16x growth — on a
    // 540-logical TV the growth must come from the budget, not from clamping
    // against the row slot (which would widen text while barely growing the
    // card).
    final cardHeight = (constraints.maxHeight * .38).clamp(180.0, 331.0);
    final grownHeight = cardHeight * 1.16;
    return Column(
      children: [
        const Spacer(flex: 2),
        _StageHeader(wash: _wash, greeting: _greeting(), wide: true),
        const Spacer(flex: 2),
        Flexible(
          flex: 10,
          child: Center(
            child: SizedBox(
              height: grownHeight,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.profiles.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          child: _card(
                            i,
                            baseHeight: cardHeight,
                            growWhenFocused: true,
                            dimWhenUnfocused: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (widget.onManage != null) _managePill(),
        const Spacer(flex: 1),
        const _KeyLegend(),
        const SizedBox(height: 16),
      ],
    );
  }

  // Portrait / touch: an evenly-lit grid. Focus reads as rim + bloom only —
  // on a device in your hand nobody gets dimmed.
  Widget _grid(BoxConstraints constraints) {
    final threeUp = constraints.maxWidth >= 600;
    final columns = threeUp ? 3 : 2;
    final gutter = threeUp ? 24.0 : 16.0;
    final margin = threeUp ? 44.0 : 24.0;
    final cardWidth =
        ((constraints.maxWidth - 2 * margin - (columns - 1) * gutter) /
                columns)
            .clamp(110.0, 240.0);
    final cardHeight = cardWidth * (threeUp ? 1.4 : 1.28);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(margin, 26, margin, 30),
      child: Column(
        children: [
          _StageHeader(wash: _wash, greeting: _greeting(), wide: false),
          const SizedBox(height: 26),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: gutter,
            runSpacing: gutter,
            children: [
              for (var i = 0; i < widget.profiles.length; i++)
                SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: _card(
                    i,
                    baseHeight: cardHeight,
                    growWhenFocused: false,
                    dimWhenUnfocused: false,
                  ),
                ),
            ],
          ),
          if (widget.onManage != null) ...[
            const SizedBox(height: 24),
            _managePill(),
          ],
        ],
      ),
    );
  }

  Widget _card(
    int index, {
    required double baseHeight,
    required bool growWhenFocused,
    required bool dimWhenUnfocused,
  }) {
    final p = widget.profiles[index];
    return _GateFocusable(
      autofocus: index == 0,
      onFocus: () => setState(() => _focusedIndex = index),
      onPressed: () => widget.onSelected(p),
      builder: (context, hasFocus) => _StageCard(
        height: growWhenFocused && hasFocus ? baseHeight * 1.16 : baseHeight,
        focused: hasFocus,
        dimmed: dimWhenUnfocused && !hasFocus,
        name: p.name,
        roleLabel: _roleLabel(p.role),
        locked: p.hasPin,
        wash: ProfileAvatarView.washColor(p.avatarKey, p.role),
        child: ProfileAvatarView(
          profileId: p.id,
          avatarKey: p.avatarKey,
          role: p.role,
          name: p.name,
          focused: hasFocus,
          animateWhenIdle: !PlatformUtil.isTelevision,
        ),
      ),
    );
  }

  Widget _managePill() => _GateFocusable(
    autofocus: false,
    onFocus: () => setState(() => _focusedIndex = _manageFocus),
    onPressed: widget.onManage!,
    builder: (context, hasFocus) => AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: hasFocus ? .10 : .03),
        border: Border.all(
          width: hasFocus ? 1.5 : 1,
          color: Colors.white.withValues(alpha: hasFocus ? .85 : .14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.manage_accounts_rounded,
            size: 17,
            color: Colors.white.withValues(alpha: hasFocus ? .95 : .55),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              'Manage profiles',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: hasFocus ? .95 : .55),
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                letterSpacing: .4,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StageHeader extends StatelessWidget {
  final Color wash;
  final String greeting;
  final bool wide;

  const _StageHeader({
    required this.wash,
    required this.greeting,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'DEBRIFY',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 5,
          color: Colors.white.withValues(alpha: .32),
        ),
      ),
      SizedBox(height: wide ? 14 : 12),
      AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 350),
        style: TextStyle(
          fontSize: wide ? 13 : 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 3.5,
          color: Color.lerp(wash, Colors.white, .25)!,
        ),
        child: Text(greeting),
      ),
      SizedBox(height: wide ? 10 : 8),
      Text(
        "Who's watching?",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: wide ? 38 : 29,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          color: Colors.white,
        ),
      ),
    ],
  );
}

class _StageCard extends StatelessWidget {
  final double height;
  final bool focused;
  final bool dimmed;
  final String name;
  final String roleLabel;
  final bool locked;
  final Color wash;
  final Widget child;

  const _StageCard({
    required this.height,
    required this.focused,
    required this.dimmed,
    required this.name,
    required this.roleLabel,
    required this.locked,
    required this.wash,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final width = height * .7;
    final radius = (width * .11).clamp(16.0, 28.0);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: dimmed ? .62 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            width: focused ? 1.6 : 1,
            color: focused
                ? Colors.white.withValues(alpha: .85)
                : Colors.white.withValues(alpha: .08),
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: wash.withValues(alpha: .38),
                    blurRadius: 52,
                    spreadRadius: 2,
                  ),
                  const BoxShadow(color: Color(0x66000000), blurRadius: 30),
                ]
              : const [
                  BoxShadow(color: Color(0x55000000), blurRadius: 18),
                ],
        ),
        // Metrics come from the width that actually laid out: a grid slot's
        // tight constraints override the container's own width, and on short
        // TVs the row slot can clamp the growth — the nameplate must follow
        // the real card, not the requested one.
        child: LayoutBuilder(
          builder: (context, box) {
            final laidWidth = box.maxWidth.isFinite ? box.maxWidth : width;
            final pad = (laidWidth * .1).clamp(12.0, 28.0);
            return Stack(
              fit: StackFit.expand,
              children: [
                // The person's own picture IS the card face (art paints
                // itself, icons keep their gradient plate).
                child,
                // Bloom rising from the floor of the card, in their colour.
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 260),
                  opacity: focused ? .55 : .28,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, 1.45),
                        radius: 1.15,
                        colors: [
                          wash.withValues(alpha: .55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Scrim so the nameplate stays legible over any picture.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .42],
                      colors: [
                        Colors.black.withValues(alpha: .52),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: pad * .82,
                  left: pad,
                  right: pad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: (laidWidth * .105).clamp(14.0, 29.0),
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.5,
                                height: 1.05,
                              ),
                            ),
                          ),
                          if (locked) ...[
                            const SizedBox(width: 6),
                            _StagePinChip(width: laidWidth),
                          ],
                        ],
                      ),
                      SizedBox(height: (laidWidth * .03).clamp(3.0, 8.0)),
                      Text(
                        roleLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .5),
                          fontSize: (laidWidth * .045).clamp(7.5, 11.5),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StagePinChip extends StatelessWidget {
  final double width;

  const _StagePinChip({required this.width});

  @override
  Widget build(BuildContext context) {
    final fontSize = (width * .048).clamp(7.5, 11.0);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * .85,
        vertical: fontSize * .48,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFF090B11).withValues(alpha: .55),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_rounded,
            size: fontSize * 1.1,
            color: Colors.white.withValues(alpha: .8),
          ),
          SizedBox(width: fontSize * .4),
          Text(
            'PIN',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .8),
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TheaterOrb extends StatelessWidget {
  final double size;
  final bool lifted;
  final String caption;
  final bool locked;
  final Color halo;
  final bool outlined;
  final Widget child;

  const _TheaterOrb({
    required this.size,
    required this.lifted,
    required this.caption,
    required this.locked,
    required this.halo,
    required this.child,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: lifted ? const Offset(0, -.06) : Offset.zero,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: lifted ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: lifted ? 1 : .5,
          duration: const Duration(milliseconds: 220),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: size,
                    height: size,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 3,
                        color: lifted
                            ? Colors.white
                            : outlined
                            ? Colors.white.withValues(alpha: .25)
                            : Colors.transparent,
                      ),
                      boxShadow: lifted
                          ? [
                              BoxShadow(
                                color: halo.withValues(alpha: .5),
                                blurRadius: 44,
                                spreadRadius: 2,
                              ),
                            ]
                          : const [],
                    ),
                    child: child,
                  ),
                  if (locked)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: _LockBadge(size: size * 0.13),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: lifted ? 1 : .55),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
