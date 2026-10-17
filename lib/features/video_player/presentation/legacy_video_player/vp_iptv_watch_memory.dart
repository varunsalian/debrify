import 'dart:async';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/utils/language_mapping.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpIptvWatchMemoryHost {
  IptvChannel? get currentIptvChannel;
  IptvGuideContext? get iptvGuideContextOverride;
  int get iptvSwitchTicket;
  bool get isIptvSeriesContext;
  bool get isPlaying;
  mk.Player get player;
  bool get mounted;
  String? get iptvSourceId;
}

class VpIptvWatchMemory {
  VpIptvWatchMemory(this._host);
  final VpIptvWatchMemoryHost _host;

  // ==========================================================================
  // Startup-channel memory
  //
  // Remembers the last LIVE channel that actually reached a playing state, so
  // "start on my last channel" re-tunes what was being watched rather than what
  // was last launched — zapping is how live IPTV is used, and the launch
  // channel is stale the moment the user presses up.
  //
  // Recorded on PLAYBACK, not on tune: a dead stream must never replace the
  // last working channel, because the startup feature re-tunes this unattended
  // on every cold boot.
  // ==========================================================================

  Timer? lastLiveChannelTimer;
  String? lastLiveChannelArmedUrl;

  /// Commit-on-settle: a channel counts once it has been *playing* for
  /// [_lastLiveChannelSettle]. Zapping through twenty channels arms and
  /// supersedes one timer rather than writing twenty times, and the commit
  /// lands while the app is alive — an abrupt force-stop runs no lifecycle
  /// callback, so a flush-on-dispose alone would lose it.
  static const Duration lastLiveChannelSettle = Duration(seconds: 1);

  void noteLiveChannelPlaying() {
    final channel = _host.currentIptvChannel;
    if (channel == null || !channel.isLive) return;
    // Already counting down for this very channel — a pause/resume or a
    // re-emitted playing event must not restart the settle window.
    if (lastLiveChannelArmedUrl == channel.url &&
        (lastLiveChannelTimer?.isActive ?? false)) {
      return;
    }
    lastLiveChannelTimer?.cancel();
    lastLiveChannelArmedUrl = channel.url;
    lastLiveChannelTimer = Timer(lastLiveChannelSettle, () {
      // Re-read rather than closing over: the user may have zapped on during
      // the settle window, and the channel that settled is the one that counts.
      final settled = _host.currentIptvChannel;
      if (settled == null || !settled.isLive || settled.url != channel.url) {
        return;
      }
      if (!_host.isPlaying) return;
      unawaited(
        IptvLastChannelStorage.setIptvLastLiveChannel(
          settled.url,
          name: settled.name,
          // Origin provider, resolved the same way the catchup path does —
          // `_originPlaylistIdFor` lives on the IPTV page and is not reachable
          // from here.
          playlistId:
              settled.attributes['source_playlist_id'] ??
              _host.iptvGuideContextOverride?.sourceId ??
              _host.iptvSourceId,
          channelNumber: settled.channelNumber,
          group: settled.group,
          logoUrl: settled.logoUrl,
          httpHeaders: settled.httpHeaders.isEmpty ? null : settled.httpHeaders,
        ),
      );
    });
  }

  /// Session-scoped audio language the user picked while in this IPTV series
  /// (carries across episode switches in this sitting). Persisted per-series
  /// too — see [StorageService.setIptvSeriesAudioLanguage].
  String? preferredIptvAudioLanguage;

  /// Per-series key for remembering the audio language — `<playlistId>::<id>`,
  /// the SAME identity Continue Watching keys by, so two series that merely
  /// share a display name never collide. Null unless this is a series episode.
  String? iptvSeriesAudioKey() {
    final ch = _host.currentIptvChannel;
    if (ch == null || ch.isLive) return null;
    final sid = ch.attributes['series_id'];
    if (sid == null || sid.isEmpty) return null;
    final pid = ch.attributes['series_playlist_id'] ?? '';
    return '$pid::$sid';
  }

