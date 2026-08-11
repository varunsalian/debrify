import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/storage_service.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';

/// Warns that Debrify TV is about to hand the stream to another app, and what
/// that costs: one title, then it's over.
///
/// Shown before every external launch until the user ticks "Don't show this
/// again" — the trade-off is a property of external playback, not of a
/// particular channel, so one dismissal covers all of Debrify TV.
///
/// Fully D-pad driven: every element is focusable, Continue takes first focus,
/// and BACK cancels (the safe outcome — nothing has launched yet).
class ExternalPlayerNoticeDialog extends StatefulWidget {
  const ExternalPlayerNoticeDialog({super.key});

  /// Returns true when playback should proceed to the external player.
  ///
  /// Returns true immediately — without showing anything — once the notice has
  /// been dismissed forever.
  static Future<bool> confirm(BuildContext context) async {
    if (await StorageService.getDebrifyTvExternalNoticeDismissed()) {
      return true;
    }
    if (!context.mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ExternalPlayerNoticeDialog(),
    );
    return proceed ?? false;
  }

  @override
  State<ExternalPlayerNoticeDialog> createState() =>
      _ExternalPlayerNoticeDialogState();
}

class _ExternalPlayerNoticeDialogState
    extends State<ExternalPlayerNoticeDialog> {
  bool _dontShowAgain = false;

  Future<void> _proceed() async {
    if (_dontShowAgain) {
      await StorageService.setDebrifyTvExternalNoticeDismissed(true);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return FocusTraversalGroup(
      child: FocusScope(
        autofocus: true,
        child: AlertDialog(
          backgroundColor: tv.noticeBg,
          shape: RoundedRectangleBorder(
            borderRadius: app.shape.br(20),
            // Not `hairline`: this is composed at 0.1 exactly, and the
            // hairline is 31/255. Ink at alpha, so it follows the ink.
            side: BorderSide(color: app.core.tx.withValues(alpha: 0.1)),
          ),
          title: Row(
            children: [
              Icon(Icons.open_in_new, color: tv.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Opening in your external player',
                  style: TextStyle(color: app.core.tx, fontSize: 20),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your default player is set to an external app, so Debrify '
                  'TV will hand this one title over and stop there.',
                  style: TextStyle(color: tv.textDim, height: 1.4),
                ),
                const SizedBox(height: 12),
                const _NoticeLine("The channel won't roll on to the next title"),
                const _NoticeLine('Channel switching is unavailable'),
                const _NoticeLine('Playback starts at the beginning, not at a '
                    'random point'),
                const _NoticeLine('Watch progress is not recorded'),
                const SizedBox(height: 14),
                Text(
                  'Change this under Settings → External Player → Default '
                  'player.',
                  style: TextStyle(
                    color: app.core.tx.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                _DontShowAgainRow(
                  value: _dontShowAgain,
                  onChanged: (value) =>
                      setState(() => _dontShowAgain = value),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            _DialogButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            _DialogButton(
              label: 'Continue',
              primary: true,
              autofocus: true,
              onPressed: _proceed,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeLine extends StatelessWidget {
  final String text;

  const _NoticeLine(this.text);

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 8),
            // `Colors.white38` = 98/255 — between `textFaint` (138) and the
            // surface's fills, so it takes the ink at its own alpha.
            child: Icon(
              Icons.remove,
              size: 14,
              color: app.core.tx.withAlpha(98),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: app.debrifyTv.textMeta, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Focusable checkbox row — a plain [CheckboxListTile] would be reachable by
/// D-pad but gives no focus cue on a 10-foot screen.
class _DontShowAgainRow extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DontShowAgainRow({required this.value, required this.onChanged});

  @override
  State<_DontShowAgainRow> createState() => _DontShowAgainRowState();
}

class _DontShowAgainRowState extends State<_DontShowAgainRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    // LEFT LITERAL: the resting ground 0xFF141418 has no token — `controlBg`
    // is 0xFF141414, four steps off, and a near-miss is exactly what must not
    // be substituted. Needs its own role before this row can follow a light
    // theme. Hoisted so the label below can be scored against whichever of the
    // two grounds is actually painted.
    final Color background =
        _isFocused ? tv.cardFocusBg : tv.controlResting;
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            isActivateOrSpaceKey(event.logicalKey)) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        child: AnimatedContainer(
          // TV: snap — see SwitchRow.
          duration: PlatformUtil.isTelevision
              ? Duration.zero
              : const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: app.shape.br(12),
            border: Border.all(
              color: _isFocused ? tv.focusRing : tv.hairline,
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.value
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                color: widget.value ? tv.accent : tv.textFaint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Don't show this again",
                  // Ink on a filled swatch, scored against that swatch — the
                  // same rule `_DialogButton` runs. Page ink was wrong here:
                  // the resting ground stays a pinned dark literal on every
                  // theme, so a paper theme's near-black label vanished into
                  // it. Both grounds clear white by a wide margin under
                  // legacy (18.4:1 and 14.0:1), so today's pixel is unchanged.
                  style: TextStyle(color: app.inkOn(background)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;

  const _DialogButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
  });

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    // LEFT LITERAL: the secondary ground 0xFF2A2A2E has no token —
    // `cardFocusBg` is 0xFF2A2A2A, four steps off.
    final Color background =
        widget.primary ? app.debrifyTv.accent : const Color(0xFF2A2A2E);

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            isActivateOrSpaceKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: PlatformUtil.isTelevision
              ? Duration.zero
              : const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: app.shape.br(12),
            border: Border.all(
              color: _isFocused
                  ? app.debrifyTv.focusRing
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              // Ink on a filled swatch, scored against that swatch.
              color: app.inkOn(background),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
