/// Detect VR format from video title
/// Returns (screenType, stereoMode) with defaults of 180° SBS
({String screenType, String stereoMode}) detectVRFormat(String title) {
  final titleUpper = title.toUpperCase();

  // Detect stereo mode (default: sbs)
  String stereoMode = 'sbs';
  if (RegExp(r'\b(TB|3DV|OVERUNDER|OVER_UNDER)\b').hasMatch(titleUpper)) {
    stereoMode = 'tb';
  }

  // Detect screen type (default: dome for 180°)
  String screenType = 'dome';
  if (RegExp(r'\b360\b|_360').hasMatch(titleUpper)) {
    screenType = 'sphere';
  } else if (RegExp(r'FISHEYE\s*190|FISHEYE190|_FISHEYE190').hasMatch(titleUpper)) {
    screenType = 'rf52';
  } else if (RegExp(r'MKX\s*200|MKX200|_MKX200').hasMatch(titleUpper)) {
    screenType = 'mkx200';
  } else if (RegExp(r'VRCA\s*220|VRCA220|_VRCA220').hasMatch(titleUpper)) {
    screenType = 'mkx200';
  } else if (RegExp(r'\bFISHEYE\b|_FISHEYE|\b190\s*FISHEYE|_190_?FISHEYE').hasMatch(titleUpper)) {
    screenType = 'fisheye';
  }

  return (screenType: screenType, stereoMode: stereoMode);
}

/// Generate DeoVR JSON for a video URL with specified format
Map<String, dynamic> generateDeoVRJson({
  required String videoUrl,
  required String title,
  required String screenType,
  required String stereoMode,
}) {
  return {
    'title': title,
    'id': videoUrl.hashCode,
    'is3d': stereoMode != 'off',
    'screenType': screenType,
    'stereoMode': stereoMode,
    'encodings': [
      {
        'name': 'h264',
        'videoSources': [
          {
            'resolution': 1080,
            'url': videoUrl,
          }
        ]
      }
    ]
  };
}

/// Screen type options with display labels
const Map<String, String> screenTypeLabels = {
  'flat': '2D Flat',
  'dome': '180° (dome)',
  'sphere': '360° (sphere)',
  'fisheye': '190° Fisheye',
  'mkx200': '200° MKX',
  'rf52': '190° Canon RF52',
};

/// Stereo mode options with display labels
const Map<String, String> stereoModeLabels = {
  'sbs': 'Side by Side',
  'tb': 'Top-Bottom',
  'off': 'Mono (2D)',
};
