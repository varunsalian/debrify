import 'dart:io';

/// Linux references were captured from the original Settings revision with
/// the same Flutter SDK; both hosts retain strict pixel comparisons.
String settingsGoldenPath(String filename) =>
    'goldens/${Platform.isLinux ? 'linux/' : ''}$filename';