  /// Remember the audio language the user just chose for the current IPTV
  /// series episode, so later episodes and future sessions default to it.
  /// No-op for non-IPTV / live / non-series content.
  void captureIptvAudioLanguage(String audioId) {
    if (!_host.isIptvSeriesContext) return;
    String? lang;
    for (final t in _host.player.state.tracks.audio) {
      if (t.id == audioId) {
        lang = t.language;
        break;
      }
    }
    if (lang == null || lang.isEmpty || lang == 'auto' || lang == 'und') return;
    // onTrackChanged also fires on subtitle-only changes and after our own
    // auto-apply — skip the redundant write when the language is unchanged.
    if (lang == preferredIptvAudioLanguage) return;
    preferredIptvAudioLanguage = lang;
    final key = iptvSeriesAudioKey();
    if (key != null) {
      unawaited(IptvAudioStorage.setIptvSeriesAudioLanguage(key, lang));
    }
  }

  /// Re-apply the preferred audio track for an IPTV series episode after a
  /// source change: this sitting's pick → this series' stored pick → the
  /// global default audio language. Matches by language (robust across
  /// episodes whose track ordinals differ). [ticket] is the switch generation
  /// this apply belongs to — a newer switch (or unmount) abandons it, so it
  /// can't set audio on the wrong episode. The preferred language is read
  /// AFTER the track wait, so a manual pick made during the wait wins.
  Future<void> applyIptvAudioPreference(int ticket) async {
    try {
      // Tracks aren't enumerated the instant open() returns — wait briefly,
      // bailing if a newer switch supersedes this one.
      for (var i = 0; i < 20; i++) {
        if (!_host.mounted || ticket != _host.iptvSwitchTicket) return;
        if (_host.player.state.tracks.audio.length >= 2) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!_host.mounted || ticket != _host.iptvSwitchTicket) return;
      final tracks = _host.player.state.tracks;
      if (tracks.audio.length < 2) return; // nothing to switch to

      // Resolve the target language now (not before the wait): a manual pick
      // during the wait updated _preferredIptvAudioLanguage, and it should win.
      String? lang = preferredIptvAudioLanguage;
      if (lang == null) {
        final key = iptvSeriesAudioKey();
        if (key != null) {
          lang = await IptvAudioStorage.getIptvSeriesAudioLanguage(key);
        }
      }
      lang ??= await SubtitleSettingsStorage.getDefaultAudioLanguage();
      if (lang == null || !_host.mounted || ticket != _host.iptvSwitchTicket)
        return;

      mk.AudioTrack? match;
      for (final t in tracks.audio) {
        if (LanguageMapper.matchesLanguage(lang, t.language) ||
            LanguageMapper.matchesLanguage(lang, t.title)) {
          match = t;
          break;
        }
      }
      if (match != null) await _host.player.setAudioTrack(match);
    } catch (_) {
      // Non-critical — audio preference is best-effort.
    }
  }

  /// Write one on-demand IPTV item to the watch history, carrying whatever
  /// series identity the channel was built with (see `openXtreamEpisode`,
  /// which stamps these attributes on every episode of a series). The
  /// playlist id has to match the one the series page records or the shelf
  /// would group the same series under two keys.
  Future<void> recordIptvWatchForChannel(IptvChannel channel) async {
    final attrs = channel.attributes;
    final seriesId = attrs['series_id'];
    final hasNext = attrs['has_next_episode'];
    final headers = channel.httpHeaders;
    try {
      await IptvHistoryStorage.recordIptvWatch(
        channel.url,
        channelName: channel.name,
        logoUrl: channel.logoUrl,
        group: channel.group,
        playlistId:
            attrs['series_playlist_id'] ??
            attrs['source_playlist_id'] ??
            _host.iptvSourceId,
        httpHeaders: headers.isEmpty ? null : headers,
        seriesId: (seriesId != null && seriesId.isNotEmpty) ? seriesId : null,
        seriesName: attrs['series_name'] ?? channel.group,
        season: int.tryParse(attrs['season'] ?? ''),
        episode: int.tryParse(attrs['episode'] ?? ''),
        hasNextEpisode: hasNext == null ? null : hasNext == 'true',
      );
    } catch (e) {
      debugPrint('Player: IPTV watch registration failed: $e');
    }
  }
}
