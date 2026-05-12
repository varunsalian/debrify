import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/android_native_downloader.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'remote_control_screen.dart';
import 'remote_receive_screen.dart';

/// Entry point for the Remote feature. Lets the user pick whether this
/// device should act as the **Sender** (controls another device, exports
/// setup) or the **Receiver** (waits to be controlled / receive setup).
///
/// On pop, restores the boot-default role for this device so existing
/// flows keep working (TV stays discoverable, phone keeps scanning).
class RemoteRolePickerScreen extends StatefulWidget {
  const RemoteRolePickerScreen({super.key});

  @override
  State<RemoteRolePickerScreen> createState() => _RemoteRolePickerScreenState();
}

class _RemoteRolePickerScreenState extends State<RemoteRolePickerScreen> {
  final FocusNode _sendFocus = FocusNode(debugLabel: 'remote-pick-send');
  final FocusNode _recvFocus = FocusNode(debugLabel: 'remote-pick-recv');

  /// True once the user actually picks Send or Receive. We only restore the
  /// boot-default role on dispose if a switch happened, so simply opening
  /// and closing the picker doesn't churn the network services.
  bool _didSwitch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _sendFocus.dispose();
    _recvFocus.dispose();
    if (_didSwitch) {
      // Restore the device's default role only if we changed it, so the TV
      // keeps listening and the phone keeps scanning.
      _restoreDefaultRole();
    }
    super.dispose();
  }

  Future<void> _restoreDefaultRole() async {
    try {
      final isTv = await AndroidNativeDownloader.isTelevision();
      final state = RemoteControlState();
      if (isTv) {
        var name = await StorageService.getRemoteTvDeviceName();
        name ??= await PlatformUtil.getDeviceName();
        name ??= 'Debrify TV';
        await state.switchToReceiverMode(name);
      } else {
        await state.switchToSenderMode();
      }
    } catch (_) {
      // Best-effort; if restore fails the user can re-enter the picker.
    }
  }

  Future<void> _openSender() async {
    HapticFeedback.mediumImpact();
    final state = RemoteControlState();
    if (state.isTv) {
      _didSwitch = true;
      await state.switchToSenderMode();
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteControlScreen()));
  }

  Future<void> _openReceiver() async {
    HapticFeedback.mediumImpact();
    var name = await StorageService.getRemoteTvDeviceName();
    name ??= await PlatformUtil.getDeviceName();
    name ??= 'This device';
    final state = RemoteControlState();
    if (!state.isTv) {
      _didSwitch = true;
      await state.switchToReceiverMode(name);
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteReceiveScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14101C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Remote',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        ),
      ),
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 720;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        'How will this device take part?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Either device can control the other or share setup. '
                        'Pick a role to continue.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _RoleCard(
                                focusNode: _sendFocus,
                                icon: Icons.send_rounded,
                                title: 'Send',
                                subtitle:
                                    'Control another device or push your '
                                    'addons, channels, and setup to it.',
                                bullets: const [
                                  'Navigate with a D-pad',
                                  'Send setup, addons, channels',
                                  'Pair over Wi-Fi',
                                ],
                                onTap: _openSender,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _RoleCard(
                                focusNode: _recvFocus,
                                icon: Icons.download_rounded,
                                title: 'Receive',
                                subtitle:
                                    'Let another device control this one or '
                                    'send its setup to it.',
                                bullets: const [
                                  'Show as a target on the network',
                                  'Receive addons, channels, sessions',
                                  'Stay paired until you leave',
                                ],
                                onTap: _openReceiver,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _RoleCard(
                          focusNode: _sendFocus,
                          icon: Icons.send_rounded,
                          title: 'Send',
                          subtitle:
                              'Control another device or push your addons, '
                              'channels, and setup to it.',
                          bullets: const [
                            'Navigate with a D-pad',
                            'Send setup, addons, channels',
                            'Pair over Wi-Fi',
                          ],
                          onTap: _openSender,
                        ),
                        const SizedBox(height: 14),
                        _RoleCard(
                          focusNode: _recvFocus,
                          icon: Icons.download_rounded,
                          title: 'Receive',
                          subtitle:
                              'Let another device control this one or send '
                              'its setup to it.',
                          bullets: const [
                            'Show as a target on the network',
                            'Receive addons, channels, sessions',
                            'Stay paired until you leave',
                          ],
                          onTap: _openReceiver,
                        ),
                      ],
                      const SizedBox(height: 24),
                      _NetworkHint(),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final VoidCallback onTap;

  const _RoleCard({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.onTap,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onShowFocusHighlight: (v) {
        if (mounted) setState(() => _focused = v);
      },
      mouseCursor: SystemMouseCursors.click,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(_focused ? 1.015 : 1.0),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _focused
                  ? [
                      const Color(0xFFED1C24).withValues(alpha: 0.18),
                      const Color(0xFFED1C24).withValues(alpha: 0.06),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.05),
                      Colors.white.withValues(alpha: 0.02),
                    ],
            ),
            border: Border.all(
              color: _focused
                  ? const Color(0xFFED1C24).withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.08),
              width: _focused ? 2 : 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: const Color(0xFFED1C24).withValues(alpha: 0.35),
                      blurRadius: 26,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFED1C24), Color(0xFFB81D24)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFED1C24,
                          ).withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: -3,
                        ),
                      ],
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              ...widget.bullets.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 7),
                        decoration: const BoxDecoration(
                          color: Color(0xFFED1C24),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.wifi_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Both devices need to be on the same Wi-Fi network.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF14101C),
                    Color(0xFF0A0810),
                    Color(0xFF030305),
                  ],
                  stops: [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -200,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 560,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFED1C24).withValues(alpha: 0.22),
                      const Color(0xFFED1C24).withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
