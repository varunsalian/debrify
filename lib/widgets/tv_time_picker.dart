import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A DPAD-operable replacement for Material's [showTimePicker].
///
/// The Material picker is unusable with a remote: in dial mode the dial isn't
/// focusable (nothing changes the value), and its `input` mode is raw
/// [TextField]s — the exact path Flutter engine bug #177360 breaks on TV IMEs,
/// which is why the app renders its own keyboard everywhere else.
///
/// So this is a spinner instead: LEFT/RIGHT walks the fields (hour, minute,
/// AM/PM where the locale uses it, then Cancel and Set), UP/DOWN changes the
/// selected value, OK on any value field sets the time, and Back cancels via
/// the usual dialog pop. Every field wraps, so any value is a few presses away.
/// Chevrons and buttons stay tappable for air-mouse remotes.
Future<TimeOfDay?> showTvTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => _TvTimePickerDialog(
      initialTime: initialTime,
      helpText: helpText,
    ),
  );
}

enum _Slot { hour, minute, period, cancel, ok }

class _TvTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  final String? helpText;

  const _TvTimePickerDialog({required this.initialTime, this.helpText});

  @override
  State<_TvTimePickerDialog> createState() => _TvTimePickerDialogState();
}

class _TvTimePickerDialogState extends State<_TvTimePickerDialog> {
  late int _hour = widget.initialTime.hour;
  late int _minute = widget.initialTime.minute;
  int _index = 0;
  bool _use24 = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final format = MaterialLocalizations.of(context).timeOfDayFormat(
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    final use24 = hourFormat(of: format) != HourFormat.h;
    if (use24 == _use24) return;
    _use24 = use24;
    // The period field appears/disappears with the format — keep the selection
    // on a slot that still exists.
    _index = _index.clamp(0, _slots.length - 1);
  }

  List<_Slot> get _slots => [
    _Slot.hour,
    _Slot.minute,
    if (!_use24) _Slot.period,
    _Slot.cancel,
    _Slot.ok,
  ];

  _Slot get _slot => _slots[_index];

  void _move(int delta) {
    final slots = _slots;
    setState(() => _index = (_index + delta) % slots.length);
  }

  /// UP/DOWN on a value field. Every field wraps; in 12-hour mode the hour
  /// wraps 12→1 without flipping the period, which is what a separate AM/PM
  /// field is for.
  void _adjust(int delta) {
    setState(() {
      switch (_slot) {
        case _Slot.hour:
          if (_use24) {
            _hour = (_hour + delta) % 24;
          } else {
            final isPm = _hour >= 12;
            final h12 = (_hour % 12 + delta) % 12;
            _hour = (isPm ? 12 : 0) + h12;
          }
        case _Slot.minute:
          _minute = (_minute + delta) % 60;
        case _Slot.period:
          _hour = (_hour + 12) % 24;
        case _Slot.cancel:
        case _Slot.ok:
          break;
      }
    });
  }

  void _activate() {
    if (_slot == _Slot.cancel) {
      Navigator.of(context).pop();
      return;
    }
    // OK anywhere else commits — on a value field it's the fast path, so the
    // common case is: spin the numbers, press OK.
    Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: _minute));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // Repeats included: holding UP is how you cross 40 minutes.
    if (key == LogicalKeyboardKey.arrowUp) {
      _adjust(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _adjust(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    // Activation only on the initial press — a held OK must not fire twice.
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.gameButtonA)) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _hourLabel {
    if (_use24) return _hour.toString().padLeft(2, '0');
    final h = _hour % 12;
    return (h == 0 ? 12 : h).toString();
  }

  String get _periodLabel {
    final l10n = MaterialLocalizations.of(context);
    return _hour < 12
        ? l10n.anteMeridiemAbbreviation
        : l10n.postMeridiemAbbreviation;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.helpText ?? 'Pick a time'),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _field(_Slot.hour, _hourLabel),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    ':',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                _field(_Slot.minute, _minute.toString().padLeft(2, '0')),
                if (!_use24) ...[
                  const SizedBox(width: 8),
                  _field(_Slot.period, _periodLabel),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Up/Down changes · Left/Right moves',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
      actions: [
        _action(_Slot.cancel, 'Cancel'),
        _action(_Slot.ok, 'Set'),
      ],
    );
  }

  Widget _field(_Slot slot, String label) {
    final theme = Theme.of(context);
    final selected = _slot == slot;
    final accent = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    return GestureDetector(
      onTap: () => setState(() => _index = _slots.indexOf(slot)),
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.16)
              : onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : onSurface.withValues(alpha: 0.14),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chevron(slot, Icons.keyboard_arrow_up_rounded, 1, selected),
            Text(
              label,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: onSurface,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            _chevron(slot, Icons.keyboard_arrow_down_rounded, -1, selected),
          ],
        ),
      ),
    );
  }

  Widget _chevron(_Slot slot, IconData icon, int delta, bool selected) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        setState(() => _index = _slots.indexOf(slot));
        _adjust(delta);
      },
      child: Icon(
        icon,
        size: 20,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _action(_Slot slot, String label) {
    final theme = Theme.of(context);
    final selected = _slot == slot;
    return TextButton(
      // Selection is driven by [_index], not real focus — the dialog keeps a
      // single focus node so arrows never traverse away from the spinner.
      onPressed: () {
        setState(() => _index = _slots.indexOf(slot));
        _activate();
      },
      style: TextButton.styleFrom(
        side: selected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
      child: Text(label),
    );
  }
}
