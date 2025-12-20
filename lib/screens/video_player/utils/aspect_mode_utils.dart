import 'package:flutter/material.dart';
import '../models/gesture_state.dart';

class AspectModeUtils {
  /// Converts an AspectMode enum to its string representation
  static String aspectModeToString(AspectMode mode) {
    switch (mode) {
      case AspectMode.cover:
        return 'cover';
      case AspectMode.fitWidth:
        return 'fitWidth';
      case AspectMode.fitHeight:
        return 'fitHeight';
      case AspectMode.aspect16_9:
        return '16:9';
      case AspectMode.aspect4_3:
        return '4:3';
      case AspectMode.aspect21_9:
        return '21:9';
      case AspectMode.aspect1_1:
        return '1:1';
      case AspectMode.aspect3_2:
        return '3:2';
      case AspectMode.aspect5_4:
        return '5:4';
      case AspectMode.contain:
      default:
        return 'contain';
    }
  }

  /// Converts a string to its AspectMode enum value
  static AspectMode stringToAspectMode(String str) {
    switch (str) {
      case 'cover':
        return AspectMode.cover;
      case 'fitWidth':
        return AspectMode.fitWidth;
      case 'fitHeight':
        return AspectMode.fitHeight;
      case '16:9':
        return AspectMode.aspect16_9;
      case '4:3':
        return AspectMode.aspect4_3;
      case '21:9':
        return AspectMode.aspect21_9;
      case '1:1':
        return AspectMode.aspect1_1;
      case '3:2':
        return AspectMode.aspect3_2;
      case '5:4':
        return AspectMode.aspect5_4;
      case 'contain':
      default:
        return AspectMode.contain;
    }
  }

  /// Gets the numeric aspect ratio value for a given AspectMode
  /// Returns null for non-numeric modes (contain, cover, fitWidth, fitHeight)
  static double? getAspectRatioValue(AspectMode mode) {
    switch (mode) {
      case AspectMode.aspect16_9:
        return 16.0 / 9.0;
      case AspectMode.aspect4_3:
        return 4.0 / 3.0;
      case AspectMode.aspect21_9:
        return 21.0 / 9.0;
      case AspectMode.aspect1_1:
        return 1.0;
      case AspectMode.aspect3_2:
        return 3.0 / 2.0;
      case AspectMode.aspect5_4:
        return 5.0 / 4.0;
      default:
        return null;
    }
  }

  /// Gets the BoxFit value for a given AspectMode
  static BoxFit getBoxFitForMode(AspectMode mode) {
    switch (mode) {
      case AspectMode.contain:
        return BoxFit.contain;
      case AspectMode.cover:
        return BoxFit.cover;
      case AspectMode.fitWidth:
        return BoxFit.fitWidth;
      case AspectMode.fitHeight:
        return BoxFit.fitHeight;
      case AspectMode.aspect16_9:
      case AspectMode.aspect4_3:
      case AspectMode.aspect21_9:
      case AspectMode.aspect1_1:
      case AspectMode.aspect3_2:
      case AspectMode.aspect5_4:
        return BoxFit.cover; // Custom aspect ratios handled in widget
    }
  }
}
