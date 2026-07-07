import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/tv_keys.dart';

/// One selectable provider in [showProviderPickerDialog].
class ProviderPickerOption {
  final String id;
  final String label;
  final List<Color> gradient;
  final IconData icon;
  const ProviderPickerOption({
    required this.id,
    required this.label,
    required this.gradient,
    required this.icon,
  });
}

/// The user's pick plus whether to persist it as the default provider.
class ProviderPickResult {
  final String provider;
  final bool remember;
  const ProviderPickResult(this.provider, this.remember);
}

/// The app's branded, DPAD-first provider picker — a dark card with per-provider
/// gradient icon chips, ordered focus traversal, autofocus on the first row, and
/// a "Remember my choice" toggle (mirrors Home's `_ProviderSelectionDialog`).
/// Returns the chosen provider + remember flag, or null if dismissed.
Future<ProviderPickResult?> showProviderPickerDialog(
  BuildContext context,
  List<ProviderPickerOption> options,
) {
  return showDialog<ProviderPickResult>(
    context: context,
    builder: (_) => _ProviderPickerDialog(options: options),
  );
}

class _ProviderPickerDialog extends StatefulWidget {
  final List<ProviderPickerOption> options;
  const _ProviderPickerDialog({required this.options});

  @override
  State<_ProviderPickerDialog> createState() => _ProviderPickerDialogState();
}

class _ProviderPickerDialogState extends State<_ProviderPickerDialog> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B0F1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 22, 22, 4),
                  child: Text(
                    'Choose provider',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                  child: Text(
                    'Where should we add this torrent?',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                    ),
                  ),
                ),
                for (var i = 0; i < widget.options.length; i++)
                  _ProviderRow(
                    option: widget.options[i],
                    autofocus: i == 0,
                    onTap: () => Navigator.of(context).pop(
                      ProviderPickResult(widget.options[i].id, _remember),
                    ),
                  ),
                const SizedBox(height: 6),
                _RememberRow(
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderRow extends StatefulWidget {
  final ProviderPickerOption option;
  final bool autofocus;
  final VoidCallback onTap;
  const _ProviderRow({
    required this.option,
    required this.autofocus,
    required this.onTap,
  });

  @override
  State<_ProviderRow> createState() => _ProviderRowState();
}

class _ProviderRowState extends State<_ProviderRow> {
  bool _focused = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!isActivateKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _focused
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused
                  ? widget.option.gradient.first.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.option.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.option.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.option.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: _focused ? 0.8 : 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RememberRow extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _RememberRow({required this.value, required this.onChanged});

  @override
  State<_RememberRow> createState() => _RememberRowState();
}

class _RememberRowState extends State<_RememberRow> {
  bool _focused = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!isActivateKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      widget.onChanged(!widget.value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                widget.value
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: widget.value
                    ? const Color(0xFF6366F1)
                    : Colors.white.withValues(alpha: 0.5),
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                'Remember my choice',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
