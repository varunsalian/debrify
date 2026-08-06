import 'package:flutter/material.dart';

import '../utils/dialog_tap_guard.dart';

/// Shared confirmation used whenever a provider can queue a torrent that is
/// not immediately available for playback.
Future<bool> showNotCachedDialog(
  BuildContext context,
  String providerLabel,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  color: Color(0xFFF59E0B),
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Torrent Not Cached',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This torrent is not cached on $providerLabel. Would you like '
                'to add it anyway?\n\nOnce downloaded, it will be available '
                'in the $providerLabel page.',
                style: Theme.of(
                  ctx,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        DialogTapGuard.markKeyAction();
                        Navigator.of(ctx).pop(false);
                      },
                      style: ButtonStyle(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(vertical: 12),
                        ),
                        shape: WidgetStateProperty.resolveWith((states) {
                          final focused = states.contains(WidgetState.focused);
                          return RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: focused ? Colors.white : Colors.white24,
                              width: focused ? 2 : 1,
                            ),
                          );
                        }),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      autofocus: true,
                      onPressed: () {
                        DialogTapGuard.markKeyAction();
                        Navigator.of(ctx).pop(true);
                      },
                      style: ButtonStyle(
                        backgroundColor: const WidgetStatePropertyAll(
                          Color(0xFF6366F1),
                        ),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(vertical: 12),
                        ),
                        shape: WidgetStateProperty.resolveWith((states) {
                          final focused = states.contains(WidgetState.focused);
                          return RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: focused
                                ? const BorderSide(
                                    color: Colors.white,
                                    width: 2,
                                  )
                                : BorderSide.none,
                          );
                        }),
                      ),
                      child: const Text(
                        'Add Anyway',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}
