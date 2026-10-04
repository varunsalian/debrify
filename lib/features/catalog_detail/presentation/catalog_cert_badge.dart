import 'package:flutter/material.dart';

class _CertBadge extends StatelessWidget {
  final String label;
  const _CertBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.50),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          height: 1.3,
        ),
      ),
    );
  }
}

typedef CatalogCertBadge = _CertBadge;

const catalogCertBadgeConstructor = _CertBadge.new;
