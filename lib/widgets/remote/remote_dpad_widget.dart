import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/remote_control/remote_constants.dart';
import '../../services/remote_control/remote_control_state.dart';

/// Circular DPAD widget with up/down/left/right arrows and center select button
class RemoteDpadWidget extends StatelessWidget {
  final double size;

  const RemoteDpadWidget({
    super.key,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    final buttonSize = size * 0.28;
    final centerSize = size * 0.32;
    final offset = size * 0.32;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1E293B).withValues(alpha: 0.8),
                  const Color(0xFF0F172A).withValues(alpha: 0.9),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),

          // Up button
          Positioned(
            top: (size - buttonSize) / 2 - offset,
            child: _DpadButton(
              icon: Icons.keyboard_arrow_up,
              size: buttonSize,
              onPressed: () => _sendCommand(NavigateCommand.up),
            ),
          ),

          // Down button
          Positioned(
            bottom: (size - buttonSize) / 2 - offset,
            child: _DpadButton(
              icon: Icons.keyboard_arrow_down,
              size: buttonSize,
              onPressed: () => _sendCommand(NavigateCommand.down),
            ),
          ),

          // Left button
          Positioned(
            left: (size - buttonSize) / 2 - offset,
            child: _DpadButton(
              icon: Icons.keyboard_arrow_left,
              size: buttonSize,
              onPressed: () => _sendCommand(NavigateCommand.left),
            ),
          ),

          // Right button
          Positioned(
            right: (size - buttonSize) / 2 - offset,
            child: _DpadButton(
              icon: Icons.keyboard_arrow_right,
              size: buttonSize,
              onPressed: () => _sendCommand(NavigateCommand.right),
            ),
          ),

          // Center select button
          _DpadCenterButton(
            size: centerSize,
            onPressed: () => _sendCommand(NavigateCommand.select),
          ),
        ],
      ),
    );
  }

  void _sendCommand(String command) {
    RemoteControlState().sendNavigateCommand(command);
  }
}

class _DpadButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  const _DpadButton({
    required this.icon,
    required this.size,
    required this.onPressed,
  });

  @override
  State<_DpadButton> createState() => _DpadButtonState();
}

class _DpadButtonState extends State<_DpadButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        HapticFeedback.lightImpact();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isPressed
                  ? [
                      const Color(0xFF6366F1),
                      const Color(0xFF8B5CF6),
                    ]
                  : [
                      const Color(0xFF334155),
                      const Color(0xFF1E293B),
                    ],
            ),
            border: Border.all(
              color: _isPressed
                  ? const Color(0xFF6366F1)
                  : Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: _isPressed
                ? [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            widget.icon,
            color: Colors.white,
            size: widget.size * 0.6,
          ),
        ),
      ),
    );
  }
}

class _DpadCenterButton extends StatefulWidget {
  final double size;
  final VoidCallback onPressed;

  const _DpadCenterButton({
    required this.size,
    required this.onPressed,
  });

  @override
  State<_DpadCenterButton> createState() => _DpadCenterButtonState();
}

class _DpadCenterButtonState extends State<_DpadCenterButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        HapticFeedback.mediumImpact();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isPressed
                  ? [
                      const Color(0xFF10B981),
                      const Color(0xFF059669),
                    ]
                  : [
                      const Color(0xFF6366F1),
                      const Color(0xFF8B5CF6),
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: (_isPressed
                        ? const Color(0xFF10B981)
                        : const Color(0xFF6366F1))
                    .withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'OK',
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.size * 0.3,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
