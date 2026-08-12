import 'package:flutter/material.dart';

import '../../../services/engine/remote_engine_manager.dart';
import '../../../theme/widgets/parallax_focus.dart';
import '../onboarding_focus.dart';
import '../onboarding_models.dart';
import '../onboarding_stage.dart';

class EnginesStep extends StatelessWidget {
  const EnginesStep({
    super.key,
    required this.layout,
    required this.focusController,
    required this.engines,
    required this.selected,
    required this.loading,
    required this.importing,
    required this.onToggle,
    required this.onTurnAllOff,
    required this.onContinue,
    required this.onSkip,
    required this.onRetry,
    this.error,
  });

  final OnboardLayout layout;
  final OnboardFocusController focusController;
  final List<RemoteEngineInfo> engines;
  final Set<String> selected;
  final bool loading;
  final bool importing;
  final String? error;
  final ValueChanged<String> onToggle;
  final VoidCallback onTurnAllOff;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onRetry;

  int get columns => switch (layout) {
    OnboardLayout.phone => 1,
    OnboardLayout.tablet => 2,
    OnboardLayout.stage => 4,
  };

  int get footerRow => (engines.length / columns).ceil();

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'The search-engine catalogue could not be loaded.\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (engines.isEmpty) {
      return const Center(
        child: Text('No search engines are available right now.'),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 11,
        mainAxisSpacing: 11,
        childAspectRatio: layout == OnboardLayout.phone ? 2.7 : 1.45,
      ),
      itemCount: engines.length,
      itemBuilder: (context, index) {
        final engine = engines[index];
        final isSelected = selected.contains(engine.id);
        return OnboardFocusable(
          key: ValueKey(engine.id),
          controller: focusController,
          cell: OnboardCell(index ~/ columns, index % columns),
          onActivate: () => onToggle(engine.id),
          enabled: !importing,
          radius: BorderRadius.circular(11),
          semanticLabel: engine.displayName,
          builder: (context, focused) => OnboardCardSurface(
            focused: focused,
            selected: isSelected,
            padding: const EdgeInsets.all(12),
            child: _EngineTile(engine: engine, selected: isSelected),
          ),
        );
      },
    );
  }

  Widget buildFooter(BuildContext context) {
    if (loading) {
      return Text(
        'Loading the live catalogue…',
        textAlign: TextAlign.right,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 11,
        ),
      );
    }
    if (error != null) {
      return Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OnboardFocusable(
              controller: focusController,
              cell: const OnboardCell(0, 0),
              onActivate: onRetry,
              shape: ParallaxShape.pill,
              radius: BorderRadius.circular(18),
              builder: (context, focused) =>
                  OnboardPillSurface(focused: focused, label: 'Try again'),
            ),
            const SizedBox(width: 10),
            OnboardFocusable(
              controller: focusController,
              cell: const OnboardCell(0, 1),
              onActivate: onSkip,
              shape: ParallaxShape.pill,
              radius: BorderRadius.circular(18),
              builder: (context, focused) => OnboardPillSurface(
                focused: focused,
                label: 'Skip engines  ›',
                primary: true,
              ),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            engines.isEmpty
                ? 'No engines found'
                : selected.length == engines.length
                ? 'All ${engines.length} selected'
                : '${selected.length} of ${engines.length} selected',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ),
        OnboardFocusable(
          controller: focusController,
          cell: OnboardCell(footerRow, 0),
          onActivate: onTurnAllOff,
          enabled: !importing,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(18),
          builder: (context, focused) => OnboardPillSurface(
            focused: focused,
            label: selected.isEmpty ? 'Turn all on' : 'Turn all off',
          ),
        ),
        const SizedBox(width: 10),
        OnboardFocusable(
          controller: focusController,
          cell: OnboardCell(footerRow, 1),
          onActivate: onContinue,
          enabled: !importing,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(18),
          builder: (context, focused) => OnboardPillSurface(
            focused: focused,
            label: importing ? 'Importing…' : 'Continue  ›',
            primary: true,
            enabled: !importing,
          ),
        ),
      ],
    );
  }
}

class _EngineTile extends StatelessWidget {
  const _EngineTile({required this.engine, required this.selected});

  final RemoteEngineInfo engine;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 25),
              child: Text(
                engine.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (engine.description != null &&
                engine.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                engine.description!.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.36,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? const Color(0xFF34D399) : Colors.transparent,
              border: Border.all(
                color: selected
                    ? const Color(0xFF34D399)
                    : scheme.onSurface.withValues(alpha: 0.22),
              ),
            ),
            child: selected
                ? const Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: Color(0xFF04231A),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
