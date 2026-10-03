import 'package:flutter/material.dart';

class DebridAddInputState {
  // Magnet input
  final TextEditingController magnetController = TextEditingController();

  bool isAddingMagnet = false;

  // Link input
  final TextEditingController linkController = TextEditingController();

  bool isAddingLink = false;
}
