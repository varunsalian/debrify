import 'package:flutter/material.dart';

/// Terminal surface for a startup failure nothing else could route.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, this.detail});

  /// What failed, from the startup error describer; null only if the failure
  /// somehow produced no describable error.
  final String? detail;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark,
    darkTheme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Debrify could not start safely. Close the app and try again. '
                  'If this continues, restart the device before changing any data.',
                  textAlign: TextAlign.center,
                ),
                if (detail != null) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Please share this with support:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  // Selectable so a desktop reporter can paste it rather than
                  // retype a photographed stack frame.
                  SelectableText(
                    detail!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
