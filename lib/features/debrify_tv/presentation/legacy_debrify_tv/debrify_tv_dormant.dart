import 'dart:async';

import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:flutter/material.dart';

class DebrifyTvDormant {
  final DebrifyTvDependencies _deps;
  DebrifyTvDormant(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> _playNextFromQueue() async {
    if (_owners.session.isBusy) return;
    final apiKey = await RealDebridStorage.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add your Real Debrid API key in Settings first!',
          ),
        ),
      );
      return;
    }

    _deps.setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Finding a playable stream...';
    });

    try {
      while (_owners.session.queue.isNotEmpty) {
        final next = _owners.session.queue.removeAt(0);
        final magnetLink = 'magnet:?xt=urn:btih:${next.infohash}';
        try {
          final result = await DebridService.addTorrentToDebridPreferVideos(
            apiKey,
            magnetLink,
          );
          final videoUrl = result['downloadLink'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            if (!_deps.mounted()) return;
            _deps.setState(() {
              _owners.session.status = 'Playing: ${next.name}';
            });

            if (await _sections.handoff.handOffToExternalPlayer(
              videoUrl,
              next.name,
            )) {
              break;
            }

            // Hide auto-launch overlay before launching player
            MainPageBridge.notifyPlayerLaunching();

            await Navigator.of(_deps.context()).push(
              videoPlayerRoute(
                builder: (_) => VideoPlayerScreen(
                  videoUrl: videoUrl,
                  title: next.name,
                  startFromRandom: _owners.settings.quickStartRandom,
                  randomStartMaxPercent:
                      _owners.settings.quickRandomStartPercent,
                  hideSeekbar: _owners.settings.quickHideSeekbar,
                  showChannelName: _owners.settings.quickShowChannelName,
                  channelName: null,
                  channelNumber: null,
                  showVideoTitle: _owners.settings.quickShowVideoTitle,
                  hideOptions: _owners.settings.quickHideOptions,
                ),
              ),
            );
            break;
          }
        } catch (_) {
          // Skip not readily available / failed items and continue
          continue;
        }
      }

      if (_owners.session.queue.isEmpty) {
        // Close popup and show user-friendly message
        if (_owners.progress.progressOpen &&
            _owners.progress.progressSheetContext != null) {
          Navigator.of(_owners.progress.progressSheetContext!).pop();
          _owners.progress.progressOpen = false;
          _owners.progress.progressSheetContext = null;
        }

        if (_deps.mounted()) {
          _deps.setState(() {
            _owners.session.isBusy = false;
            _owners.session.status =
                'No playable torrents found. Try different keywords.';
          });
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            const SnackBar(
              content: Text(
                'All torrents failed to process. Try different keywords or check your internet connection.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        _deps.setState(() {
          _owners.session.status =
              'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } finally {
      _deps.setState(() {
        _owners.session.isBusy = false;
      });
    }
  }
}
