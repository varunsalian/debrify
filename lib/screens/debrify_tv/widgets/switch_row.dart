import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A switch row widget with Android TV focus support.
///
/// Displays a switch with title and subtitle, supporting D-pad navigation
/// and activation via select/enter/space keys.
class SwitchRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<SwitchRow> createState() => _SwitchRowState();
}

class _SwitchRowState extends State<SwitchRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onChanged(!widget.value);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _isFocused ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isFocused ? Colors.white : Colors.white12,
            width: _isFocused ? 2 : 1,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: SwitchListTile(
          title: Text(
            widget.title,
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            widget.subtitle,
            style: const TextStyle(color: Colors.white70),
          ),
          value: widget.value,
          onChanged: widget.onChanged,
          activeColor: const Color(0xFFE50914),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
        ),
      ),
    );
  }
}
