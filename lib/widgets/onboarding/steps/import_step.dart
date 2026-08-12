import 'package:flutter/material.dart';

import '../../../theme/widgets/parallax_focus.dart';
import '../onboarding_focus.dart';
import '../onboarding_models.dart';
import '../onboarding_stage.dart';

class ImportStep extends StatelessWidget {
  const ImportStep({
    super.key,
    required this.layout,
    required this.focusController,
    required this.deviceName,
    required this.connected,
    required this.connectionDropped,
    required this.receivedCount,
    required this.transferComplete,
    required this.onSetupHere,
    this.lastReceived,
    this.startError,
  });

  final OnboardLayout layout;
  final OnboardFocusController focusController;
  final String deviceName;
  final bool connected;
  final bool connectionDropped;
  final int receivedCount;
  final String? lastReceived;
  final bool transferComplete;
  final String? startError;
  final VoidCallback onSetupHere;

  @override
  Widget build(BuildContext context) {
    final checklist = const _ImportChecklist();
    final panel = _ImportLivePanel(
      deviceName: deviceName,
      connected: connected,
      connectionDropped: connectionDropped,
      receivedCount: receivedCount,
      lastReceived: lastReceived,
      transferComplete: transferComplete,
      startError: startError,
    );
    if (layout == OnboardLayout.phone) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [checklist, const SizedBox(height: 14), panel],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: checklist),
        const SizedBox(width: 22),
        Expanded(flex: 6, child: panel),
      ],
    );
  }

  Widget buildFooter(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            transferComplete
                ? 'Transfer received'
                : connected
                ? 'Receiving from your phone…'
                : 'Waiting for the transfer…',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
        OnboardFocusable(
          controller: focusController,
          cell: const OnboardCell(0, 0),
          onActivate: onSetupHere,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(18),
          builder: (context, focused) => OnboardPillSurface(
            focused: focused,
            label: 'Set up here instead',
          ),
        ),
      ],
    );
  }
}

class _ImportChecklist extends StatelessWidget {
  const _ImportChecklist();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ChecklistRow(
          number: '1',
          title: 'Open Remote on the phone',
          subtitle: 'Menu › Remote, near the bottom of the list.',
        ),
        _ChecklistRow(
          number: '2',
          title: 'Choose Send',
          subtitle: 'The phone becomes the sender.',
        ),
        _ChecklistRow(
          number: '3',
          title: 'Pick this device and transfer everything',
          subtitle: 'This screen finishes when the complete signal arrives.',
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.onSurface.withValues(alpha: 0.1),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.4,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportLivePanel extends StatelessWidget {
  const _ImportLivePanel({
    required this.deviceName,
    required this.connected,
    required this.connectionDropped,
    required this.receivedCount,
    required this.lastReceived,
    required this.transferComplete,
    required this.startError,
  });

  final String deviceName;
  final bool connected;
  final bool connectionDropped;
  final int receivedCount;
  final String? lastReceived;
  final bool transferComplete;
  final String? startError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dropped = connectionDropped && !connected && !transferComplete;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THIS DEVICE',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 10,
              letterSpacing: 2,
              color: scheme.onSurface.withValues(alpha: 0.44),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            deviceName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ConnectionPill(
            label: transferComplete
                ? 'Transfer complete'
                : connected
                ? 'Phone connected'
                : 'Waiting for a phone',
            good: connected || transferComplete,
          ),
          const SizedBox(height: 16),
          if (startError != null)
            Text(
              startError!,
              style: const TextStyle(color: Color(0xFFF87171), fontSize: 10.5),
            )
          else if (dropped)
            const Text(
              'Connection dropped. Keep this screen open—the transfer resumes when the phone reconnects.',
              style: TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 10.5,
                height: 1.4,
              ),
            )
          else ...[
            Text(
              '$receivedCount ${receivedCount == 1 ? 'item' : 'items'} received',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (lastReceived != null) ...[
              const SizedBox(height: 5),
              Text(
                'Last received: $lastReceived',
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
            ],
            if (receivedCount > 0 && !transferComplete) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
              const SizedBox(height: 7),
              Text(
                'Applying…',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.label, required this.good});

  final String label;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good
        ? const Color(0xFF34D399)
        : Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10.5)),
        ],
      ),
    );
  }
}
