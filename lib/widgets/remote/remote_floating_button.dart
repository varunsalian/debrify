import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/remote_control/remote_control_state.dart';

/// Floating action button for remote control that appears when TV is detected
class RemoteFloatingButton extends StatefulWidget {
  final VoidCallback onTap;

  const RemoteFloatingButton({
    super.key,
    required this.onTap,
  });

  @override
  State<RemoteFloatingButton> createState() => _RemoteFloatingButtonState();
}

class _RemoteFloatingButtonState extends State<RemoteFloatingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Listen to state changes
    RemoteControlState().addListener(_onStateChanged);
    _updatePulseAnimation();
  }

  @override
  void dispose() {
    RemoteControlState().removeListener(_onStateChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
      _updatePulseAnimation();
    }
  }

  void _updatePulseAnimation() {
    final state = RemoteControlState();
    if (state.isScanning) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = RemoteControlState();

    // Gradient colors based on connection state
    final List<Color> gradientColors = state.isConnected
        ? const [Color(0xFF10B981), Color(0xFF059669)] // Green for connected
        : const [Color(0xFF6366F1), Color(0xFF8B5CF6)]; // Purple for scanning

    // Icon based on state
    final IconData icon = state.isConnected
        ? Icons.tv
        : Icons.cast_connected;

    return Positioned(
      bottom: 80, // Above MobileFloatingNav
      right: 16,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final scale = state.isScanning ? _pulseAnimation.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            widget.onTap();
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: gradientColors[0].withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: gradientColors[1].withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
