import 'dart:convert';
import 'package:android_intent_plus/android_intent.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_disclosure.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_playback_preparation.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/utils/deovr_utils.dart' as deovr;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

final class DeovrLaunch {
  /// Launch video with DeoVR player (Android only)
  /// Returns true if successfully launched, false if should fall back to in-app player
  static Future<bool> launchWithDeoVR(
    BuildContext context,
    VideoPlayerLaunchArgs args, {
    ProfilePlaybackPreparation? preparation,
  }) async {
    bool active() => context.mounted && (preparation?.isCurrent ?? true);
    if (!context.mounted || !active()) return false;
    final url = args.videoUrl;
    final title = args.title;

    if (!await ProfilePolicyGuard.allows(ProfileFeature.externalPlayers)) {
      return false;
    }
    if (!context.mounted || !active()) return false;
    if (ExternalDisclosure.mayDiscloseCredential(url) &&
        !await ExternalDisclosure.confirmExternalDisclosure(context)) {
      return false;
    }

    if (!context.mounted || !active()) return false;
    try {
      // Load VR settings
      final vrAutoDetectFormat = await QuickPlayStorage.getQuickPlayVrAutoDetectFormat();
      if (!context.mounted || !active()) return false;
      final vrShowDialog = await QuickPlayStorage.getQuickPlayVrShowDialog();
      if (!context.mounted || !active()) return false;
      final vrDefaultScreenType = await QuickPlayStorage.getQuickPlayVrDefaultScreenType();
      if (!context.mounted || !active()) return false;
      final vrDefaultStereoMode = await QuickPlayStorage.getQuickPlayVrDefaultStereoMode();

      if (!context.mounted || !active()) return false;
      // Detect or use default format
      String selectedScreenType = vrDefaultScreenType;
      String selectedStereoMode = vrDefaultStereoMode;

      if (vrAutoDetectFormat) {
        final detected = deovr.detectVRFormat(title);
        selectedScreenType = detected.screenType;
        selectedStereoMode = detected.stereoMode;
      }

      // Show format selection dialog if enabled
      if (vrShowDialog && active()) {
        final result = await DeovrLaunch.showDeoVRFormatDialog(
          context,
          title: title,
          initialScreenType: selectedScreenType,
          initialStereoMode: selectedStereoMode,
        );

        if (!active() || result == null) {
          // User cancelled
          return false;
        }

        selectedScreenType = result.screenType;
        selectedStereoMode = result.stereoMode;
      }

      // Generate DeoVR JSON
      final json = deovr.generateDeoVRJson(
        videoUrl: url,
        title: title,
        screenType: selectedScreenType,
        stereoMode: selectedStereoMode,
      );
      final jsonString = jsonEncode(json);

      debugPrint('DeoVR JSON content: $jsonString');

      if (!context.mounted || !active()) return false;
      // Upload JSON to jsonblob.com
      final response = await http.post(
        Uri.parse('https://jsonblob.com/api/jsonBlob'),
        headers: {'Content-Type': 'application/json'},
        body: jsonString,
      );

      if (!context.mounted || !active()) return false;
      if (response.statusCode != 201) {
        throw Exception('Failed to upload JSON: ${response.statusCode}');
      }

      final location = response.headers['location'];
      if (location == null) {
        throw Exception('No location header in response');
      }

      final jsonUrl = 'https://jsonblob.com$location';
      debugPrint('DeoVR JSON uploaded to: $jsonUrl');

      // Launch DeoVR with the public URL
      final deOvrUri = 'deovr://$jsonUrl';
      debugPrint('Launching DeoVR with URI: $deOvrUri');

      final intent = AndroidIntent(action: 'action_view', data: deOvrUri);
      await intent.launch();

      if (context.mounted && active()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Launching DeoVR...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      return true;
    } catch (e) {
      debugPrint('Failed to launch DeoVR: $e');
      if (context.mounted && active()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open DeoVR: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return false;
    }
  }

  /// Show DeoVR format selection dialog
  static Future<({String screenType, String stereoMode})?> showDeoVRFormatDialog(
    BuildContext context, {
    required String title,
    required String initialScreenType,
    required String initialStereoMode,
  }) async {
    String selectedScreenType = initialScreenType;
    String selectedStereoMode = initialStereoMode;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('DeoVR Format'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              const Text(
                'Screen Type',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedScreenType,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: deovr.screenTypeLabels.entries
                    .map(
                      (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedScreenType = value);
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Stereo Mode',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedStereoMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: deovr.stereoModeLabels.entries
                    .map(
                      (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedStereoMode = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
          ],
        ),
      ),
    );

    if (result != true) {
      return null;
    }

    return (screenType: selectedScreenType, stereoMode: selectedStereoMode);
  }
}
