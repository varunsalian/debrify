import 'dart:io';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:flutter/material.dart';

final class ExternalDisclosure {
  /// Whether a launch needs to explain why the user's external-player default
  /// cannot be honored. Authenticated server playback carries headers which
  /// can be consumed by Debrify's player but are not part
  /// of the URL handed to another app.
  static bool shouldExplainExternalPlayerFallback(
    VideoPlayerLaunchArgs args,
    String defaultPlayerMode,
  ) {
    final wantsExternal =
        defaultPlayerMode == 'external' || (defaultPlayerMode == 'deovr' && Platform.isAndroid);
    final carriesAuthorization =
        args.httpHeaders?.keys.any(
          (key) => key.toLowerCase() == 'authorization' || key.toLowerCase() == 'x-emby-token',
        ) ??
        false;
    return wantsExternal && args.disableExternalPlayer && carriesAuthorization;
  }

  static bool mayDiscloseCredential(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) return true;
    if (uri.userInfo.isNotEmpty) return true;
    const sensitive = <String>{
      'token',
      'key',
      'api_key',
      'apikey',
      'auth',
      'authorization',
      'signature',
      'sig',
      'expires',
    };
    return uri.queryParameters.keys.any(
      (key) => sensitive.contains(key.toLowerCase()),
    );
  }

  static Future<bool> confirmExternalDisclosure(BuildContext context) async {
    if (!context.mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Share stream with another app?'),
            content: const Text(
              'This stream address may contain a short-lived account token. '
              'The selected player will be able to read it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Use Debrify player'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
