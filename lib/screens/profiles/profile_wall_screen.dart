import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/profiles/profile_preferences.dart';
import '../../utils/platform_util.dart';
import '../../widgets/profiles/profile_avatar_view.dart';

/// The gate's style. Device-level, because the gate renders before any
/// profile is entered and profile-scoped preferences do not exist yet at
/// that point.
///
/// `marquee` is the DEFAULT (2026-08-17, after a couch comparison of all
/// five): a device that never chose keeps getting the flagship look; an
/// explicit earlier choice is a stored value and survives.
class ProfileGateStyle {
  ProfileGateStyle._();

  static const String key = 'profile_gate_style_v1';
  static const String classic = 'classic';
  static const String wall = 'wall';
  static const String row = 'row';
  static const String marquee = 'marquee';
  static const String theater = 'theater';

  static const String defaultStyle = marquee;

  /// Picker metadata, in display order.
  static const List<({String id, String label, String blurb})> options = [
    (
      id: marquee,
      label: 'Marquee',
      blurb: 'A big stage for whoever is focused',
    ),
    (
      id: theater,
      label: 'Theater',
      blurb: 'The chosen profile lights the whole room',
    ),
    (id: row, label: 'Row', blurb: 'A simple row of portraits'),
    (
      id: wall,
      label: 'Portrait Wall',
      blurb: 'Tall posters, colour-washed room',
    ),
    (id: classic, label: 'Classic', blurb: 'The original card grid'),
  ];

  static String labelFor(String id) =>
      options.firstWhere((o) => o.id == id, orElse: () => options.first).label;

  /// Synchronous mirror for build paths; loaded whenever the gate loads its
  /// roster, and after the hub writes a change.
  static String cached = defaultStyle;

  static Future<void> warm() async {
    final device = await DevicePreferences.instance();
    cached = device.getString(key) ?? defaultStyle;
  }

  static Future<void> set(String value) async {
    final device = await DevicePreferences.instance();
    await device.setString(key, value);
    cached = value;
  }
}

/// Whether launch always stops at "Who's watching?", even when a sole
/// PIN-less profile could auto-enter. Device-level for the same reason as
/// [ProfileGateStyle]: the gate consults it before any profile exists.
///
/// Defaults ON — the profile screen is the app's front door, and skipping it
/// is the opt-out (the startup toggle on Settings → Profiles). The gate's
/// OTHER auto-enter suppressions (explicit Switch, lock, resume) are not
/// this setting's business and keep their own `allowSingleProfileAutoEnter`
/// argument.
class ProfileGateAlwaysAsk {
  ProfileGateAlwaysAsk._();

  static const String key = 'profile_gate_always_ask_v1';

  /// Synchronous mirror for build paths; loaded whenever the gate loads its
  /// roster, and after the hub writes a change.
  static bool cached = true;

  static Future<void> warm() async {
    final device = await DevicePreferences.instance();
    cached = device.getBool(key) ?? true;
  }

  static Future<void> set(bool value) async {
    final device = await DevicePreferences.instance();
    await device.setBool(key, value);
    cached = value;
  }
}

/// Portrait Wall — the redesigned "Who's watching?".
///
/// Same contract as the classic picker: [onSelected] and [onManage] come from
/// [ProfileGate], which owns activation, PIN routing and — critically — the
/// management authorization ladder. This widget adds no capability; a tile
/// press and the Manage chip reach exactly what the classic buttons reached.
///
/// Focus is the composition: the focused tile lifts, saturates, animates its
/// avatar, and repaints the room in that avatar's colour. Everything else
/// recedes. Only one avatar ever animates (see [ProfileAvatarView]).
class ProfileWallScreen extends StatefulWidget {
  final List<UserProfile> profiles;
  final ValueChanged<UserProfile> onSelected;
  final VoidCallback? onManage;

  const ProfileWallScreen({
    super.key,
    required this.profiles,
    required this.onSelected,
    this.onManage,
  });

  @override
  State<ProfileWallScreen> createState() => _ProfileWallScreenState();
}

class _ProfileWallScreenState extends State<ProfileWallScreen> {
  int _focusedIndex = 0;

  Color get _washColor {
    final profiles = widget.profiles;
    if (profiles.isEmpty || _focusedIndex >= profiles.length) {
      return const Color(0xFF31435F); // the Manage tile's neutral room
    }
    final profile = profiles[_focusedIndex];
    return ProfileAvatarView.washColor(profile.avatarKey, profile.role);
  }

