import 'package:flutter/material.dart';

import '../../../theme/widgets/parallax_focus.dart';
import '../onboarding_focus.dart';
import '../onboarding_stage.dart';

class ModeStep extends StatelessWidget {
  const ModeStep({
    super.key,
    required this.focusController,
    required this.onWebDavLogin,
    required this.onSetupHere,
    required this.onImport,
    this.onRestore,
    required this.onSkip,
    this.webDavError,
  });

  final OnboardFocusController focusController;
  final VoidCallback onWebDavLogin;
  final VoidCallback onSetupHere;
  final VoidCallback onImport;
  final VoidCallback? onRestore;
  final VoidCallback onSkip;
  final String? webDavError;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _ModeRow(
          controller: focusController,
          cell: const OnboardCell(0, 0),
          icon: Icons.login_rounded,
          title: 'Log in with WebDAV',
          subtitle:
              'Connect your sync account and pull your setup from your other devices.',
          onPressed: onWebDavLogin,
        ),
        if (webDavError case final error?) ...[
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        ],
        const SizedBox(height: 12),
        _ModeRow(
          controller: focusController,
          cell: const OnboardCell(1, 0),
          icon: Icons.tune_rounded,
          title: 'Set it up here',
          subtitle:
              'Connect your debrid service, pick search engines, and link a tracker.',
          onPressed: onSetupHere,
        ),
        const SizedBox(height: 12),
        _ModeRow(
          controller: focusController,
          cell: const OnboardCell(2, 0),
          icon: Icons.sync_alt_rounded,
          title: 'Bring it from another device',
          subtitle:
              'Copy services, addons, channels, and preferences from Debrify on another device.',
          footnote: 'Both devices need to be on the same Wi-Fi.',
          onPressed: onImport,
        ),
        if (onRestore != null) ...[
          const SizedBox(height: 12),
          _ModeRow(
            controller: focusController,
            cell: const OnboardCell(3, 0),
            icon: Icons.restore_rounded,
            title: 'Restore from a backup',
            subtitle:
                'Choose a Debrify backup file to restore profiles, services, addons, channels, and preferences.',
            onPressed: onRestore!,
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OnboardFocusable(
            controller: focusController,
            cell: OnboardCell(onRestore == null ? 3 : 4, 0),
            onActivate: onSkip,
            shape: ParallaxShape.pill,
            radius: BorderRadius.circular(18),
            semanticLabel: "Skip — I'll do this later",
            builder: (context, focused) => OnboardPillSurface(
              focused: focused,
              label: "Skip — I'll do this later",
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.controller,
    required this.cell,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.footnote,
  });

  final OnboardFocusController controller;
  final OnboardCell cell;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? footnote;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OnboardFocusable(
      controller: controller,
      cell: cell,
      onActivate: onPressed,
      radius: BorderRadius.circular(11),
      semanticLabel: title,
      builder: (context, focused) => OnboardCardSurface(
        focused: focused,
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 17),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: scheme.onSurface.withValues(alpha: 0.1),
              ),
              child: Icon(icon, color: scheme.onSurface),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.42,
                      color: scheme.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                  if (footnote != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      footnote!,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurface.withValues(alpha: focused ? 0.8 : 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
