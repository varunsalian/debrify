import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

class IptvTwoPanePaneHeader extends StatelessWidget {
  const IptvTwoPanePaneHeader({
    required this.icon,
    required this.title,
    required this.meta,
    required this.badges,
  });

  final IconData icon;
  final String title;
  final String meta;
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: t.panel2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 26, color: t.accent2),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: t.dim),
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 7, runSpacing: 7, children: badges),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class IptvTwoPaneBadge extends StatelessWidget {
  const IptvTwoPaneBadge(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class IptvTwoPaneStatStrip extends StatelessWidget {
  const IptvTwoPaneStatStrip({required this.stats});
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stats[i].$2,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stats[i].$1.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: t.dim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class IptvTwoPaneQuietBanner extends StatelessWidget {
  const IptvTwoPaneQuietBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: t.dim),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: t.dim)),
          ),
        ],
      ),
    );
  }
}

class IptvTwoPaneRowGroup extends StatelessWidget {
  const IptvTwoPaneRowGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.line),
      ),
      child: Column(children: children),
    );
  }
}
