import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _EnsureVisibleOnFocus extends StatelessWidget {
  const _EnsureVisibleOnFocus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) {
      if (!focused) return;
      Scrollable.ensureVisible(
        context,
        alignment: .35,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    },
    child: child,
  );
}

/// Gives a read-only TV row a real DPAD stop. Flutter removes disabled
/// ListTiles from focus traversal, which used to leave the active Admin's
/// Access page with no way to advance (and therefore no way to scroll).
class _TvReadOnlyScrollAnchor extends StatefulWidget {
  const _TvReadOnlyScrollAnchor({super.key, required this.child});

  final Widget child;

  @override
  State<_TvReadOnlyScrollAnchor> createState() =>
      _TvReadOnlyScrollAnchorState();
}

class _TvReadOnlyScrollAnchorState extends State<_TvReadOnlyScrollAnchor> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: .5,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, event) {
        if (isActivateOrSpaceKey(event.logicalKey)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? colors.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _TvActionSurface extends StatefulWidget {
  const _TvActionSurface({
    super.key,
    required this.child,
    required this.onPressed,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.onKeyEvent,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  @override
  State<_TvActionSurface> createState() => _TvActionSurfaceState();
}

class _TvActionSurfaceState extends State<_TvActionSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = _focused || widget.selected;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        final result = widget.onKeyEvent?.call(node, event);
        if (result != null && result != KeyEventResult.ignored) return result;
        if (isActivateOrSpaceKey(event.logicalKey)) {
          if (event is KeyDownEvent) widget.onPressed?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: _focused ? 1.025 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: active
                ? colors.primary.withValues(alpha: widget.selected ? .15 : .1)
                : colors.surfaceContainerHighest.withValues(alpha: .55),
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            border: Border.all(
              color: active ? colors.primary : Colors.transparent,
              width: _focused ? 3 : 2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: .28),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            focusNode: widget.focusNode,
            onFocusChange: (focused) {
              if (_focused != focused) setState(() => _focused = focused);
              if (focused) {
                Scrollable.ensureVisible(
                  context,
                  alignment: .35,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            onTap: widget.onPressed,
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            child: IconTheme.merge(
              data: IconThemeData(color: active ? colors.primary : null),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: active ? colors.primary : null),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Left/right remain pane navigation; OK opens the value picker.
class _TvAutoLockField extends StatelessWidget {
  const _TvAutoLockField({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;
  static const _labels = <int, String>{
    0: 'Never',
    5: 'After 5 minutes',
    15: 'After 15 minutes',
    30: 'After 30 minutes',
    60: 'After 1 hour',
  };

  @override
  Widget build(BuildContext context) => _TvActionSurface(
    key: const ValueKey('tv-profile-auto-lock'),
    onPressed: () async {
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => TvHeldKeyGuard(
          child: SimpleDialog(
            title: const Text('Auto-lock'),
            children: [
              for (final entry in _labels.entries)
                ListTile(
                  autofocus: entry.key == value,
                  selected: entry.key == value,
                  title: Text(entry.value),
                  trailing: entry.key == value ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, entry.key),
                ),
            ],
          ),
        ),
      );
      if (selected != null && context.mounted) onChanged(selected);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-lock',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _labels[value] ?? _labels[0]!,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Icon(Icons.expand_more_rounded, size: 30),
        ],
      ),
    ),
  );
}

typedef EditProfileEnsureVisibleOnFocus = _EnsureVisibleOnFocus;

typedef EditProfileTvReadOnlyScrollAnchor = _TvReadOnlyScrollAnchor;

typedef EditProfileTvActionSurface = _TvActionSurface;

typedef EditProfileTvAutoLockField = _TvAutoLockField;
Widget editProfileEnsureVisibleOnFocus({Key? key, required Widget child}) =>
    EditProfileEnsureVisibleOnFocus(key: key, child: child);
Widget editProfileTvReadOnlyScrollAnchor({Key? key, required Widget child}) =>
    EditProfileTvReadOnlyScrollAnchor(key: key, child: child);
Widget editProfileTvActionSurface({
  Key? key,
  required Widget child,
  required VoidCallback? onPressed,
  bool selected = false,
  bool autofocus = false,
  FocusNode? focusNode,
  KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent,
}) => EditProfileTvActionSurface(
  key: key,
  child: child,
  onPressed: onPressed,
  selected: selected,
  autofocus: autofocus,
  focusNode: focusNode,
  onKeyEvent: onKeyEvent,
);
