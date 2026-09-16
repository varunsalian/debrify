import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum RandomPlaybackMode { once, continuous }

Future<RandomPlaybackMode?> showRandomPlaybackDialog(
  BuildContext context, {
  required String title,
}) => showDialog<RandomPlaybackMode>(
  context: context,
  builder: (_) => RandomPlaybackDialog(title: title),
);

/// A bounded, scrollable choice dialog shared by touch and remote surfaces.
class RandomPlaybackDialog extends StatelessWidget {
  const RandomPlaybackDialog({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: AlertDialog(
        title: const Text('Random playback'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 20),
              _choice(
                context,
                mode: RandomPlaybackMode.once,
                icon: Icons.shuffle_rounded,
                label: 'Play random once',
                description:
                    'Start one random episode. Playback continues normally after it.',
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _choice(
                context,
                mode: RandomPlaybackMode.continuous,
                icon: Icons.repeat_rounded,
                label: 'Continuous shuffle',
                description:
                    'Start a random episode and keep choosing randomly across this series.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _choice(
    BuildContext context, {
    required RandomPlaybackMode mode,
    required IconData icon,
    required String label,
    required String description,
    bool autofocus = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton(
      autofocus: autofocus,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(16)),
        alignment: Alignment.centerLeft,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? colors.primary
                : colors.outlineVariant,
            width: states.contains(WidgetState.focused) ? 3 : 1,
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? colors.primaryContainer
              : colors.surface,
        ),
        foregroundColor: WidgetStatePropertyAll(colors.onSurface),
      ),
      onPressed: () => Navigator.of(context).pop(mode),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
