import 'package:flutter/material.dart';

/// Supported external video players for iOS
/// Each player uses URL schemes to launch with a video URL
enum iOSExternalPlayer {
  vlc,
  infuse,
  outplayer,
  nplayer,
  playerXtreme,
  vimu,
  customScheme,
}

extension iOSExternalPlayerExtension on iOSExternalPlayer {
  /// Human-readable display name
  String get displayName {
    switch (this) {
      case iOSExternalPlayer.vlc:
        return 'VLC';
      case iOSExternalPlayer.infuse:
        return 'Infuse';
      case iOSExternalPlayer.outplayer:
        return 'Outplayer';
      case iOSExternalPlayer.nplayer:
        return 'nPlayer';
      case iOSExternalPlayer.playerXtreme:
        return 'PlayerXtreme';
      case iOSExternalPlayer.vimu:
        return 'Vimu';
      case iOSExternalPlayer.customScheme:
        return 'Custom URL Scheme';
    }
  }

  /// Description of the player
  String get description {
    switch (this) {
      case iOSExternalPlayer.vlc:
        return 'Free, open-source media player';
      case iOSExternalPlayer.infuse:
        return 'Premium player with streaming support';
      case iOSExternalPlayer.outplayer:
        return 'Feature-rich video player';
      case iOSExternalPlayer.nplayer:
        return 'Powerful media player with codec support';
      case iOSExternalPlayer.playerXtreme:
        return 'All-format video player';
      case iOSExternalPlayer.vimu:
        return 'Simple and clean video player';
      case iOSExternalPlayer.customScheme:
        return 'Define your own URL scheme';
    }
  }

  /// URL scheme for checking if app is installed (for canOpenURL)
  /// This is the base scheme without parameters
  String get urlScheme {
    switch (this) {
      case iOSExternalPlayer.vlc:
        return 'vlc://';
      case iOSExternalPlayer.infuse:
        return 'infuse://';
      case iOSExternalPlayer.outplayer:
        return 'outplayer://';
      case iOSExternalPlayer.nplayer:
        return 'nplayer://';
      case iOSExternalPlayer.playerXtreme:
        return 'playerxtreme://';
      case iOSExternalPlayer.vimu:
        return 'vimu://';
      case iOSExternalPlayer.customScheme:
        return ''; // User-defined
    }
  }

  /// Build the full URL to launch the player with a video
  ///
  /// Different players have different URL formats:
  /// - VLC: vlc://http://video.url
  /// - Infuse: infuse://x-callback-url/play?url=http://video.url
  /// - Outplayer: outplayer://http://video.url
  /// - nPlayer: nplayer-http://video.url (replaces http:// with nplayer-)
  /// - PlayerXtreme: playerxtreme://http://video.url
  /// - Vimu: vimu://http://video.url
  String buildLaunchUrl(String videoUrl) {
    switch (this) {
      case iOSExternalPlayer.vlc:
        // VLC format: vlc://http://example.com/video.mp4
        return 'vlc://$videoUrl';

      case iOSExternalPlayer.infuse:
        // Infuse format: infuse://x-callback-url/play?url=<encoded_url>
        final encodedUrl = Uri.encodeComponent(videoUrl);
        return 'infuse://x-callback-url/play?url=$encodedUrl';

      case iOSExternalPlayer.outplayer:
        // Outplayer format: outplayer://http://example.com/video.mp4
        return 'outplayer://$videoUrl';

      case iOSExternalPlayer.nplayer:
        // nPlayer format: nplayer-http://example.com/video.mp4
        // Prefix the URL with nplayer-
        if (videoUrl.startsWith('https://') || videoUrl.startsWith('http://')) {
          return 'nplayer-$videoUrl';
        }
        return 'nplayer-http://$videoUrl';

      case iOSExternalPlayer.playerXtreme:
        // PlayerXtreme format: playerxtreme://http://example.com/video.mp4
        return 'playerxtreme://$videoUrl';

      case iOSExternalPlayer.vimu:
        // Vimu format: vimu://http://example.com/video.mp4
        return 'vimu://$videoUrl';

      case iOSExternalPlayer.customScheme:
        // Custom scheme - should not be called directly
        // Use buildCustomLaunchUrl instead
        return videoUrl;
    }
  }

