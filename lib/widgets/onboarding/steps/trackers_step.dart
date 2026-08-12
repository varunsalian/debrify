import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/widgets/parallax_focus.dart';
import '../controllers/tracker_auth_controller.dart';
import '../onboarding_focus.dart';
import '../onboarding_models.dart';
import '../onboarding_stage.dart';

class TrackersStep extends StatelessWidget {
  const TrackersStep({
    super.key,
    required this.layout,
    required this.focusController,
    required this.trakt,
    required this.simkl,
    required this.onDone,
  });

  final OnboardLayout layout;
  final OnboardFocusController focusController;
  final TrackerAuthController trakt;
  final TrackerAuthController simkl;
  final VoidCallback onDone;

  TrackerKind? get _active {
    for (final controller in <TrackerAuthController>[trakt, simkl]) {
      if (controller.phase == TrackerAuthPhase.code ||
          controller.phase == TrackerAuthPhase.starting) {
        return controller.kind;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _card(trakt, const OnboardCell(0, 0)),
      _card(simkl, const OnboardCell(0, 1)),
    ];
    if (layout == OnboardLayout.phone) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, index) => SizedBox(height: 210, child: cards[index]),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 14),
        Expanded(child: cards[1]),
      ],
    );
  }

  Widget _card(TrackerAuthController controller, OnboardCell cell) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[trakt, simkl]),
      builder: (context, _) {
        final active = _active;
        final enabled = active == null || active == controller.kind;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.42,
          child: OnboardFocusable(
            controller: focusController,
            cell: cell,
            enabled: enabled,
            onActivate: () => _activate(context, controller),
            radius: BorderRadius.circular(11),
            semanticLabel: controller.label,
            builder: (context, focused) => OnboardCardSurface(
              focused: focused,
              selected: controller.connected,
              padding: const EdgeInsets.all(18),
              child: _TrackerCardBody(controller: controller),
            ),
          ),
        );
      },
    );
  }

  Future<void> _activate(
    BuildContext context,
    TrackerAuthController controller,
  ) async {
    if (controller.phase == TrackerAuthPhase.code) {
      final url = controller.verificationUrl;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (controller.phase == TrackerAuthPhase.connected ||
        controller.phase == TrackerAuthPhase.resolving ||
        controller.phase == TrackerAuthPhase.starting) {
      return;
    }
    await controller.start();
  }

  Widget buildFooter(BuildContext context) {
    final connected = <String>[
      if (trakt.connected) 'Trakt',
      if (simkl.connected) 'Simkl',
    ];
    return Row(
      children: [
        Expanded(
          child: Text(
            connected.isEmpty
                ? 'Both optional'
                : '${connected.join(' and ')} connected',
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
          cell: const OnboardCell(1, 0),
          onActivate: onDone,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(18),
          builder: (context, focused) => OnboardPillSurface(
            focused: focused,
            label: connected.isEmpty ? 'Skip both' : 'Continue',
          ),
        ),
        const SizedBox(width: 10),
        OnboardFocusable(
          controller: focusController,
          cell: const OnboardCell(1, 1),
          onActivate: onDone,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(18),
          builder: (context, focused) => OnboardPillSurface(
            focused: focused,
            label: 'Done  ›',
            primary: true,
          ),
        ),
      ],
    );
  }
}

class _TrackerCardBody extends StatelessWidget {
  const _TrackerCardBody({required this.controller});

  final TrackerAuthController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isTrakt = controller.kind == TrackerKind.trakt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isTrakt ? const Color(0xFFED1C24) : const Color(0xFF0B0F14),
            borderRadius: BorderRadius.circular(12),
            border: isTrakt
                ? null
                : Border.all(color: scheme.onSurface.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Text(
              isTrakt ? 'T' : 'S',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          controller.label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        if (controller.phase == TrackerAuthPhase.code) ...[
          Text(
            controller.verificationUrl ?? 'Open the verification page',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              final code = controller.userCode;
              if (code != null) Clipboard.setData(ClipboardData(text: code));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                controller.userCode ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${controller.countdown} · press OK to open',
            style: TextStyle(
              fontSize: 9.5,
              color: scheme.onSurface.withValues(alpha: 0.42),
            ),
          ),
        ] else ...[
          Text(
            isTrakt
                ? 'Scrobbles what you watch and syncs your watchlist and progress.'
                : 'Syncs watch progress with strong anime coverage. Tokens do not expire.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.42,
              color: scheme.onSurface.withValues(alpha: 0.52),
            ),
          ),
          const Spacer(),
          _phaseLabel(context),
        ],
      ],
    );
  }

  Widget _phaseLabel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (controller.phase) {
      TrackerAuthPhase.resolving || TrackerAuthPhase.starting => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      TrackerAuthPhase.connected => Text(
        controller.username == null || controller.username!.isEmpty
            ? 'Connected'
            : 'Connected as ${controller.username}',
        style: const TextStyle(color: Color(0xFF34D399), fontSize: 10.5),
      ),
      TrackerAuthPhase.error => Text(
        controller.error ?? 'Try again',
        maxLines: 2,
        style: const TextStyle(color: Color(0xFFF87171), fontSize: 10),
      ),
      _ => Text(
        'Connect',
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    };
  }
}
