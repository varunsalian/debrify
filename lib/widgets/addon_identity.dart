import 'package:flutter/material.dart';

/// A non-interactive identity beside source text; image failures keep its size.
class AddonIdentity extends StatelessWidget {
  const AddonIdentity({super.key, required this.name, this.logo, this.large = false,
    this.color});
  final String name;
  final String? logo;
  final bool large;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.onSurface;
    final words = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final initials = words.take(2).map((s) => s.characters.first).join().toUpperCase();
    final fallback = Center(child: Text(initials.isEmpty ? '?' : initials,
      style: TextStyle(color: ink, fontSize: large ? 17 : 14, fontWeight: FontWeight.w700)));
    final uri = Uri.tryParse(logo ?? '');
    final valid = uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
    final size = large ? 48.0 : 36.0;
    return ExcludeFocus(child: SizedBox(width: large ? 80 : 62, child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: size, height: size, padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: ink.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ink.withValues(alpha: .10))),
          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: valid
            ? Image.network(logo!, fit: BoxFit.contain, cacheWidth: (size * 2).round(),
                errorBuilder: (_, __, ___) => fallback)
            : fallback)),
        const SizedBox(height: 5),
        Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: ink.withValues(alpha: .65), fontSize: large ? 11 : 10, height: 1.2)),
      ],
    )));
  }
}
