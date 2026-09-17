import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An opaque shield: rejected provider videos must never show through it.
class PlaybackStartupView extends StatelessWidget {
  const PlaybackStartupView({
    super.key,
    required this.title,
    required this.details,
    required this.retrying,
    this.episode,
    this.onBack,
  });
  final String title;
  final String details;
  final bool retrying;
  final String? episode;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    // Handle these below the player's root Focus, which otherwise consumes
    // remote keys while playback is not ready.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): PreviousFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: FocusTraversalGroup(
        child: Material(
          color: const Color(0xff080c12),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(.6, -.5),
                radius: 1.4,
                colors: [Color(0xff233539), Color(0xff080c12)],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, size) {
                  final compact = size.maxHeight < 400 || size.maxWidth < 600;
                  return Padding(
                    padding: EdgeInsets.all(compact ? 16 : 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (onBack != null)
                          IconButton.filledTonal(
                            key: const ValueKey('startup-source-back'),
                            tooltip: 'Back',
                            autofocus: true,
                            onPressed: onBack,
                            icon: const Icon(Icons.arrow_back),
                          ),
                        Expanded(
                          child: LayoutBuilder(
                            // Keep the controls pinned. The content fills roomy
                            // screens but can scroll at large text scales or
                            // in short windows without shrinking readable text.
                            builder: (context, bodySize) => SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: bodySize.maxHeight,
                                ),
                                child: IntrinsicHeight(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          child: Center(
                                            child: TweenAnimationBuilder<double>(
                                              tween: Tween(begin: 0, end: 1),
                                              duration: Duration(
                                                milliseconds: reduced ? 0 : 650,
                                              ),
                                              builder:
                                                  (
                                                    context,
                                                    value,
                                                    child,
                                                  ) => Opacity(
                                                    opacity: value,
                                                    child: Transform.translate(
                                                      offset: Offset(
                                                        0,
                                                        12 * (1 - value),
                                                      ),
                                                      child: child,
                                                    ),
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    title,
                                                    textAlign: TextAlign.center,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: compact
                                                          ? 26
                                                          : 42,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      letterSpacing: -1,
                                                    ),
                                                  ),
                                                  if (episode != null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 12,
                                                          ),
                                                      child: Text(
                                                        episode!,
                                                        style: const TextStyle(
                                                          color: Colors.white60,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      AnimatedSwitcher(
                                        duration: Duration(
                                          milliseconds: reduced ? 0 : 250,
                                        ),
                                        child: Text(
                                          retrying
                                              ? 'CONNECTING TO ANOTHER SOURCE'
                                              : 'OPENING YOUR STREAM',
                                          key: ValueKey(retrying),
                                          style: const TextStyle(
                                            color: Color(0xff80d4bc),
                                            fontSize: 11,
                                            letterSpacing: 2,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        retrying
                                            ? 'The previous source couldn’t start. Trying an alternative.'
                                            : 'Connecting and waiting for the first frames.',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: 240,
                                        child: LinearProgressIndicator(
                                          value: reduced ? 0.5 : null,
                                          minHeight: 2,
                                          color: const Color(0xff80d4bc),
                                          backgroundColor: Colors.white12,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          autofocus: onBack == null,
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              scrollable: true,
                              title: const Text('Playback details'),
                              content: Text(details),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                          child: const Text('Playback details'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
