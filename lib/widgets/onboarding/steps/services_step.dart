import 'package:flutter/material.dart';

import '../../../theme/widgets/parallax_focus.dart';
import '../onboarding_focus.dart';
import '../onboarding_models.dart';
import '../onboarding_stage.dart';

class ServicesStep extends StatelessWidget {
  const ServicesStep({
    super.key,
    required this.layout,
    required this.focusController,
    required this.selection,
    required this.onToggle,
    required this.onNone,
    required this.onContinue,
  });

  final OnboardLayout layout;
  final OnboardFocusController focusController;
  final Set<IntegrationType> selection;
  final ValueChanged<IntegrationType> onToggle;
  final VoidCallback onNone;
  final VoidCallback onContinue;

  int get _columns => switch (layout) {
    OnboardLayout.phone => 1,
    OnboardLayout.tablet => 2,
    OnboardLayout.stage => 3,
  };

  int get footerRow => (integrationMeta.length / _columns).ceil();

  @override
  Widget build(BuildContext context) {
    final entries = integrationMeta.values.toList(growable: false);
    return GridView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        crossAxisSpacing: 13,
        mainAxisSpacing: 13,
        childAspectRatio: layout == OnboardLayout.phone ? 2.45 : 1.32,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final meta = entries[index];
        final selected = selection.contains(meta.type);
        return OnboardFocusable(
          key: ValueKey(meta.type),
          controller: focusController,
          cell: OnboardCell(index ~/ _columns, index % _columns),
          onActivate: () => onToggle(meta.type),
          radius: BorderRadius.circular(11),
          semanticLabel: meta.title,
          builder: (context, focused) => OnboardCardSurface(
            focused: focused,
            selected: selected,
            padding: const EdgeInsets.all(10),
            child: _ServiceCard(meta: meta, selected: selected),
          ),
        );
      },
    );
  }

  Widget buildFooter(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            selection.isEmpty
                ? 'Nothing selected'
                : '${selection.length} selected',
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
          onActivate: onNone,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(18),
          builder: (context, focused) =>
              OnboardPillSurface(focused: focused, label: "I don't have any"),
        ),
        const SizedBox(width: 10),
        OnboardFocusable(
          controller: focusController,
          cell: OnboardCell(footerRow, 1),
          onActivate: onContinue,
          enabled: selection.isNotEmpty,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(18),
          builder: (context, focused) => OnboardPillSurface(
            focused: focused,
            label: 'Continue  ›',
            primary: true,
            enabled: selection.isNotEmpty,
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.meta, required this.selected});

  final IntegrationMeta meta;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 37,
              height: 37,
              decoration: BoxDecoration(
                color: meta.color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(meta.icon, size: 20, color: Colors.white),
            ),
            const Spacer(),
            Text(
              meta.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              meta.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.32,
                color: scheme.onSurface.withValues(alpha: 0.52),
              ),
            ),
          ],
        ),
        Positioned(
          right: 0,
          top: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 21,
            height: 21,
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
                    size: 14,
                    color: Color(0xFF04231A),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