  @override
  Widget build(BuildContext context) {
    const ground = Color(0xFF0D1420);
    final wash = _washColor;
    return Scaffold(
      backgroundColor: ground,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.25),
            radius: 1.25,
            colors: <Color>[wash.withValues(alpha: .32), ground],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              return Column(
                children: [
                  const Spacer(flex: 2),
                  Text(
                    'DEBRIFY',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 4,
                      color: Colors.white.withValues(alpha: .4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Who's watching?",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      letterSpacing: -.5,
                    ),
                  ),
                  const Spacer(flex: 2),
                  Flexible(flex: 9, child: wide ? _wideRow() : _narrowGrid()),
                  const Spacer(flex: 2),
                  if (widget.onManage != null)
                    _ManageChip(
                      onFocus: () => setState(
                        () => _focusedIndex = widget.profiles.length,
                      ),
                      onPressed: widget.onManage!,
                    ),
                  const SizedBox(height: 22),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _wideRow() => Center(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.profiles.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _tile(i, width: 150),
            ),
        ],
      ),
    ),
  );

  Widget _narrowGrid() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 26),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 14,
      children: [
        for (var i = 0; i < widget.profiles.length; i++) _tile(i, width: 132),
      ],
    ),
  );

  Widget _tile(int index, {required double width}) {
    final profile = widget.profiles[index];
    final focused = _focusedIndex == index;
    return _WallTile(
      width: width,
      focused: focused,
      autofocus: index == 0,
      haloColor: ProfileAvatarView.washColor(profile.avatarKey, profile.role),
      onFocus: () => setState(() => _focusedIndex = index),
      onPressed: () => widget.onSelected(profile),
      caption: profile.name,
      subCaption: _roleLabel(profile.role),
      locked: profile.hasPin,
      child: ProfileAvatarView(
        profileId: profile.id,
        avatarKey: profile.avatarKey,
        role: profile.role,
        name: profile.name,
        focused: focused,
        // TV keeps the focus-only contract (one moving tile is the focus
        // indicator); on touch nothing is ever focused, so without this a
        // chosen GIF simply never moved.
        animateWhenIdle: !PlatformUtil.isTelevision,
      ),
    );
  }

  static String _roleLabel(UserProfileRole role) => switch (role) {
    UserProfileRole.admin => 'ADMIN',
    UserProfileRole.member => 'MEMBER',
    UserProfileRole.child => 'KID',
  };
}

class _WallTile extends StatelessWidget {
  final double width;
  final bool focused;
  final bool autofocus;
  final Color haloColor;
  final VoidCallback onFocus;
  final VoidCallback onPressed;
  final String caption;
  final String subCaption;
  final bool locked;
  final Widget child;

  const _WallTile({
    required this.width,
    required this.focused,
    required this.autofocus,
    required this.haloColor,
    required this.onFocus,
    required this.onPressed,
    required this.caption,
    required this.subCaption,
    required this.locked,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onFocusChange: (hasFocus) {
        if (hasFocus) onFocus();
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              // Touch: first tap focuses (repainting the room), a tap on the
              // focused tile enters. DPAD/OK goes through onKeyEvent below.
              if (hasFocus || focused) {
                onPressed();
              } else {
                Focus.of(context).requestFocus();
              }
            },
            child: _tileBody(context, hasFocus),
          );
        },
      ),
      onKeyEvent: (node, event) {
        // OK on a remote arrives as select or enter depending on the device;
        // some BT remotes send space.
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  Widget _tileBody(BuildContext context, bool hasFocus) {
    final lifted = hasFocus || focused;
    return AnimatedScale(
      scale: lifted ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: lifted ? 1 : .62,
        duration: const Duration(milliseconds: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: width,
              height: width * 4 / 3,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  width: 2.5,
                  color: lifted ? Colors.white : Colors.transparent,
                ),
                boxShadow: lifted
                    ? <BoxShadow>[
                        BoxShadow(
                          color: haloColor.withValues(alpha: .45),
                          blurRadius: 38,
                          spreadRadius: 2,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColorFiltered(
                    colorFilter: lifted
                        ? const ColorFilter.mode(
                            Colors.transparent,
                            BlendMode.dst,
                          )
                        : const ColorFilter.matrix(<double>[
                            // Desaturate the unfocused wall.
                            .45, .35, .12, 0, 0, //
                            .18, .62, .12, 0, 0,
                            .18, .35, .39, 0, 0,
                            0, 0, 0, 1, 0,
                          ]),
                    child: child,
                  ),
                  if (locked)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
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
            const SizedBox(height: 3),
            Text(
              subCaption,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .38),
                fontSize: 9,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageChip extends StatelessWidget {
  final VoidCallback onFocus;
  final VoidCallback onPressed;

  const _ManageChip({required this.onFocus, required this.onPressed});

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (focused) {
      if (focused) onFocus();
    },
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: .75),
        side: BorderSide(color: Colors.white.withValues(alpha: .22)),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.manage_accounts_rounded, size: 18),
      label: const Text('Manage profiles'),
    ),
  );
}
