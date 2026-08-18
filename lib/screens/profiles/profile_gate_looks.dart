import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../utils/platform_util.dart';
import '../../widgets/profiles/profile_avatar_view.dart';

/// The three 2026-08-17 gate looks — Row, Marquee and Theater (the default).
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

/// Marquee: the Spotlight rail-and-stage grammar. The focused person IS the
/// screen — display-type name, role/PIN chips, a white Continue pill and
/// their avatar huge on the right — while the household is a quiet rail of
/// circles. Focus lives on the rail only.
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
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(.85, 0),
            radius: 1.3,
            colors: [wash.withValues(alpha: .34), _kGround],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // A portrait tablet can be wider than a phone but still has no
              // room for the side-by-side stage.  Treating it as a desktop
              // layout makes the artwork overlap the copy and leaves the
              // focused rail pressed against the bottom edge.
              final wide =
                  constraints.maxWidth >= 700 &&
                  constraints.maxWidth >= constraints.maxHeight;
              return wide ? _wide(constraints) : _narrow(constraints);
            },
          ),
        ),
      ),
    );
  }

  Widget _wide(BoxConstraints constraints) {
    final artSize = (constraints.maxHeight * 0.72).clamp(220.0, 560.0);
    return Stack(
      children: [
        Positioned(
          right: -artSize * 0.16,
          top: 0,
          bottom: 0,
          child: Center(child: _stageArt(artSize)),
        ),
        Positioned(
          left: constraints.maxWidth * 0.065,
          top: 0,
          bottom: constraints.maxHeight * 0.2,
          right: constraints.maxWidth * 0.42,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _stageInfo(nameSize: 58, alignStart: true),
          ),
        ),
        Positioned(
          left: constraints.maxWidth * 0.065,
          bottom: 30,
          right: 24,
          child: Row(
            children: [
              // A big household must scroll along the rail, not overflow
              // off the right edge of a 960-logical TV. Expanded+Align, not
              // Flexible+Spacer: a Spacer would claim half the free width,
              // capping the rail's viewport and pushing the legend off the
              // right edge.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _rail(dot: 56),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const _KeyLegend(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _narrow(BoxConstraints constraints) {
    const focusPaintInset = 12.0;
    const topInset = 34.0;
    const bottomInset = 42.0;
    final minContentHeight = constraints.maxHeight > topInset + bottomInset
        ? constraints.maxHeight - topInset - bottomInset
        : 0.0;
    return SingleChildScrollView(
      // AnimatedScale paints beyond the rail dot's layout bounds.  Do not
      // crop its focus ring/shadow while this vertical surface scrolls.
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(26, topInset, 26, bottomInset),
      child: Center(
        child: ConstrainedBox(
          // A wide portrait tablet should retain the composed phone layout,
          // rather than stretching its stage copy across the whole display.
          constraints: BoxConstraints(
            maxWidth: 460,
            minHeight: minContentHeight,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stageArt((constraints.maxWidth * 0.42).clamp(120.0, 200.0)),
                const SizedBox(height: 20),
                ..._stageInfo(nameSize: 34, alignStart: false),
                const SizedBox(height: 30),
                // Leave paint room around a scaled dot (and its lock badge),
                // so the initial focused profile is wholly visible.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: focusPaintInset,
                  ),
                  child: _rail(dot: 62, wrap: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stageArt(double size) {
    final p = _focusedProfile;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: Container(
        key: ValueKey<String>(p?.id ?? 'manage'),
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _wash.withValues(alpha: .4),
              blurRadius: 60,
              spreadRadius: 4,
            ),
          ],
        ),
        child: p == null
            ? Container(
                color: _kNeutralWash,
                child: Icon(
                  Icons.manage_accounts_rounded,
                  size: size * 0.4,
                  color: Colors.white.withValues(alpha: .7),
                ),
              )
            // The stage copy is the focus indicator — it animates; the rail
            // dots stay still (one moving avatar, the house contract).
            : ProfileAvatarView(
                profileId: p.id,
                avatarKey: p.avatarKey,
                role: p.role,
                name: p.name,
                focused: true,
                animateWhenIdle: !PlatformUtil.isTelevision,
              ),
      ),
    );
  }

  List<Widget> _stageInfo({
    required double nameSize,
    required bool alignStart,
  }) {
    final p = _focusedProfile;
    final cross = alignStart
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.6,
          color: Colors.white.withValues(alpha: .6),
        ),
      ),
    );
    return [
      Text(
        p == null ? 'HOUSEHOLD' : 'PROFILE',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
          color: Color(0xFFE23D4C),
        ),
      ),
      const SizedBox(height: 10),
      Column(
        crossAxisAlignment: cross,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              p?.name ?? 'Manage profiles',
              maxLines: 1,
              style: TextStyle(
                fontSize: nameSize,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (p != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                chip(_roleLabel(p.role)),
                if (p.hasPin) ...[const SizedBox(width: 8), chip('PIN')],
              ],
            )
          else
            Text(
              'Create, edit, back up, send to TV',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: .55),
              ),
            ),
          const SizedBox(height: 24),
          // A visual echo of OK for touch; not a focus stop, so DPAD keeps
          // exactly one grammar (the rail).
          GestureDetector(
            onTap: () {
              final profile = _focusedProfile;
              if (profile != null) {
                widget.onSelected(profile);
              } else {
                widget.onManage?.call();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 26),
                ],
              ),
              child: Text(
                p == null ? 'Open' : 'Continue as ${p.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0B0F17),
                ),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _rail({required double dot, bool wrap = false}) {
    final dots = <Widget>[
      for (var i = 0; i < widget.profiles.length; i++) _dot(i, dot),
      if (widget.onManage != null) _manageDot(dot),
    ];
    if (wrap) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: dots,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in dots)
          Padding(padding: const EdgeInsets.only(right: 14), child: d),
      ],
    );
  }

  Widget _dot(int index, double size) {
    final p = widget.profiles[index];
    return _GateFocusable(
      autofocus: index == 0,
      onFocus: () => setState(() => _focusedIndex = index),
      onPressed: () => widget.onSelected(p),
      builder: (context, hasFocus) => _MarqueeDot(
        size: size,
        lifted: hasFocus,
        locked: p.hasPin,
        child: ProfileAvatarView(
          profileId: p.id,
          avatarKey: p.avatarKey,
          role: p.role,
          name: p.name,
          // The stage copy animates; the dot never does.
          allowAnimation: false,
        ),
      ),
    );
  }

  Widget _manageDot(double size) {
    return _GateFocusable(
      autofocus: false,
      onFocus: () => setState(() => _focusedIndex = widget.profiles.length),
      onPressed: widget.onManage!,
      builder: (context, hasFocus) => _MarqueeDot(
        size: size,
        lifted: hasFocus,
        locked: false,
        outlined: true,
        child: Center(
          child: Icon(
            Icons.manage_accounts_rounded,
            size: size * 0.42,
            color: Colors.white.withValues(alpha: .6),
          ),
        ),
      ),
    );
  }
}

class _MarqueeDot extends StatelessWidget {
  final double size;
  final bool lifted;
  final bool locked;
  final bool outlined;
  final Widget child;

  const _MarqueeDot({
    required this.size,
    required this.lifted,
    required this.locked,
    required this.child,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: lifted ? 1.12 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: lifted ? 1 : .55,
        duration: const Duration(milliseconds: 200),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  width: 2.5,
                  color: lifted
                      ? Colors.white
                      : outlined
                      ? Colors.white.withValues(alpha: .25)
                      : Colors.transparent,
                ),
              ),
              child: child,
            ),
            if (locked)
              Positioned(
                bottom: -2,
                right: -2,
                child: _LockBadge(size: size * 0.16),
              ),
          ],
        ),
      ),
    );
  }
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