  /// Icon representing the player
  IconData get icon {
    switch (this) {
      case iOSExternalPlayer.vlc:
        return Icons.play_circle_filled_rounded;
      case iOSExternalPlayer.infuse:
        return Icons.smart_display_rounded;
      case iOSExternalPlayer.outplayer:
        return Icons.ondemand_video_rounded;
      case iOSExternalPlayer.nplayer:
        return Icons.video_library_rounded;
      case iOSExternalPlayer.playerXtreme:
        return Icons.videocam_rounded;
      case iOSExternalPlayer.vimu:
        return Icons.play_arrow_rounded;
      case iOSExternalPlayer.customScheme:
        return Icons.code_rounded;
    }
  }

  /// Storage key value for persistence
  String get storageKey {
    switch (this) {
      case iOSExternalPlayer.vlc:
        return 'vlc';
      case iOSExternalPlayer.infuse:
        return 'infuse';
      case iOSExternalPlayer.outplayer:
        return 'outplayer';
      case iOSExternalPlayer.nplayer:
        return 'nplayer';
      case iOSExternalPlayer.playerXtreme:
        return 'playerxtreme';
      case iOSExternalPlayer.vimu:
        return 'vimu';
      case iOSExternalPlayer.customScheme:
        return 'custom_scheme';
    }
  }

  /// Create iOSExternalPlayer from storage key
  static iOSExternalPlayer fromStorageKey(String key) {
    switch (key) {
      case 'vlc':
        return iOSExternalPlayer.vlc;
      case 'infuse':
        return iOSExternalPlayer.infuse;
      case 'outplayer':
        return iOSExternalPlayer.outplayer;
      case 'nplayer':
        return iOSExternalPlayer.nplayer;
      case 'playerxtreme':
        return iOSExternalPlayer.playerXtreme;
      case 'vimu':
        return iOSExternalPlayer.vimu;
      case 'custom_scheme':
        return iOSExternalPlayer.customScheme;
      default:
        return iOSExternalPlayer.vlc; // Default to VLC
    }
  }
}

/// Build a custom URL scheme launch URL from a template
/// Template should contain {url} placeholder
/// Example: "myplayer://play?video={url}"
String buildCustomSchemeLaunchUrl(String template, String videoUrl) {
  if (!template.contains('{url}')) {
    // If no placeholder, append the URL
    return '$template$videoUrl';
  }

  // Check if URL should be encoded (if template contains url= or similar)
  final needsEncoding = template.contains('url=') ||
                         template.contains('={url}') ||
                         template.contains('?{url}');

  final urlToInsert = needsEncoding ? Uri.encodeComponent(videoUrl) : videoUrl;
  return template.replaceAll('{url}', urlToInsert);
}

/// Validate a custom URL scheme template
class CustomSchemeValidation {
  final bool isValid;
  final String? errorMessage;

  const CustomSchemeValidation({
    required this.isValid,
    this.errorMessage,
  });

  factory CustomSchemeValidation.valid() {
    return const CustomSchemeValidation(isValid: true);
  }

  factory CustomSchemeValidation.invalid(String message) {
    return CustomSchemeValidation(isValid: false, errorMessage: message);
  }
}

CustomSchemeValidation validateCustomScheme(String? scheme) {
  if (scheme == null || scheme.trim().isEmpty) {
    return CustomSchemeValidation.invalid('URL scheme cannot be empty');
  }

  final trimmed = scheme.trim();

  // Must contain a scheme separator
  if (!trimmed.contains('://')) {
    return CustomSchemeValidation.invalid('Must contain :// (e.g., myapp://)');
  }

  // Should not start with http or https (those aren't custom schemes)
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return CustomSchemeValidation.invalid('Cannot use http:// or https://');
  }

  return CustomSchemeValidation.valid();
}
