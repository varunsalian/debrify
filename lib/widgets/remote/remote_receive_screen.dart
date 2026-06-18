import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/remote_control/remote_control_state.dart';
import '../../utils/tv_keys.dart';

/// Shown when the user picks **Receive** in the role picker. The device is
/// already in receiver mode (the picker switched roles before navigating
/// here); this screen just shows the live status: waiting for a sender,
/// or connected with one.
class RemoteReceiveScreen extends StatefulWidget {
  const RemoteReceiveScreen({super.key});

  @override
  State<RemoteReceiveScreen> createState() => _RemoteReceiveScreenState();
}

class _RemoteReceiveScreenState extends State<RemoteReceiveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  String? _localIp;
  Timer? _ipPoll;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    RemoteControlState().addListener(_onState);
    _resolveLocalIp();
    _ipPoll = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _resolveLocalIp(),
    );
  }

  @override
  void dispose() {
    RemoteControlState().removeListener(_onState);
    _pulse.dispose();
    _ipPoll?.cancel();
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  Future<void> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      String? best;
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (addr.isLoopback) continue;
          best ??= addr.address;
          // Prefer common LAN ranges.
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            best = addr.address;
            break;
          }
        }
      }
      if (mounted && best != _localIp) {
        setState(() => _localIp = best);
      }
    } catch (_) {
      // Best-effort; not critical.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = RemoteControlState();
    final connected = state.isConnected;

    return Scaffold(
      backgroundColor: const Color(0xFF14101C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Receiving',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        ),
      ),
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 48,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(height: 12),
                        Column(
                          children: [
                            _StatusOrb(connected: connected, pulse: _pulse),
                            const SizedBox(height: 28),
                            Text(
                              connected ? 'Connected' : 'Waiting for sender…',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              connected
                                  ? 'Ready to receive commands and setup '
                                        'from the paired device.'
                                  : 'On another device, open Remote → Send '
                                        'and pick this one from the list.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_localIp != null) _IpChip(ip: _localIp!),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: _StopButton(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              Navigator.of(context).maybePop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusOrb extends StatelessWidget {
  final bool connected;
  final AnimationController pulse;

  const _StatusOrb({required this.connected, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final accent = connected
        ? const Color(0xFF34D399)
        : const Color(0xFFED1C24);
    return SizedBox(
      width: 160,
      height: 160,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          final t = pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer ripple
              for (final phase in const [0.0, 0.5])
                Opacity(
                  opacity: (1.0 - ((t + phase) % 1.0)).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.6 + ((t + phase) % 1.0) * 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent.withValues(alpha: 0.45),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              // Solid orb
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: connected
                        ? const [Color(0xFF34D399), Color(0xFF10B981)]
                        : const [Color(0xFFED1C24), Color(0xFFB81D24)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 32,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: Icon(
                  connected ? Icons.link_rounded : Icons.wifi_tethering_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IpChip extends StatelessWidget {
  final String ip;
  const _IpChip({required this.ip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lan_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 8),
          Text(
            ip,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopButton extends StatefulWidget {
  final VoidCallback onTap;
  const _StopButton({required this.onTap});

  @override
  State<_StopButton> createState() => _StopButtonState();
}

class _StopButtonState extends State<_StopButton> {
  final FocusNode _node = FocusNode(debugLabel: 'remote-receive-stop');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node.requestFocus();
    });
    _node.addListener(_onFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = _node.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED1C24);
    return Focus(
      focusNode: _node,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: _focused ? Colors.white : accent.withValues(alpha: 0.55),
              width: _focused ? 2 : 1.2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop_rounded, size: 18, color: accent),
              SizedBox(width: 8),
              Text(
                'Stop receiving',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
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
