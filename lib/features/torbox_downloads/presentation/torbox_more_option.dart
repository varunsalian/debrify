import 'package:flutter/material.dart';

class TorboxMoreOption {
  const TorboxMoreOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool destructive;
  final bool enabled;
}
