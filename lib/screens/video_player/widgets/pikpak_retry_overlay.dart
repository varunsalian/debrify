import 'package:flutter/material.dart';

/// Non-blocking retry indicator overlay for PikPak cold storage reactivation
///
/// Displays a semi-transparent indicator at the bottom-right showing
/// retry progress when PikPak videos need to be reactivated from cold storage.
class PikPakRetryOverlay extends StatelessWidget {
  /// Message to display (e.g., "Reactivating video... (1/5)")
  final String message;

  const PikPakRetryOverlay({
    Key? key,
    required this.message,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80,
      right: 20,
      child: IgnorePointer(
        ignoring: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
