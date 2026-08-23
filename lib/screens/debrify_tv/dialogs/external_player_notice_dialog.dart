import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/storage_service.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';
import 'spotlight_dialog.dart';

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
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: FocusScope(
        autofocus: true,
        child: DebrifyTvSpotlightDialog(
          eyebrow: 'External playback',
          title: 'Opening another player',
          subtitle:
              'Debrify TV will hand this title to your default external app and stop here.',
          icon: Icons.open_in_new_rounded,
          maxWidth: 620,
          actions: [
            DebrifyTvDialogButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            DebrifyTvDialogButton(
              label: 'Continue',
              icon: Icons.open_in_new_rounded,
              tone: DebrifyTvDialogButtonTone.primary,
              autofocus: true,
              onPressed: _proceed,
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _NoticeLine("The channel won't roll on to the next title"),
              const _NoticeLine('Channel switching is unavailable'),
              const _NoticeLine(
                'Playback starts at the beginning, not at a random point',
              ),
              const _NoticeLine('Watch progress is not recorded'),
              const SizedBox(height: 12),
              _DontShowAgainRow(
                value: _dontShowAgain,
                onChanged: (value) => setState(() => _dontShowAgain = value),
              ),
            ],
          ),
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
    final Color background = _isFocused ? app.core.tx : tv.fillWeak;
    final Color ink = _isFocused ? app.inkOn(app.core.tx) : app.core.tx;
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowUp) {
            node.previousFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowDown) {
            node.nextFocus();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && isActivateOrSpaceKey(key)) {
            widget.onChanged(!widget.value);
            return KeyEventResult.handled;
          }
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
            border: Border.all(color: _isFocused ? app.core.tx : tv.hairline),
          ),
          child: Row(
            children: [
              Icon(
                widget.value ? Icons.check_box : Icons.check_box_outline_blank,
                color: _isFocused
                    ? ink
                    : widget.value
                    ? tv.accent
                    : tv.textFaint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Don't show this again",
                  style: TextStyle(color: ink, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
