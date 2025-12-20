import 'package:flutter/material.dart';

class SeekHudState {
  final Duration base;
  final Duration target;
  final bool isForward;
  SeekHudState({
    required this.base,
    required this.target,
    required this.isForward,
  });
}

enum VerticalKind { volume, brightness }

class VerticalHudState {
  final VerticalKind kind;
  final double value; // 0..1
  VerticalHudState({required this.kind, required this.value});
}

class AspectRatioHudState {
  final String aspectRatio;
  final IconData icon;
  const AspectRatioHudState({required this.aspectRatio, required this.icon});
}

class DoubleTapRipple {
  final Offset center;
  final IconData icon;
  DoubleTapRipple({required this.center, required this.icon});
}
