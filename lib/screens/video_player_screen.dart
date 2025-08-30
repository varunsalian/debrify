import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

// Removed volume_controller; using media_kit player volume instead
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/storage_service.dart';
import '../services/android_native_downloader.dart';
import '../services/debrid_service.dart';
import '../models/series_playlist.dart';



import '../widgets/series_browser.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

/// A full-featured video player screen with playlist support and navigation controls.
/// 
/// Features:
/// - Play/pause controls
/// - Next/Previous episode navigation (when playlist is available)
/// - Gesture controls for seeking, volume, and brightness
/// - Aspect ratio controls
/// - Playback speed controls
/// - Audio and subtitle track selection
/// - Auto-advance to next episode when current episode ends
/// - Resume playback from last position
/// - Series-aware episode ordering and tracking
class VideoPlayerScreen extends StatefulWidget {
	final String videoUrl;
	final String title;
	final String? subtitle;
	final List<PlaylistEntry>? playlist;
	final int? startIndex;

	const VideoPlayerScreen({
		Key? key,
		required this.videoUrl,
		required this.title,
		this.subtitle,
		this.playlist,
		this.startIndex,
	}) : super(key: key);

	SeriesPlaylist? get _seriesPlaylist {
		if (playlist == null || playlist!.isEmpty) return null;
		return SeriesPlaylist.fromPlaylistEntries(playlist!);
	}

	@override
	State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class PlaylistEntry {
	final String url;
	final String title;
	final String? restrictedLink; // The original restricted link from debrid
	final String? apiKey; // API key for unrestricting
	const PlaylistEntry({
		required this.url, 
		required this.title, 
		this.restrictedLink,
		this.apiKey,
	});
}



enum _GestureMode { none, seek, volume, brightness }

enum _AspectMode { 
  contain, 
  cover, 
  fitWidth, 
  fitHeight,
  aspect16_9,
  aspect4_3,
  aspect21_9,
  aspect1_1,
  aspect3_2,
  aspect5_4,
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with TickerProviderStateMixin {
	late mk.Player _player;
	late mkv.VideoController _videoController;
	SeriesPlaylist? _cachedSeriesPlaylist;
	final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);
	

	
	SeriesPlaylist? get _seriesPlaylist {
		if (widget.playlist == null || widget.playlist!.isEmpty) return null;
		if (_cachedSeriesPlaylist == null) {
			_cachedSeriesPlaylist = SeriesPlaylist.fromPlaylistEntries(widget.playlist!);
		}
		return _cachedSeriesPlaylist;
	}
	Timer? _hideTimer;
	bool _isSeekingWithSlider = false;
	_DoubleTapRipple? _ripple;
	bool _panIgnore = false;
	int _currentIndex = 0;
	Offset? _lastTapLocal;
	bool _isManualEpisodeSelection = false; // Track if episode was manually selected
	bool _isAutoAdvancing = false; // Track if episode is auto-advancing
	bool _allowResumeForManualSelection = false; // Allow resuming for manual selections with progress
	Timer? _manualSelectionResetTimer; // Timer to reset manual selection flag

	// media_kit state
	bool _isReady = false;
	bool _isPlaying = false;
	Duration _position = Duration.zero;
	Duration _duration = Duration.zero;
	// We render using a large logical surface; fit is controlled by BoxFit
	StreamSubscription? _posSub;
	StreamSubscription? _durSub;
	StreamSubscription? _playSub;
	StreamSubscription? _paramsSub;
	StreamSubscription? _completedSub;

	// Gesture state
	_GestureMode _mode = _GestureMode.none;
	Offset _gestureStartPosition = Offset.zero;
	Duration _gestureStartVideoPosition = Duration.zero;
	double _gestureStartVolume = 0.0;
	double _gestureStartBrightness = 0.0;

	// HUD state
	final ValueNotifier<_SeekHudState?> _seekHud = ValueNotifier<_SeekHudState?>(null);
	final ValueNotifier<_VerticalHudState?> _verticalHud = ValueNotifier<_VerticalHudState?>(null);
	final ValueNotifier<_AspectRatioHudState?> _aspectRatioHud = ValueNotifier<_AspectRatioHudState?>(null);

	// Aspect / speed
	_AspectMode _aspectMode = _AspectMode.contain;
	double _playbackSpeed = 1.0;

	// Orientation
	bool _landscapeLocked = false;

	@override
	void initState() {
		super.initState();
		mk.MediaKit.ensureInitialized();
		SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
		// Default to landscape when entering the player
		SystemChrome.setPreferredOrientations(<DeviceOrientation>[
			DeviceOrientation.landscapeLeft,
			DeviceOrientation.landscapeRight,
		]);
		_landscapeLocked = true;
		WakelockPlus.enable();
		// System volume UI not modified
		
		// Initialize the player asynchronously
		_initializePlayer();
	}

	Future<void> _initializePlayer() async {
		// Determine the initial URL and index
		String initialUrl = widget.videoUrl;
		int initialIndex = 0;
		
		if (widget.playlist != null && widget.playlist!.isNotEmpty) {
			for (int i = 0; i < widget.playlist!.length; i++) {
				final entry = widget.playlist![i];
			}
			
			// Check if this is a series and we should find the first episode by season/episode
			final seriesPlaylist = _seriesPlaylist;
			if (seriesPlaylist != null && seriesPlaylist.isSeries) {
				// Try to restore the last played episode first
				final lastEpisode = await _getLastPlayedEpisode(seriesPlaylist);
				if (lastEpisode != null) {
					initialIndex = lastEpisode['originalIndex'] as int;
				} else {
					// Find the first episode (lowest season, lowest episode)
					final firstEpisodeIndex = seriesPlaylist.getFirstEpisodeOriginalIndex();
					if (firstEpisodeIndex != -1) {
						initialIndex = firstEpisodeIndex;
					} else {
						initialIndex = widget.startIndex ?? 0;
					}
				}
			} else {
				// For non-series playlists, try to restore the last played video
				if (widget.playlist != null && widget.playlist!.isNotEmpty) {
					// Try to find the last played video by checking each playlist entry
					int lastPlayedIndex = -1;
					Map<String, dynamic>? lastPlayedState;
					
					for (int i = 0; i < widget.playlist!.length; i++) {
						final entry = widget.playlist![i];
						String videoFilename = entry.title;
						
						if (videoFilename.isNotEmpty) {
							// Generate stable hash from filename
							final filenameHash = _generateFilenameHash(videoFilename);
							
							final state = await StorageService.getVideoPlaybackState(videoTitle: filenameHash);
							if (state != null) {
								final updatedAt = state['updatedAt'] as int? ?? 0;
								if (lastPlayedState == null || updatedAt > (lastPlayedState['updatedAt'] as int? ?? 0)) {
									lastPlayedState = state;
									lastPlayedIndex = i;
								}
							}
						}
					}
					
					if (lastPlayedIndex != -1) {
						initialIndex = lastPlayedIndex;
					} else {
						initialIndex = widget.startIndex ?? 0;
					}
				} else {
					// Not a series or no series playlist, use the provided startIndex
					initialIndex = widget.startIndex ?? 0;
				}
			}
		} else {
		}
		
		// Get the initial URL from the determined index
		if (widget.playlist != null && widget.playlist!.isNotEmpty && initialIndex < widget.playlist!.length) {
			final entry = widget.playlist![initialIndex];
			if (entry.url.isNotEmpty) {
				initialUrl = entry.url;
			} else if (entry.restrictedLink != null && entry.apiKey != null) {
				try {
					final unrestrictResult = await DebridService.unrestrictLink(entry.apiKey!, entry.restrictedLink!);
					initialUrl = unrestrictResult['download'] ?? '';
				} catch (e) {
					// Only fall back to widget.videoUrl if unrestriction fails
					if (widget.videoUrl.isNotEmpty) {
						initialUrl = widget.videoUrl;
					}
				}
			} else {
				// Only fall back to widget.videoUrl if no other option
				if (widget.videoUrl.isNotEmpty) {
					initialUrl = widget.videoUrl;
				}
			}
		}
		
		_currentIndex = initialIndex;
		_player = mk.Player(configuration: mk.PlayerConfiguration(ready: () {
			_isReady = true;
			if (mounted) setState(() {});
		}));
		_videoController = mkv.VideoController(_player);
		
		// Only open the player if we have a valid URL
		if (initialUrl.isNotEmpty) {
			_player.open(mk.Media(initialUrl)).then((_) async {
				// Wait for the video to load and duration to be available
				await _waitForVideoReady();
				await _maybeRestoreResume();
				_scheduleAutoHide();
				// Restore audio and subtitle track preferences
				await _restoreTrackPreferences();
			});
		} else {
			// If no valid URL, try to load the first playlist entry
			if (widget.playlist != null && widget.playlist!.isNotEmpty) {
				_loadPlaylistIndex(_currentIndex, autoplay: false);
			}
		}
		_posSub = _player.stream.position.listen((d) {
			_position = d;
			// throttle UI updates
			if (mounted) setState(() {});
			// Check if episode should be marked as finished (for manual seeking)
			_checkAndMarkEpisodeAsFinished();
		});
		_durSub = _player.stream.duration.listen((d) {
			_duration = d;
			if (mounted) setState(() {});
		});
		_playSub = _player.stream.playing.listen((p) {
			_isPlaying = p;
			if (mounted) setState(() {});
		});
		// No need to observe video params for sizing; we use a fixed logical surface
		_completedSub = _player.stream.completed.listen((done) {
			if (done) _onPlaybackEnded();
		});
		_autosaveTimer = Timer.periodic(const Duration(seconds: 6), (_) => _saveResume(debounced: true));
		
		// Preload episode information if this is a series
		_preloadEpisodeInfo();
	}

		// Wait for the video to be ready and duration to be available
		Future<void> _waitForVideoReady() async {
			// Wait up to 10 seconds for the video to be ready
			for (int i = 0; i < 100; i++) {
				if (_duration > Duration.zero) {
					return;
				}
				await Future.delayed(const Duration(milliseconds: 100));
			}
		}
		
		// Wait for duration to be available before attempting position restoration
		Future<void> _waitForDuration() async {
			// Wait up to 20 seconds for duration to be available
			for (int i = 0; i < 200; i++) {
				if (_duration > Duration.zero) {
					return;
				}
				await Future.delayed(const Duration(milliseconds: 100));
			}
		}

	/// Get the last played episode for a series
	Future<Map<String, dynamic>?> _getLastPlayedEpisode(SeriesPlaylist seriesPlaylist) async {
		try {
			final lastEpisode = await StorageService.getLastPlayedEpisode(
				seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
			);
			
			if (lastEpisode != null) {
				final season = lastEpisode['season'] as int;
				final episode = lastEpisode['episode'] as int;
				
				// Find the original index for this episode
				final originalIndex = seriesPlaylist.findOriginalIndexBySeasonEpisode(season, episode);
				if (originalIndex != -1) {
					return {
						...lastEpisode,
						'originalIndex': originalIndex,
					};
				}
			}
		} catch (e) {
		}
		return null;
	}

	void _onVideoUpdate() {
		// Update slider-driven seeks HUD if needed
		if (!mounted) return;
		// handled via stream.completed
		if (mounted) setState(() {});
	}

	Future<void> _onPlaybackEnded() async {
		// Mark the current episode as finished if it's a series
		await _markCurrentEpisodeAsFinished();
		
		if (widget.playlist == null || widget.playlist!.isEmpty) return;
		
		// Find the next logical episode
		final nextIndex = _findNextEpisodeIndex();
		if (nextIndex == -1) return; // No next episode found
		
		// Mark this as auto-advancing to the next episode
		_isAutoAdvancing = true;
		await _loadPlaylistIndex(nextIndex, autoplay: true);
	}

	/// Get the current episode title for display
	String _getCurrentEpisodeTitle() {
		final seriesPlaylist = _seriesPlaylist;
		if (seriesPlaylist != null && seriesPlaylist.isSeries && widget.playlist != null) {
			// Find the current episode info
			if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
				try {
					final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
						(episode) => episode.originalIndex == _currentIndex,
						orElse: () => seriesPlaylist.allEpisodes.first,
					);
					
					// Return episode title if available, otherwise use the playlist entry title
					if (currentEpisode.episodeInfo?.title != null && currentEpisode.episodeInfo!.title!.isNotEmpty) {
						return currentEpisode.episodeInfo!.title!;
					} else if (currentEpisode.seriesInfo.season != null && currentEpisode.seriesInfo.episode != null) {
						return 'Episode ${currentEpisode.seriesInfo.episode}';
					}
				} catch (e) {
				}
			}
		}
		
		// Fallback to the current playlist entry title
		if (widget.playlist != null && _currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
			return widget.playlist![_currentIndex].title;
		}
		
		// Final fallback to the current title or widget title
		return widget.title;
	}

	/// Get the current episode subtitle for display
	String? _getCurrentEpisodeSubtitle() {
		final seriesPlaylist = _seriesPlaylist;
		if (seriesPlaylist != null && seriesPlaylist.isSeries && widget.playlist != null) {
			// Find the current episode info
			if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
				try {
					final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
						(episode) => episode.originalIndex == _currentIndex,
						orElse: () => seriesPlaylist.allEpisodes.first,
					);
					
					// Return series name and season/episode info as subtitle
					if (currentEpisode.seriesInfo.season != null && currentEpisode.seriesInfo.episode != null) {
						final seriesName = seriesPlaylist.seriesTitle ?? 'Unknown Series';
						return '$seriesName • Season ${currentEpisode.seriesInfo.season}, Episode ${currentEpisode.seriesInfo.episode}';
					}
				} catch (e) {
				}
			}
		}
		
		// Fallback to the current subtitle or widget subtitle
		return widget.subtitle;
	}

	/// Get enhanced metadata for OTT-style display
	Map<String, dynamic> _getEnhancedMetadata() {
		final seriesPlaylist = _seriesPlaylist;
		
		if (seriesPlaylist != null && seriesPlaylist.isSeries && widget.playlist != null) {
			// Find the current episode info
			if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
				try {
					final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
						(episode) => episode.originalIndex == _currentIndex,
						orElse: () => seriesPlaylist.allEpisodes.first,
					);
					
					if (currentEpisode.episodeInfo != null) {
						final episodeInfo = currentEpisode.episodeInfo!;
						
						final metadata = {
							'rating': episodeInfo.rating,
							'runtime': episodeInfo.runtime,
							'year': episodeInfo.year,
							'airDate': episodeInfo.airDate,
							'language': episodeInfo.language,
							'genres': episodeInfo.genres,
							'network': episodeInfo.network,
							'country': episodeInfo.country,
							'plot': episodeInfo.plot,
						};
						
						return metadata;
					}
				} catch (e) {
				}
			}
		}
		
		return {};
	}

	/// Find the next logical episode index for auto-advance
	int _findNextEpisodeIndex() {
		final seriesPlaylist = _seriesPlaylist;
		if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
			// For non-series content, just advance to next index
			if (widget.playlist != null && _currentIndex + 1 < widget.playlist!.length) {
				return _currentIndex + 1;
			}
			return -1;
		}

		// Find current episode in the sorted allEpisodes list
		final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
			(episode) => episode.originalIndex == _currentIndex,
			orElse: () => seriesPlaylist.allEpisodes.first,
		);

		// Find the index of current episode in allEpisodes
		final currentEpisodeIndex = seriesPlaylist.allEpisodes.indexOf(currentEpisode);
		
		if (currentEpisodeIndex == -1 || currentEpisodeIndex + 1 >= seriesPlaylist.allEpisodes.length) {
			// No next episode found
			return -1;
		}

		// Get the next episode from the sorted list
		final nextEpisode = seriesPlaylist.allEpisodes[currentEpisodeIndex + 1];
		
		return nextEpisode.originalIndex;
	}

	/// Find the previous logical episode index
	int _findPreviousEpisodeIndex() {
		final seriesPlaylist = _seriesPlaylist;
		if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
			// For non-series content, just go to previous index
			if (_currentIndex > 0) {
				return _currentIndex - 1;
			}
			return -1;
		}

		// Find current episode in the sorted allEpisodes list
		final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
			(episode) => episode.originalIndex == _currentIndex,
			orElse: () => seriesPlaylist.allEpisodes.first,
		);

		// Find the index of current episode in allEpisodes
		final currentEpisodeIndex = seriesPlaylist.allEpisodes.indexOf(currentEpisode);
		
		if (currentEpisodeIndex <= 0) {
			// No previous episode found
			return -1;
		}

		// Get the previous episode from the sorted list
		final previousEpisode = seriesPlaylist.allEpisodes[currentEpisodeIndex - 1];
		return previousEpisode.originalIndex;
	}

	/// Check if there's a next episode available
	bool _hasNextEpisode() {
		return _findNextEpisodeIndex() != -1;
	}

	/// Check if there's a previous episode available
	bool _hasPreviousEpisode() {
		return _findPreviousEpisodeIndex() != -1;
	}

	/// Navigate to next episode
	Future<void> _goToNextEpisode() async {
		final nextIndex = _findNextEpisodeIndex();
		if (nextIndex != -1) {
			// Mark this as a manual episode selection
			_isManualEpisodeSelection = true;
			_allowResumeForManualSelection = false; // Don't allow resuming for next/previous navigation
			// Reset the flag after 30 seconds to allow position saving
			_manualSelectionResetTimer?.cancel();
			_manualSelectionResetTimer = Timer(const Duration(seconds: 30), () {
				_isManualEpisodeSelection = false;
				_allowResumeForManualSelection = false;
			});
			await _loadPlaylistIndex(nextIndex, autoplay: true);
		}
	}

	/// Navigate to previous episode
	Future<void> _goToPreviousEpisode() async {
		final previousIndex = _findPreviousEpisodeIndex();
		if (previousIndex != -1) {
			// Mark this as a manual episode selection
			_isManualEpisodeSelection = true;
			_allowResumeForManualSelection = false; // Don't allow resuming for next/previous navigation
			// Reset the flag after 30 seconds to allow position saving
			_manualSelectionResetTimer?.cancel();
			_manualSelectionResetTimer = Timer(const Duration(seconds: 30), () {
				_isManualEpisodeSelection = false;
				_allowResumeForManualSelection = false;
			});
			await _loadPlaylistIndex(previousIndex, autoplay: true);
		}
	}

	/// Mark the current episode as finished if it's a series
	Future<void> _markCurrentEpisodeAsFinished() async {
		final seriesPlaylist = _seriesPlaylist;
		if (seriesPlaylist != null && seriesPlaylist.isSeries && seriesPlaylist.seriesTitle != null) {
			try {
				// Find the current episode info
				if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
					final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
						(episode) => episode.originalIndex == _currentIndex,
						orElse: () => seriesPlaylist.allEpisodes.first,
					);
					
					if (currentEpisode.seriesInfo.season != null && currentEpisode.seriesInfo.episode != null) {
						await StorageService.markEpisodeAsFinished(
							seriesTitle: seriesPlaylist.seriesTitle!,
							season: currentEpisode.seriesInfo.season!,
							episode: currentEpisode.seriesInfo.episode!,
						);
					}
				}
			} catch (e) {
			}
		}
	}

	/// Check if current episode should be marked as finished (for manual seeking)
	Future<void> _checkAndMarkEpisodeAsFinished() async {
		// Only check if we're near the end of the video (within last 30 seconds)
		if (_duration > Duration.zero && _position > Duration.zero) {
			final timeRemaining = _duration - _position;
			if (timeRemaining <= const Duration(seconds: 30)) {
				await _markCurrentEpisodeAsFinished();
			}
		}
	}



	Future<void> _loadPlaylistIndex(int index, {bool autoplay = false}) async {
		if (widget.playlist == null || index < 0 || index >= widget.playlist!.length) return;
		
		await _saveResume();
		final entry = widget.playlist![index];
		_currentIndex = index;
		
		// Check if we need to unrestrict this link
		String videoUrl = entry.url;
		if (entry.restrictedLink != null && entry.apiKey != null) {
			try {
				final unrestrictResult = await DebridService.unrestrictLink(entry.apiKey!, entry.restrictedLink!);
				videoUrl = unrestrictResult['download'] ?? entry.url;
				// Update the playlist entry with the unrestricted URL
				// Note: We can't modify the const PlaylistEntry, so we'll use the unrestricted URL directly
			} catch (e) {
				if (mounted) {
					ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(
							content: Text('Failed to unrestrict video: ${e.toString()}', style: const TextStyle(color: Colors.white)),
							backgroundColor: Theme.of(context).colorScheme.error,
							duration: const Duration(seconds: 3),
						),
					);
				}
				// Fall back to the original URL
				videoUrl = entry.url;
			}
		}
		
		// Log whether we're using cached or unrestricted URL
		if (entry.restrictedLink == null) {
		}
		
		await _player.open(mk.Media(videoUrl), play: autoplay);
		// Wait for the video to load and duration to be available
		await _waitForVideoReady();
		await _maybeRestoreResume();
		// Restore audio and subtitle track preferences
		await _restoreTrackPreferences();
	}

	/// Preload episode information in the background
	Future<void> _preloadEpisodeInfo() async {
		final seriesPlaylist = _seriesPlaylist;
		
		if (seriesPlaylist != null && seriesPlaylist.isSeries) {
			// Preload episode information in the background
			seriesPlaylist.fetchEpisodeInfo().then((_) {
				// Trigger UI update to show the episode info
				if (mounted) {
					setState(() {});
				}
			}).catchError((error) {
				// Silently handle errors - this is just preloading
			});
		}
	}

	@override
	void dispose() {

		
		// Save the current state before disposing
		_saveResume();
		_hideTimer?.cancel();
		_autosaveTimer?.cancel();
		_manualSelectionResetTimer?.cancel();
		_controlsVisible.dispose();
		_seekHud.dispose();
		_verticalHud.dispose();
		_posSub?.cancel();
		_durSub?.cancel();
		_playSub?.cancel();
		_paramsSub?.cancel();
		_completedSub?.cancel();
		_player.dispose();
		// Restore system brightness when exiting the player
		try { ScreenBrightness().resetScreenBrightness(); } catch (_) {}
		WakelockPlus.disable();
		SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
		AndroidNativeDownloader.isTelevision().then((isTv) {
			if (!isTv) {
				SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
			}
		});
		super.dispose();
	}

	Timer? _autosaveTimer;

	String get _resumeKey {
		// Use a canonical key stripping volatile query parts
		final url = (widget.playlist != null && widget.playlist!.isNotEmpty && _currentIndex >= 0 && _currentIndex < widget.playlist!.length)
			? widget.playlist![_currentIndex].url
			: widget.videoUrl;
		
		final uri = Uri.tryParse(url);
		if (uri == null) {
			return widget.videoUrl;
		}
		final base = uri.replace(queryParameters: {});
		final resumeKey = base.toString();
		return resumeKey;
	}

	Future<void> _maybeRestoreResume() async {
		// If this is auto-advancing, don't restore position
		if (_isAutoAdvancing) {
			_isAutoAdvancing = false; // Reset the flag
			return;
		}
		
		// If this is a manual episode selection, only restore if we have saved progress
		if (_isManualEpisodeSelection && !_allowResumeForManualSelection) {
			// Don't reset _isManualEpisodeSelection here - let it be reset after a delay
			return;
		}
		
		// Try enhanced playback state first
		final enhancedData = await _getEnhancedPlaybackState();
		if (enhancedData != null) {
			// Wait for duration to be available before attempting position restoration
			await _waitForDuration();
			
			final posMs = (enhancedData['positionMs'] ?? 0) as int;
			final speed = (enhancedData['speed'] ?? 1.0) as double;
			final aspect = (enhancedData['aspect'] ?? 'contain') as String;
			final position = Duration(milliseconds: posMs);
			final dur = _duration;
			
			if (dur > Duration.zero && position > const Duration(seconds: 2) && position < dur * 0.9) {
				await _player.seek(position);
			}
			
			// restore speed
			if (speed != 1.0) {
				await _player.setRate(speed);
				_playbackSpeed = speed;
			}
			
			// restore aspect
			switch (aspect) {
				case 'cover':
					_aspectMode = _AspectMode.cover;
					break;
				case 'fitWidth':
					_aspectMode = _AspectMode.fitWidth;
					break;
				case 'fitHeight':
					_aspectMode = _AspectMode.fitHeight;
					break;
				case '16:9':
					_aspectMode = _AspectMode.aspect16_9;
					break;
				case '4:3':
					_aspectMode = _AspectMode.aspect4_3;
					break;
				case '21:9':
					_aspectMode = _AspectMode.aspect21_9;
					break;
				case '1:1':
					_aspectMode = _AspectMode.aspect1_1;
					break;
				case '3:2':
					_aspectMode = _AspectMode.aspect3_2;
					break;
				case '5:4':
					_aspectMode = _AspectMode.aspect5_4;
					break;
				default:
					_aspectMode = _AspectMode.contain;
			}
			return;
		}
		// Fallback to legacy resume system
		// Wait for duration to be available before attempting position restoration
		await _waitForDuration();
		final data = await StorageService.getVideoResume(_resumeKey);
		if (data == null) {
			return;
		}
		
		final posMs = (data['positionMs'] ?? 0) as int;
		final speed = (data['speed'] ?? 1.0) as double;
		final aspect = (data['aspect'] ?? 'contain') as String;
		final position = Duration(milliseconds: posMs);
		final dur = _duration;
		
		if (dur > Duration.zero && position > const Duration(seconds: 2) && position < dur * 0.9) {
			await _player.seek(position);
		}
		
		// restore speed
		if (speed != 1.0) {
			await _player.setRate(speed);
			_playbackSpeed = speed;
		}
		// restore aspect
		switch (aspect) {
			case 'cover':
				_aspectMode = _AspectMode.cover;
				break;
			case 'fitWidth':
				_aspectMode = _AspectMode.fitWidth;
				break;
			case 'fitHeight':
				_aspectMode = _AspectMode.fitHeight;
				break;
			case '16:9':
				_aspectMode = _AspectMode.aspect16_9;
				break;
			case '4:3':
				_aspectMode = _AspectMode.aspect4_3;
				break;
			case '21:9':
				_aspectMode = _AspectMode.aspect21_9;
				break;
			case '1:1':
				_aspectMode = _AspectMode.aspect1_1;
				break;
			case '3:2':
				_aspectMode = _AspectMode.aspect3_2;
				break;
			case '5:4':
				_aspectMode = _AspectMode.aspect5_4;
				break;
			default:
				_aspectMode = _AspectMode.contain;
		}
	}

	/// Get enhanced playback state for current content
	Future<Map<String, dynamic>?> _getEnhancedPlaybackState() async {
		try {
			final seriesPlaylist = _seriesPlaylist;
			if (seriesPlaylist != null && seriesPlaylist.isSeries) {
				// For series, get the current episode info
				if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
					final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
						(episode) => episode.originalIndex == _currentIndex,
						orElse: () => seriesPlaylist.allEpisodes.first,
					);
					
					if (currentEpisode.seriesInfo.season != null && currentEpisode.seriesInfo.episode != null) {
						// Only restore position for the exact same episode
						final playbackState = await StorageService.getSeriesPlaybackState(
							seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
							season: currentEpisode.seriesInfo.season!,
							episode: currentEpisode.seriesInfo.episode!,
						);
						
						return playbackState;
					}
				}
			} else {
				
				// For non-series content, check if we have a playlist
				if (widget.playlist != null && widget.playlist!.isNotEmpty) {
					// Get the current video filename for state checking
					String currentVideoFilename = '';
					if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
						final entry = widget.playlist![_currentIndex];
						currentVideoFilename = entry.title;
					}
					
					if (currentVideoFilename.isNotEmpty) {
						// Generate stable hash from filename
						final filenameHash = _generateFilenameHash(currentVideoFilename);
						
						// Try to get playback state for this specific video filename hash
						final videoState = await StorageService.getVideoPlaybackState(
							videoTitle: filenameHash, // Use filename hash as the key for specific video tracking
						);
						
						if (videoState != null) {
							return videoState;
						}
					}
				}
				
				// Fallback to collection-based state (legacy behavior)
				final videoTitle = widget.title.isNotEmpty ? widget.title : 'Unknown Video';
				
				final videoState = await StorageService.getVideoPlaybackState(
					videoTitle: videoTitle,
				);
				
				return videoState;
			}
		} catch (e) {
		}
		return null;
	}

	Future<void> _saveResume({bool debounced = false}) async {
		if (!_isReady) {
			return;
		}
		
		// If this is a manual episode selection and it's been less than 30 seconds, skip saving
		// This gives the user time to seek to where they want
		if (_isManualEpisodeSelection && debounced) {
			return;
		}
		
		final pos = _position;
		final dur = _duration;
		if (dur <= Duration.zero) {
			return;
		}
		
		final aspectStr = () {
			switch (_aspectMode) {
				case _AspectMode.cover:
					return 'cover';
				case _AspectMode.fitWidth:
					return 'fitWidth';
				case _AspectMode.fitHeight:
					return 'fitHeight';
				case _AspectMode.aspect16_9:
					return '16:9';
				case _AspectMode.aspect4_3:
					return '4:3';
				case _AspectMode.aspect21_9:
					return '21:9';
				case _AspectMode.aspect1_1:
					return '1:1';
				case _AspectMode.aspect3_2:
					return '3:2';
				case _AspectMode.aspect5_4:
					return '5:4';
				case _AspectMode.contain:
				default:
					return 'contain';
			}
		}();
		
		// Save to enhanced playback state system
		try {
			final seriesPlaylist = _seriesPlaylist;
			if (seriesPlaylist != null && seriesPlaylist.isSeries) {
				// For series content
				if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
					final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
						(episode) => episode.originalIndex == _currentIndex,
						orElse: () => seriesPlaylist.allEpisodes.first,
					);
					
					if (currentEpisode.seriesInfo.season != null && currentEpisode.seriesInfo.episode != null) {
						await StorageService.saveSeriesPlaybackState(
							seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
							season: currentEpisode.seriesInfo.season!,
							episode: currentEpisode.seriesInfo.episode!,
							positionMs: pos.inMilliseconds,
							durationMs: dur.inMilliseconds,
							speed: _playbackSpeed,
							aspect: aspectStr,
						);
					}
				}
			} else {
				// For non-series content
				if (widget.playlist != null && widget.playlist!.isNotEmpty) {
					// Get the current video filename and entry for state saving
					String currentVideoFilename = '';
					PlaylistEntry? currentEntry;
					if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
						currentEntry = widget.playlist![_currentIndex];
						currentVideoFilename = currentEntry.title;
					}
					
					if (currentVideoFilename.isNotEmpty && currentEntry != null) {
						// Generate stable hash from filename
						final filenameHash = _generateFilenameHash(currentVideoFilename);
						
						// Get the current video URL for the videoUrl field (still needed for some functionality)
						String currentVideoUrl = '';
						if (currentEntry.url.isNotEmpty) {
							currentVideoUrl = currentEntry.url;
						} else if (currentEntry.restrictedLink != null && currentEntry.apiKey != null) {
							try {
								final unrestrictResult = await DebridService.unrestrictLink(currentEntry.apiKey!, currentEntry.restrictedLink!);
								currentVideoUrl = unrestrictResult['download'] ?? '';
							} catch (e) {
							}
						}
						
						// Save state for this specific video filename hash
						await StorageService.saveVideoPlaybackState(
							videoTitle: filenameHash, // Use filename hash as the key for specific video tracking
							videoUrl: currentVideoUrl,
							positionMs: pos.inMilliseconds,
							durationMs: dur.inMilliseconds,
							speed: _playbackSpeed,
							aspect: aspectStr,
						);
					}
				} else {
					// Single video file (no playlist)
					final currentUrl = widget.videoUrl;
					final videoTitle = widget.title.isNotEmpty ? widget.title : 'Unknown Video';
					
					await StorageService.saveVideoPlaybackState(
						videoTitle: videoTitle,
						videoUrl: currentUrl,
						positionMs: pos.inMilliseconds,
						durationMs: dur.inMilliseconds,
						speed: _playbackSpeed,
						aspect: aspectStr,
					);
				}
			}
		} catch (e) {
		}
		
		// Also save to legacy system for backward compatibility
		await StorageService.upsertVideoResume(_resumeKey, {
			'positionMs': pos.inMilliseconds,
			'speed': _playbackSpeed,
			'aspect': aspectStr,
			'durationMs': dur.inMilliseconds,
			'updatedAt': DateTime.now().millisecondsSinceEpoch,
		});
	}

	void _scheduleAutoHide() {
		_hideTimer?.cancel();
		_hideTimer = Timer(const Duration(seconds: 3), () {
			_controlsVisible.value = false;
		});
	}

	void _toggleControls() {
		_controlsVisible.value = !_controlsVisible.value;
		if (_controlsVisible.value) {
			_scheduleAutoHide();
		}
	}

	Future<void> _handleDoubleTap(TapDownDetails details) async {
		final box = context.findRenderObject() as RenderBox?;
		if (box == null) return;
		final size = box.size;
		final localPos = details.localPosition;
		// Avoid edge conflicts with system back gesture by requiring a margin
		const edgeGuard = 24.0;
		if (localPos.dx < edgeGuard || localPos.dx > size.width - edgeGuard) return;
		// If controls visible, ignore double-taps near top/bottom bars to not clash with buttons/slider
		if (_controlsVisible.value) {
			const topBar = 72.0;
			const bottomBar = 72.0;
			if (localPos.dy < topBar || localPos.dy > size.height - bottomBar) return;
		}
		final isLeft = localPos.dx < size.width / 2;
		final delta = const Duration(seconds: 10);
		final target = _position + (isLeft ? -delta : delta);
		final minPos = Duration.zero;
		final maxPos = _duration;
		final clamped = target < minPos ? minPos : (target > maxPos ? maxPos : target);
		await _player.seek(clamped);
		_ripple = _DoubleTapRipple(
			center: localPos,
			icon: isLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
		);
		setState(() {});
		Future.delayed(const Duration(milliseconds: 450), () {
			if (mounted) setState(() =>
			 _ripple = null);
		});
	}

	void _onPanStart(DragStartDetails details) async {
		// If controls are visible, ignore pans that begin within top/bottom bars so buttons and slider work unaffected
		_panIgnore = false;
		if (_controlsVisible.value) {
			final box = context.findRenderObject() as RenderBox?;
			if (box != null) {
				final size = box.size;
				const topBar = 72.0;
				const bottomBar = 72.0;
				final dy = details.localPosition.dy;
				if (dy < topBar || dy > size.height - bottomBar) {
					_panIgnore = true;
					return;
				}
			}
		}
		_gestureStartPosition = details.localPosition;
		_gestureStartVideoPosition = _position;
		_gestureStartVolume = (_player.state.volume / 100.0).clamp(0.0, 1.0);
		try {
			_gestureStartBrightness = await ScreenBrightness().current;
		} catch (_) {
			_gestureStartBrightness = 0.5;
		}
		_mode = _GestureMode.none;
		_verticalHud.value = null;
		_seekHud.value = null;
	}

	void _onPanUpdate(DragUpdateDetails details) {
		if (_panIgnore) return;
		final dx = details.localPosition.dx - _gestureStartPosition.dx;
		final dy = details.localPosition.dy - _gestureStartPosition.dy;
		final absDx = dx.abs();
		final absDy = dy.abs();
		final size = (context.findRenderObject() as RenderBox).size;

		// Decide mode on first significant movement
		if (_mode == _GestureMode.none) {
			if (absDx > 12 && absDx > absDy) {
				_mode = _GestureMode.seek;
			} else if (absDy > 12) {
				final isLeftHalf = _gestureStartPosition.dx < size.width / 2;
				_mode = isLeftHalf ? _GestureMode.brightness : _GestureMode.volume;
			}
		}

		if (_mode == _GestureMode.seek) {
			final duration = _duration;
			if (duration == Duration.zero) return;
			// Map horizontal delta to seconds, proportional to width
			final totalSeconds = duration.inSeconds.toDouble();
			final seekSeconds = (dx / size.width) * math.min(120.0, totalSeconds);
			var newPos = _gestureStartVideoPosition + Duration(seconds: seekSeconds.round());
			if (newPos < Duration.zero) newPos = Duration.zero;
			if (newPos > duration) newPos = duration;
			_seekHud.value = _SeekHudState(
				target: newPos,
				base: _position,
				isForward: newPos >= _position,
			);
		} else if (_mode == _GestureMode.volume) {
			var newVol = (_gestureStartVolume - dy / size.height).clamp(0.0, 1.0);
			_player.setVolume((newVol * 100).clamp(0.0, 100.0));
			_verticalHud.value = _VerticalHudState(kind: _VerticalKind.volume, value: newVol);
		} else if (_mode == _GestureMode.brightness) {
			var newBright = (_gestureStartBrightness - dy / size.height).clamp(0.0, 1.0);
			ScreenBrightness().setScreenBrightness(newBright);
			_verticalHud.value = _VerticalHudState(kind: _VerticalKind.brightness, value: newBright);
		}
	}

	void _onPanEnd(DragEndDetails details) {
		if (_panIgnore) return;
		if (_mode == _GestureMode.seek && _seekHud.value != null) {
			_player.seek(_seekHud.value!.target);
		}
		_mode = _GestureMode.none;
		Future.delayed(const Duration(milliseconds: 250), () {
			_seekHud.value = null;
			_verticalHud.value = null;
		});
	}

	String _format(Duration d) {
		final sign = d.isNegative ? '-' : '';
		final abs = d.abs();
		final h = abs.inHours;
		final m = abs.inMinutes % 60;
		final s = abs.inSeconds % 60;
		if (h > 0) {
			return '$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
		}
		return '$sign${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
	}

	void _togglePlay() {
		if (!_isReady) return;
		if (_isPlaying) {
			_player.pause();
		} else {
			_player.play();
		}
		_scheduleAutoHide();
	}

	void _cycleAspectMode() {
		_AspectMode newMode;
		String modeName;
		IconData modeIcon;
		
		switch (_aspectMode) {
			case _AspectMode.contain:
				newMode = _AspectMode.cover;
				modeName = 'Cover';
				modeIcon = Icons.crop_free_rounded;
				break;
			case _AspectMode.cover:
				newMode = _AspectMode.fitWidth;
				modeName = 'Fit Width';
				modeIcon = Icons.fit_screen_rounded;
				break;
			case _AspectMode.fitWidth:
				newMode = _AspectMode.fitHeight;
				modeName = 'Fit Height';
				modeIcon = Icons.fit_screen_rounded;
				break;
			case _AspectMode.fitHeight:
				newMode = _AspectMode.aspect16_9;
				modeName = '16:9';
				modeIcon = Icons.aspect_ratio_rounded;
				break;
			case _AspectMode.aspect16_9:
				newMode = _AspectMode.aspect4_3;
				modeName = '4:3';
				modeIcon = Icons.aspect_ratio_rounded;
				break;
			case _AspectMode.aspect4_3:
				newMode = _AspectMode.aspect21_9;
				modeName = '21:9';
				modeIcon = Icons.aspect_ratio_rounded;
				break;
			case _AspectMode.aspect21_9:
				newMode = _AspectMode.aspect1_1;
				modeName = '1:1';
				modeIcon = Icons.crop_square_rounded;
				break;
			case _AspectMode.aspect1_1:
				newMode = _AspectMode.aspect3_2;
				modeName = '3:2';
				modeIcon = Icons.aspect_ratio_rounded;
				break;
			case _AspectMode.aspect3_2:
				newMode = _AspectMode.aspect5_4;
				modeName = '5:4';
				modeIcon = Icons.aspect_ratio_rounded;
				break;
			case _AspectMode.aspect5_4:
				newMode = _AspectMode.contain;
				modeName = 'Contain';
				modeIcon = Icons.crop_free_rounded;
				break;
		}
		
		setState(() {
			_aspectMode = newMode;
		});
		
		// Show elegant HUD feedback
		_aspectRatioHud.value = _AspectRatioHudState(
			aspectRatio: modeName,
			icon: modeIcon,
		);
		
		// Auto-hide the HUD after 1.5 seconds
		Future.delayed(const Duration(milliseconds: 1500), () {
			_aspectRatioHud.value = null;
		});
		
		_scheduleAutoHide();
		_saveResume();
	}

	void _changeSpeed() {
		const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
		final idx = speeds.indexOf(_playbackSpeed);
		final next = speeds[(idx + 1) % speeds.length];
		_player.setRate(next);
		setState(() => _playbackSpeed = next);
		_scheduleAutoHide();
		_saveResume();
	}

	Future<void> _toggleOrientation() async {
		if (_landscapeLocked) {
			await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
			_landscapeLocked = false;
		} else {
			await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
				DeviceOrientation.landscapeLeft,
				DeviceOrientation.landscapeRight,
			]);
			_landscapeLocked = true;
		}
		SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
		if (mounted) setState(() {});
		_scheduleAutoHide();
	}

	BoxFit _currentFit() {
		switch (_aspectMode) {
			case _AspectMode.contain:
				return BoxFit.contain;
			case _AspectMode.cover:
				return BoxFit.cover;
			case _AspectMode.fitWidth:
				return BoxFit.fitWidth;
			case _AspectMode.fitHeight:
				return BoxFit.fitHeight;
			case _AspectMode.aspect16_9:
			case _AspectMode.aspect4_3:
			case _AspectMode.aspect21_9:
			case _AspectMode.aspect1_1:
			case _AspectMode.aspect3_2:
			case _AspectMode.aspect5_4:
				return BoxFit.cover; // We'll handle custom aspect ratios in the widget
		}
	}
	
	// Build video with custom aspect ratio
	Widget _buildCustomAspectRatioVideo() {
		final aspectRatio = _getCustomAspectRatio();
		if (aspectRatio == null) {
			return FittedBox(
				fit: _currentFit(),
				child: SizedBox(
					width: 1920,
					height: 1080,
					child: mkv.Video(controller: _videoController, controls: null),
				),
			);
		}
		
		return Center(
			child: AspectRatio(
				aspectRatio: aspectRatio,
				child: ClipRect(
					child: FittedBox(
						fit: BoxFit.cover,
						child: SizedBox(
							width: 1920,
							height: 1080,
							child: mkv.Video(controller: _videoController, controls: null),
						),
					),
				),
			),
		);
	}
	
	// Get the custom aspect ratio for specific modes
	double? _getCustomAspectRatio() {
		switch (_aspectMode) {
			case _AspectMode.aspect16_9:
				return 16.0 / 9.0;
			case _AspectMode.aspect4_3:
				return 4.0 / 3.0;
			case _AspectMode.aspect21_9:
				return 21.0 / 9.0;
			case _AspectMode.aspect1_1:
				return 1.0;
			case _AspectMode.aspect3_2:
				return 3.0 / 2.0;
			case _AspectMode.aspect5_4:
				return 5.0 / 4.0;
			default:
				return null;
		}
	}

	Future<void> _showPlaylistSheet(BuildContext context) async {
		if (widget.playlist == null || widget.playlist!.isEmpty) return;
		
		final seriesPlaylist = _seriesPlaylist;
		
		await showModalBottomSheet(
			context: context,
			backgroundColor: const Color(0xFF0F0F0F),
			isScrollControlled: true,
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
			),
			builder: (context) {
				return SafeArea(
					top: false,
					child: Container(
						decoration: const BoxDecoration(
							gradient: LinearGradient(
								begin: Alignment.topCenter,
								end: Alignment.bottomCenter,
								colors: [
									Color(0xFF1A1A1A),
									Color(0xFF0F0F0F),
								],
							),
						),
						child: seriesPlaylist != null && seriesPlaylist.isSeries
							? SeriesBrowser(
								seriesPlaylist: seriesPlaylist,
								currentEpisodeIndex: _currentIndex,
								onEpisodeSelected: (season, episode) async {
									// Find the original index in the PlaylistEntry array
									final originalIndex = seriesPlaylist.findOriginalIndexBySeasonEpisode(season, episode);
									if (originalIndex != -1) {
										// Check if this episode has saved progress
										final playbackState = await StorageService.getSeriesPlaybackState(
											seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
											season: season,
											episode: episode,
										);
										
										// Allow resuming if the episode has saved progress
										_allowResumeForManualSelection = playbackState != null;
										
										// Mark this as a manual episode selection
										_isManualEpisodeSelection = true;
										// Reset the flag after 30 seconds to allow position saving
										_manualSelectionResetTimer?.cancel();
										_manualSelectionResetTimer = Timer(const Duration(seconds: 30), () {
											_isManualEpisodeSelection = false;
											_allowResumeForManualSelection = false;
										});
										await _loadPlaylistIndex(originalIndex, autoplay: true);
									} else {
                                        // Show error message to user
										if (mounted) {
											ScaffoldMessenger.of(context).showSnackBar(
												SnackBar(
													content: Text('Failed to find episode S${season}E${episode}', style: const TextStyle(color: Colors.white)),
													backgroundColor: const Color(0xFFEF4444),
													duration: const Duration(seconds: 3),
												),
											);
										}
									}
								},
							  )
							: _buildSimplePlaylist(),
					),
				);
			},
		);
	}

	Widget _buildSimplePlaylist() {
		return Container(
			height: MediaQuery.of(context).size.height * 0.85,
			padding: const EdgeInsets.all(20),
			child: Column(
				mainAxisSize: MainAxisSize.min,
				children: [
					// Netflix-style header
					Row(
						children: [
							Container(
								padding: const EdgeInsets.all(8),
								decoration: BoxDecoration(
									color: const Color(0xFFE50914).withOpacity(0.2),
									borderRadius: BorderRadius.circular(8),
								),
								child: const Icon(
									Icons.playlist_play_rounded,
									color: Color(0xFFE50914),
									size: 20,
								),
							),
							const SizedBox(width: 12),
							const Text(
								'All Files',
								style: TextStyle(
									color: Colors.white,
									fontWeight: FontWeight.w700,
									fontSize: 18,
									letterSpacing: 0.5,
								),
							),
							const Spacer(),
							Container(
								decoration: BoxDecoration(
									color: Colors.black.withOpacity(0.4),
									borderRadius: BorderRadius.circular(8),
									border: Border.all(
										color: Colors.white.withOpacity(0.2),
										width: 1,
									),
								),
								child: IconButton(
									icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
									onPressed: () => Navigator.of(context).pop(),
									style: IconButton.styleFrom(
										padding: const EdgeInsets.all(8),
										minimumSize: const Size(36, 36),
									),
								),
							),
						],
					),
					const SizedBox(height: 20),
					Flexible(
						child: FutureBuilder<Set<int>>(
							future: _getFinishedEpisodesForSimplePlaylist(),
							builder: (context, snapshot) {
								final finishedEpisodes = snapshot.data ?? <int>{};
								
								return ListView.builder(
									shrinkWrap: true,
									itemCount: widget.playlist!.length,
									itemBuilder: (context, index) {
										final entry = widget.playlist![index];
										final active = index == _currentIndex;
										final isFinished = finishedEpisodes.contains(index);
										
										return Container(
											margin: const EdgeInsets.only(bottom: 12),
											decoration: BoxDecoration(
												color: active 
													? const Color(0xFFE50914).withOpacity(0.2)
													: const Color(0xFF1A1A1A).withOpacity(0.8),
												borderRadius: BorderRadius.circular(12),
												border: Border.all(
													color: active 
														? const Color(0xFFE50914)
														: Colors.white.withOpacity(0.1),
													width: 1,
												),
												boxShadow: [
													BoxShadow(
														color: Colors.black.withOpacity(0.2),
														blurRadius: 8,
														offset: const Offset(0, 2),
													),
												],
											),
											child: Material(
												color: Colors.transparent,
												child: InkWell(
													onTap: () async {
														Navigator.of(context).pop();
														// Mark this as a manual episode selection
														_isManualEpisodeSelection = true;
														_allowResumeForManualSelection = false; // Don't allow resuming for simple playlist navigation
														// Reset the flag after 30 seconds to allow position saving
														_manualSelectionResetTimer?.cancel();
														_manualSelectionResetTimer = Timer(const Duration(seconds: 30), () {
															_isManualEpisodeSelection = false;
															_allowResumeForManualSelection = false;
														});
														await _loadPlaylistIndex(index, autoplay: true);
													},
													borderRadius: BorderRadius.circular(12),
													child: Padding(
														padding: const EdgeInsets.all(16),
														child: Row(
															children: [
																Container(
																	padding: const EdgeInsets.all(8),
																	decoration: BoxDecoration(
																		color: active 
																			? const Color(0xFFE50914)
																			: Colors.white.withOpacity(0.1),
																		borderRadius: BorderRadius.circular(8),
																	),
																	child: Icon(
																		active ? Icons.play_arrow_rounded : Icons.movie_rounded,
																		color: active 
																			? Colors.white
																			: Colors.white.withOpacity(0.7),
																		size: 20,
																	),
																),
																const SizedBox(width: 16),
																Expanded(
																	child: Column(
																		crossAxisAlignment: CrossAxisAlignment.start,
																		children: [
																			Text(
																				entry.title,
																				maxLines: 2,
																				overflow: TextOverflow.ellipsis,
																				style: TextStyle(
																					color: active 
																						? Colors.white
																						: Colors.white.withOpacity(0.9),
																					fontWeight: active 
																						? FontWeight.w600
																						: FontWeight.w400,
																					fontSize: 14,
																					decoration: isFinished ? TextDecoration.lineThrough : null,
																				),
																			),
																			if (active) ...[
																				const SizedBox(height: 4),
																				Container(
																					padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
																					decoration: BoxDecoration(
																						color: const Color(0xFFE50914),
																						borderRadius: BorderRadius.circular(8),
																					),
																					child: const Text(
																						'Now Playing',
																						style: TextStyle(
																							color: Colors.white,
																							fontSize: 10,
																							fontWeight: FontWeight.w600,
																						),
																					),
																				),
																			],
																		],
																	),
																),
																if (isFinished)
																	Container(
																		padding: const EdgeInsets.all(6),
																		decoration: BoxDecoration(
																			color: const Color(0xFF059669).withOpacity(0.2),
																			borderRadius: BorderRadius.circular(6),
																		),
																		child: const Icon(
																			Icons.check_circle,
																			color: Color(0xFF059669),
																			size: 16,
																		),
																	),
															],
														),
													),
												),
											),
										);
									},
								);
							},
						),
					),
				],
			),
		);
	}

	/// Get finished episodes for simple playlist (non-series content)
	Future<Set<int>> _getFinishedEpisodesForSimplePlaylist() async {
		// For simple playlists, we don't track finished episodes
		// This is mainly for series content
		return <int>{};
	}

	@override
	Widget build(BuildContext context) {
		final isReady = _isReady;
		final duration = _duration;
		final pos = _position;
		// final remaining = (duration - pos).clamp(Duration.zero, duration); // not used

		return Scaffold(
			backgroundColor: Colors.black,
			body: SafeArea(
				left: false,
				top: false,
				right: false,
				bottom: false,
									child: Focus(
						autofocus: true,
						onKey: (node, event) {
							if (event is! RawKeyDownEvent) return KeyEventResult.ignored;
							final key = event.logicalKey;
							
							// A -> Aspect ratio
							if (key == LogicalKeyboardKey.keyA) {
								_cycleAspectMode();
								return KeyEventResult.handled;
							}
							
							// Space -> Pause resume
							if (key == LogicalKeyboardKey.space) {
								_togglePlay();
								return KeyEventResult.handled;
							}
							
							// Up/Down arrow -> Volume
							if (key == LogicalKeyboardKey.arrowUp) {
								// Show controls first
								_controlsVisible.value = true;
								_scheduleAutoHide();
								
								// Increase volume
								final currentVolume = (_player.state.volume / 100.0).clamp(0.0, 1.0);
								final newVolume = (currentVolume + 0.1).clamp(0.0, 1.0);
								_player.setVolume((newVolume * 100).clamp(0.0, 100.0));
								
								// Show volume HUD
								_verticalHud.value = _VerticalHudState(kind: _VerticalKind.volume, value: newVolume);
								Future.delayed(const Duration(milliseconds: 250), () {
									_verticalHud.value = null;
								});
								
								return KeyEventResult.handled;
							}
							
							if (key == LogicalKeyboardKey.arrowDown) {
								// Show controls first
								_controlsVisible.value = true;
								_scheduleAutoHide();
								
								// Decrease volume
								final currentVolume = (_player.state.volume / 100.0).clamp(0.0, 1.0);
								final newVolume = (currentVolume - 0.1).clamp(0.0, 1.0);
								_player.setVolume((newVolume * 100).clamp(0.0, 100.0));
								
								// Show volume HUD
								_verticalHud.value = _VerticalHudState(kind: _VerticalKind.volume, value: newVolume);
								Future.delayed(const Duration(milliseconds: 250), () {
									_verticalHud.value = null;
								});
								
								return KeyEventResult.handled;
							}
							

							
							// Center/Enter toggles play or shows controls
							if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
								if (_controlsVisible.value) {
									_togglePlay();
								} else {
									_toggleControls();
								}
								return KeyEventResult.handled;
							}

							// DPAD left/right seek 10s
							if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
								final candidate = _position - const Duration(seconds: 10);
								final newPos = candidate < Duration.zero ? Duration.zero : (candidate > _duration ? _duration : candidate);
								_player.seek(newPos);
								_controlsVisible.value = true;
								_scheduleAutoHide();
								return KeyEventResult.handled;
							}
							if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
								final candidate = _position + const Duration(seconds: 10);
								final newPos = candidate < Duration.zero ? Duration.zero : (candidate > _duration ? _duration : candidate);
								_player.seek(newPos);
								_controlsVisible.value = true;
								_scheduleAutoHide();
								return KeyEventResult.handled;
							}

							// Media play/pause keys
							if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.mediaPlay || key == LogicalKeyboardKey.mediaPause) {
								_togglePlay();
								return KeyEventResult.handled;
							}

							// Next/Previous episode navigation
							if (key == LogicalKeyboardKey.mediaSkipForward) {
								if (_hasNextEpisode()) {
									_goToNextEpisode();
									return KeyEventResult.handled;
								}
							}
							if (key == LogicalKeyboardKey.mediaSkipBackward) {
								if (_hasPreviousEpisode()) {
									_goToPreviousEpisode();
									return KeyEventResult.handled;
								}
							}
							return KeyEventResult.ignored;
						},
					child: Stack(
						fit: StackFit.expand,
						children: [
							// Video texture (media_kit renderer)
							if (isReady)
								_getCustomAspectRatio() != null
									? _buildCustomAspectRatioVideo()
									: FittedBox(
										fit: _currentFit(),
										child: SizedBox(
											width: 1920,
											height: 1080,
											child: mkv.Video(controller: _videoController, controls: null),
										),
									)
							else
								const Center(child: CircularProgressIndicator(color: Colors.white)),
							// Double-tap ripple
							if (_ripple != null)
								IgnorePointer(child: CustomPaint(painter: _DoubleTapRipplePainter(_ripple!))),
							// HUDs
							ValueListenableBuilder<_SeekHudState?>(
								valueListenable: _seekHud,
								builder: (context, hud, _) {
									return IgnorePointer(
										ignoring: true,
										child: AnimatedOpacity(
											opacity: hud == null ? 0 : 1,
											duration: const Duration(milliseconds: 120),
											child: Center(
												child: hud == null
													? const SizedBox.shrink()
													: _SeekHud(hud: hud, format: _format),
											),
										),
									);
								},
							),
							ValueListenableBuilder<_VerticalHudState?>(
								valueListenable: _verticalHud,
								builder: (context, hud, _) {
									return IgnorePointer(
										ignoring: true,
										child: AnimatedOpacity(
											opacity: hud == null ? 0 : 1,
											duration: const Duration(milliseconds: 120),
											child: Align(
												alignment: Alignment.centerRight,
												child: Padding(
													padding: const EdgeInsets.only(right: 24),
													child: hud == null ? const SizedBox.shrink() : _VerticalHud(hud: hud),
												),
											),
										),
									);
								},
							),
							ValueListenableBuilder<_AspectRatioHudState?>(
								valueListenable: _aspectRatioHud,
								builder: (context, hud, _) {
									return IgnorePointer(
										ignoring: true,
										child: AnimatedOpacity(
											opacity: hud == null ? 0 : 1,
											duration: const Duration(milliseconds: 200),
											child: Align(
												alignment: Alignment.topRight,
												child: Padding(
													padding: const EdgeInsets.only(top: 80, right: 24),
													child: hud == null ? const SizedBox.shrink() : _AspectRatioHud(hud: hud),
												),
											),
										),
									);
								},
							),
							// Full-screen gesture layer (placed below controls)
							GestureDetector(
								behavior: HitTestBehavior.translucent,
								onTapDown: (d) => _lastTapLocal = d.localPosition,
								onTap: () {
									final box = context.findRenderObject() as RenderBox?;
									if (box == null) return;
									final size = box.size;
									final pos = _lastTapLocal ?? Offset.zero;
									if (_shouldToggleForTap(pos, size, controlsVisible: _controlsVisible.value)) {
										_toggleControls();
									}
								},
								onDoubleTapDown: _handleDoubleTap,
								onPanStart: _onPanStart,
								onPanUpdate: _onPanUpdate,
								onPanEnd: _onPanEnd,
							),
							// Controls overlay (shown only when ready)
							if (isReady)
							ValueListenableBuilder<bool>(
								valueListenable: _controlsVisible,
								builder: (context, visible, _) {
									return AnimatedOpacity(
										opacity: visible ? 1 : 0,
										duration: const Duration(milliseconds: 150),
										child: IgnorePointer(
											ignoring: !visible,
											child: _Controls(
												title: _getCurrentEpisodeTitle(),
												subtitle: _getCurrentEpisodeSubtitle(),
												enhancedMetadata: _getEnhancedMetadata(),
												duration: duration,
												position: pos,
												isPlaying: _isPlaying,
												isReady: isReady,
												onPlayPause: _togglePlay,
												onBack: () => Navigator.of(context).pop(),
												onAspect: _cycleAspectMode,
												onSpeed: _changeSpeed,
												speed: _playbackSpeed,
												aspectMode: _aspectMode,
												isLandscape: _landscapeLocked,
												onRotate: _toggleOrientation,
												hasPlaylist: widget.playlist != null && widget.playlist!.isNotEmpty,
												onShowPlaylist: () => _showPlaylistSheet(context),
												onShowTracks: () => _showTracksSheet(context),
												onSeekBarChangedStart: () {
													_isSeekingWithSlider = true;
												},
												onSeekBarChanged: (v) {
													final newPos = duration * v;
													_player.seek(newPos);
												},
												onSeekBarChangeEnd: () {
													_isSeekingWithSlider = false;
													_scheduleAutoHide();
												},
												onNext: _goToNextEpisode,
												onPrevious: _goToPreviousEpisode,
												hasNext: _hasNextEpisode(),
												hasPrevious: _hasPreviousEpisode(),
												
											),
										),
									);
								},
							),
						],
					),
				),
			),
		);
	}



				
		





	

	










	




	
















}

class _Controls extends StatelessWidget {
	final String title;
	final String? subtitle;
	final Map<String, dynamic> enhancedMetadata;
	final Duration duration;
	final Duration position;
	final bool isPlaying;
	final bool isReady;
	final VoidCallback onPlayPause;
	final VoidCallback onBack;
	final VoidCallback onAspect;
	final VoidCallback onSpeed;
	final double speed;
	final _AspectMode aspectMode;
	final bool isLandscape;
	final VoidCallback onRotate;
	final VoidCallback onShowPlaylist;
	final VoidCallback onShowTracks;
	final bool hasPlaylist;
	final VoidCallback onSeekBarChangedStart;
	final ValueChanged<double> onSeekBarChanged;
	final VoidCallback onSeekBarChangeEnd;
	final VoidCallback? onNext;
	final VoidCallback? onPrevious;
	final bool hasNext;
	final bool hasPrevious;


	const _Controls({
		required this.title,
		required this.subtitle,
		required this.enhancedMetadata,
		required this.duration,
		required this.position,
		required this.isPlaying,
		required this.isReady,
		required this.onPlayPause,
		required this.onBack,
		required this.onAspect,
		required this.onSpeed,
		required this.speed,
		required this.aspectMode,
		required this.isLandscape,
		required this.onRotate,
		required this.onShowPlaylist,
		required this.onShowTracks,
		required this.hasPlaylist,
		required this.onSeekBarChangedStart,
		required this.onSeekBarChanged,
		required this.onSeekBarChangeEnd,
			this.onNext,
	this.onPrevious,
	this.hasNext = false,
	this.hasPrevious = false,
	});
	
	String _getAspectRatioName() {
		switch (aspectMode) {
			case _AspectMode.contain:
				return 'Contain';
			case _AspectMode.cover:
				return 'Cover';
			case _AspectMode.fitWidth:
				return 'Fit Width';
			case _AspectMode.fitHeight:
				return 'Fit Height';
			case _AspectMode.aspect16_9:
				return '16:9';
			case _AspectMode.aspect4_3:
				return '4:3';
			case _AspectMode.aspect21_9:
				return '21:9';
			case _AspectMode.aspect1_1:
				return '1:1';
			case _AspectMode.aspect3_2:
				return '3:2';
			case _AspectMode.aspect5_4:
				return '5:4';
		}
	}

	String _format(Duration d) {
		final sign = d.isNegative ? '-' : '';
		final abs = d.abs();
		final h = abs.inHours;
		final m = abs.inMinutes % 60;
		final s = abs.inSeconds % 60;
		if (h > 0) {
			return '$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
		}
		return '$sign${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
	}

	// Simple rating badge for top-right
	Widget _buildMetadataRow(Map<String, dynamic> metadata) {
		// Only show rating
		if (metadata['rating'] == null || metadata['rating'] <= 0) {
			return const SizedBox.shrink();
		}
		
		return Container(
			padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
			decoration: BoxDecoration(
				color: Colors.black.withOpacity(0.7),
				borderRadius: BorderRadius.circular(16),
				border: Border.all(
					color: Colors.white.withOpacity(0.2),
					width: 1,
				),
			),
			child: Row(
				mainAxisSize: MainAxisSize.min,
				children: [
					const Icon(
						Icons.star_rounded,
						color: Colors.amber,
						size: 16,
					),
					const SizedBox(width: 4),
					Text(
						metadata['rating'].toStringAsFixed(1),
						style: const TextStyle(
							color: Colors.white,
							fontSize: 14,
							fontWeight: FontWeight.w600,
						),
					),
				],
			),
		);
	}
	


	@override
	Widget build(BuildContext context) {
		final total = duration.inMilliseconds <= 0 ? const Duration(seconds: 1) : duration;
		final progress = (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

		return Stack(
			children: [
				// Non-interactive gradient overlay
				Positioned.fill(
					child: IgnorePointer(
						ignoring: true,
						child: Container(
							decoration: const BoxDecoration(
								gradient: LinearGradient(
									begin: Alignment.topCenter,
									end: Alignment.bottomCenter,
									colors: [
										Color(0x80000000),
										Color(0x26000000),
										Color(0x80000000),
									],
								),
							),
						),
					),
				),
				// Metadata overlay at the very top-right
				if (enhancedMetadata.isNotEmpty)
					Positioned(
						top: 20,
						right: 20,
						child: _buildMetadataRow(enhancedMetadata),
					),
				// Interactive controls
				SafeArea(
				left: true,
				right: true,
				top: true,
				bottom: true,
				child: Column(
					mainAxisAlignment: MainAxisAlignment.spaceBetween,
					children: [
						// Netflix-style Top Bar - Back button and centered title when playing
						Row(
							children: [
								IconButton(
									icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
									onPressed: onBack,
								),
								Expanded(
									child: Column(
										crossAxisAlignment: CrossAxisAlignment.center,
										children: [
											// Main title
											Text(
												title,
												maxLines: 1,
												overflow: TextOverflow.ellipsis,
												style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
											),
											if (subtitle != null) ...[
												const SizedBox(height: 4),
												Text(
													subtitle!,
													maxLines: 1,
													overflow: TextOverflow.ellipsis,
													style: const TextStyle(color: Colors.white70, fontSize: 12),
												),
											],
											// Enhanced metadata row - removed from center
										],
									),
								),
								// Empty space to balance the back button
								const SizedBox(width: 48),
							],
						),



						// Netflix-style Bottom Bar with all controls
						Container(
							padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
							child: Column(
								mainAxisSize: MainAxisSize.min,
								children: [
									// Progress bar with time indicators
									Row(
										children: [
											Text(
												_format(position),
												style: const TextStyle(
													color: Colors.white,
													fontSize: 14,
													fontWeight: FontWeight.w500,
												),
											),
											const SizedBox(width: 12),
											Expanded(
												child: SliderTheme(
													data: SliderTheme.of(context).copyWith(
														trackHeight: 4,
														activeTrackColor: const Color(0xFFE50914),
														inactiveTrackColor: Colors.white.withOpacity(0.3),
														thumbShape: const RoundSliderThumbShape(
															enabledThumbRadius: 6,
															elevation: 2,
														),
														thumbColor: const Color(0xFFE50914),
														overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
													),
													child: Slider(
														min: 0,
														max: 1,
														value: progress.toDouble(),
														onChangeStart: (_) => onSeekBarChangedStart(),
														onChanged: (v) => onSeekBarChanged(v),
														onChangeEnd: (_) => onSeekBarChangeEnd(),
													),
												),
											),
											const SizedBox(width: 12),
											Text(
												_format(duration),
												style: const TextStyle(
													color: Colors.white,
													fontSize: 14,
													fontWeight: FontWeight.w500,
												),
											),
										],
									),
									
									const SizedBox(height: 16),
									
									// Netflix-style control buttons row - responsive layout
									SingleChildScrollView(
										scrollDirection: Axis.horizontal,
										child: Row(
											children: [
												// Previous episode button
												if (hasPrevious)
													_NetflixControlButton(
														icon: Icons.skip_previous_rounded,
														label: 'Previous',
														onPressed: onPrevious!,
														isCompact: true,
													),
												

												
												// Play/Pause button
												_NetflixControlButton(
													icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
													label: isPlaying ? 'Pause' : 'Play',
													onPressed: onPlayPause,
													isPrimary: true,
													isCompact: true,
												),
												
												// Next episode button
												if (hasNext)
													_NetflixControlButton(
														icon: Icons.skip_next_rounded,
														label: 'Next',
														onPressed: onNext!,
														isCompact: true,
													),
												

												
												// Speed indicator and button
												_NetflixControlButton(
													icon: Icons.speed_rounded,
													label: '${speed}x',
													onPressed: onSpeed,
													isCompact: true,
												),
												
												// Aspect ratio button
												_NetflixControlButton(
													icon: Icons.aspect_ratio_rounded,
													label: _getAspectRatioName(),
													onPressed: onAspect,
													isCompact: true,
												),
												
												// Audio & subtitles button
												_NetflixControlButton(
													icon: Icons.subtitles_rounded,
													label: 'Audio',
													onPressed: onShowTracks,
													isCompact: true,
												),
												
												// Playlist button
												if (hasPlaylist)
													_NetflixControlButton(
														icon: Icons.playlist_play_rounded,
														label: 'Episodes',
														onPressed: onShowPlaylist,
														isCompact: true,
													),
												
												// Orientation button
												_NetflixControlButton(
													icon: isLandscape 
														? Icons.fullscreen_exit_rounded 
														: Icons.fullscreen_rounded,
													label: isLandscape ? 'Exit' : 'Full',
													onPressed: onRotate,
													isCompact: true,
												),
											],
										),
									),
								],
							),
						),
											],
						),
					),
				],
			);
	}
}

class _SeekHudState {
	final Duration base;
	final Duration target;
	final bool isForward;
	_SeekHudState({required this.base, required this.target, required this.isForward});
}

class _SeekHud extends StatelessWidget {
	final _SeekHudState hud;
	final String Function(Duration) format;
	const _SeekHud({required this.hud, required this.format});
	@override
	Widget build(BuildContext context) {
		final delta = hud.target - hud.base;
		return Container(
			padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
			decoration: BoxDecoration(
				color: Colors.black.withOpacity(0.5),
				borderRadius: BorderRadius.circular(12),
			),
			child: Row(
				mainAxisSize: MainAxisSize.min,
				children: [
					Icon(
						hud.isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
						color: Colors.white,
						size: 20,
					),
					const SizedBox(width: 10),
					Text(
						'${format(hud.target)}  (${delta.isNegative ? '-' : '+'}${format(delta)})',
						style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
					),
				],
			),
		);
	}
}

enum _VerticalKind { volume, brightness }

class _VerticalHudState {
	final _VerticalKind kind;
	final double value; // 0..1
	_VerticalHudState({required this.kind, required this.value});
}

class _AspectRatioHudState {
	final String aspectRatio;
	final IconData icon;
	const _AspectRatioHudState({required this.aspectRatio, required this.icon});
}

class _VerticalHud extends StatelessWidget {
	final _VerticalHudState hud;
	const _VerticalHud({required this.hud});
	@override
	Widget build(BuildContext context) {
		final icon = hud.kind == _VerticalKind.volume ? Icons.volume_up_rounded : Icons.brightness_6_rounded;
		final label = (hud.value * 100).round();
		return Container(
			padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
			decoration: BoxDecoration(
				color: Colors.black.withOpacity(0.5),
				borderRadius: BorderRadius.circular(12),
			),
			child: Column(
				mainAxisSize: MainAxisSize.min,
				children: [
					Icon(icon, color: Colors.white),
					const SizedBox(height: 8),
					SizedBox(
						height: 80,
						width: 6,
						child: ClipRRect(
							borderRadius: BorderRadius.circular(999),
							child: LinearProgressIndicator(
								value: hud.value.clamp(0.0, 1.0),
								minHeight: 6,
								backgroundColor: Colors.white12,
								valueColor: AlwaysStoppedAnimation<Color>(
									hud.kind == _VerticalKind.volume ? Colors.lightBlueAccent : Colors.amberAccent,
								),
							),
						),
					),
					const SizedBox(height: 8),
					Text('$label%', style: const TextStyle(color: Colors.white)),
				],
			),
		);
	}
}

class _AspectRatioHud extends StatelessWidget {
	final _AspectRatioHudState hud;
	const _AspectRatioHud({required this.hud});
	
	@override
	Widget build(BuildContext context) {
		return Container(
			padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
			decoration: BoxDecoration(
				color: Colors.black.withOpacity(0.7),
				borderRadius: BorderRadius.circular(16),
				boxShadow: [
					BoxShadow(
						color: Colors.black.withOpacity(0.3),
						blurRadius: 12,
						offset: const Offset(0, 4),
					),
				],
			),
			child: Row(
				mainAxisSize: MainAxisSize.min,
				children: [
					Icon(hud.icon, color: Colors.white, size: 20),
					const SizedBox(width: 8),
					Text(
						hud.aspectRatio,
						style: const TextStyle(
							color: Colors.white,
							fontSize: 16,
							fontWeight: FontWeight.w600,
						),
					),
				],
			),
		);
	}
}

class _DoubleTapRipple {
	final Offset center;
	final IconData icon;
	_DoubleTapRipple({required this.center, required this.icon});
}

class _DoubleTapRipplePainter extends CustomPainter {
	final _DoubleTapRipple ripple;
	_DoubleTapRipplePainter(this.ripple);
	@override
	void paint(Canvas canvas, Size size) {
		final paint = Paint()..color = Colors.white.withOpacity(0.15);
		canvas.drawCircle(ripple.center, 80, paint);
		final tp = TextPainter(
			text: TextSpan(
				text: String.fromCharCode(ripple.icon.codePoint),
				style: TextStyle(
					fontSize: 48,
					fontFamily: ripple.icon.fontFamily,
					package: ripple.icon.fontPackage,
					color: Colors.white,
				),
			),
			textDirection: TextDirection.ltr,
		);
		tb(Size s) => Offset(ripple.center.dx - s.width / 2, ripple.center.dy - s.height / 2);
		tp.layout();
		tp.paint(canvas, tb(tp.size));
	}
	@override
	bool shouldRepaint(covariant _DoubleTapRipplePainter oldDelegate) => true;
}

// Helpers for tap gating
bool _isInTopArea(double dy) => dy < 72.0;
bool _isInBottomArea(double dy, double height) => dy > height - 72.0;
bool _isInCenterRegion(Offset pos, Size size) {
	final center = Offset(size.width / 2, size.height / 2);
	const radius = 120.0; // protect center play area
	return (pos - center).distance <= radius;
}

bool _shouldToggleForTap(Offset pos, Size size, {required bool controlsVisible}) {
	// If controls are hidden, allow toggling from anywhere (including center)
	if (!controlsVisible) return true;
	// If controls are visible, avoid toggling when tapping on bars or center to not fight with buttons
	if (_isInTopArea(pos.dy) || _isInBottomArea(pos.dy, size.height)) return false;
	if (_isInCenterRegion(pos, size)) return false;
	return true;
}

extension on _VideoPlayerScreenState {
	String _niceLanguage(String? codeOrTitle) {
		final v = (codeOrTitle ?? '').toLowerCase();
		const map = {
			'en': 'English','eng': 'English','hi': 'Hindi','es': 'Spanish','spa': 'Spanish','fr': 'French','fra': 'French','de': 'German','ger': 'German','ru': 'Russian','zh': 'Chinese','zho': 'Chinese','ja': 'Japanese','ko': 'Korean','it': 'Italian','pt': 'Portuguese'
		};
		return map[v] ?? '';
	}
	String _labelForTrack(dynamic t, int index) {
		final title = (t.title as String?)?.trim();
		if (title != null && title.isNotEmpty && title.toLowerCase() != 'no' && title.toLowerCase() != 'auto') {
			final langPretty = _niceLanguage(title);
			return langPretty.isNotEmpty ? langPretty : title;
		}
		final id = (t.id as String?)?.trim();
		if (id != null && id.isNotEmpty && id.toLowerCase() != 'no' && id.toLowerCase() != 'auto') {
			final langPretty = _niceLanguage(id);
			if (langPretty.isNotEmpty) return langPretty;
		}
		return 'Track ${index + 1}';
	}
	Future<void> _showTracksSheet(BuildContext context) async {
		final tracks = _player.state.tracks;
		final audios = tracks.audio.where((a) => (a.id ?? '').toLowerCase() != 'no').toList(growable: false);
		final subs = tracks.subtitle.where((s) => (s.id ?? '').toLowerCase() != 'auto' && (s.id ?? '').toLowerCase() != 'no').toList(growable: false);
		String selectedAudio = _player.state.track.audio.id ?? '';
		String selectedSub = _player.state.track.subtitle.id ?? '';

		await showModalBottomSheet(
			context: context,
			isScrollControlled: true,
			backgroundColor: const Color(0xFF0F0F0F),
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
			),
			builder: (context) {
				return SafeArea(
					top: false,
					child: FractionallySizedBox(
						heightFactor: 0.7,
						child: Padding(
							padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
							child: StatefulBuilder(
								builder: (context, setModalState) {
									return Column(
										crossAxisAlignment: CrossAxisAlignment.stretch,
										children: [
											Row(
												children: [
													Container(
														padding: const EdgeInsets.all(8),
														decoration: BoxDecoration(
															color: const Color(0xFFE50914).withOpacity(0.2),
															borderRadius: BorderRadius.circular(8),
														),
														child: const Icon(
															Icons.tune_rounded,
															color: Color(0xFFE50914),
															size: 20,
														),
													),
													const SizedBox(width: 12),
													const Text(
														'Audio & Subtitles',
														style: TextStyle(
															color: Colors.white,
															fontWeight: FontWeight.w700,
															fontSize: 18,
															letterSpacing: 0.5,
														),
													),
													const Spacer(),
													Container(
														decoration: BoxDecoration(
															color: Colors.black.withOpacity(0.4),
															borderRadius: BorderRadius.circular(8),
															border: Border.all(
																color: Colors.white.withOpacity(0.2),
																width: 1,
															),
														),
														child: IconButton(
															icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
															onPressed: () => Navigator.of(context).pop(),
															style: IconButton.styleFrom(
																padding: const EdgeInsets.all(8),
																minimumSize: const Size(36, 36),
															),
														),
													),
												],
											),
											const SizedBox(height: 20),
											Expanded(
												child: Row(
													children: [
														// Audio pane
														Expanded(
															child: Container(
																decoration: BoxDecoration(
																	color: const Color(0xFF1A1A1A),
																	borderRadius: BorderRadius.circular(16),
																	border: Border.all(
																		color: const Color(0xFF333333),
																		width: 1,
																	),
																	boxShadow: [
																		BoxShadow(
																			color: Colors.black.withOpacity(0.3),
																			blurRadius: 12,
																			offset: const Offset(0, 4),
																		),
																	],
																),
																padding: const EdgeInsets.all(16),
																child: Column(
																	crossAxisAlignment: CrossAxisAlignment.start,
																	children: [
																		Row(
																			children: [
																				Container(
																					padding: const EdgeInsets.all(6),
																					decoration: BoxDecoration(
																						color: const Color(0xFFE50914).withOpacity(0.2),
																						borderRadius: BorderRadius.circular(6),
																					),
																					child: const Icon(
																						Icons.volume_up_rounded,
																						color: Color(0xFFE50914),
																						size: 16,
																					),
																				),
																				const SizedBox(width: 8),
																				const Text(
																					'Audio',
																					style: TextStyle(
																						color: Colors.white,
																						fontWeight: FontWeight.w600,
																						fontSize: 16,
																					),
																				),
																			],
																		),
																		const SizedBox(height: 12),
																		Expanded(
																			child: ListView.builder(
																				itemCount: audios.length + 1,
																				itemBuilder: (context, index) {
																					if (index == 0) {
																						return _NetflixRadioTile(
																							value: 'auto',
																							groupValue: selectedAudio.isEmpty ? 'auto' : selectedAudio,
																							title: 'Auto',
																							onChanged: (v) async {
																								setModalState(() { selectedAudio = ''; });
																								await _player.setAudioTrack(mk.AudioTrack.auto());
																								await _persistTrackChoice('', selectedSub);
																							},
																						);
																					}
																					final a = audios[index - 1];
																					return _NetflixRadioTile(
																						value: a.id ?? '',
																						groupValue: selectedAudio.isEmpty ? 'auto' : selectedAudio,
																						title: _labelForTrack(a, index - 1),
																						onChanged: (v) async {
																							if (v == null) return;
																							setModalState(() { selectedAudio = v; });
																							await _player.setAudioTrack(a);
																							await _persistTrackChoice(v, selectedSub);
																						},
																					);
																				},
																			),
																		),
																	],
																),
															),
														),
														const SizedBox(width: 16),
														// Subtitles pane
														Expanded(
															child: Container(
																decoration: BoxDecoration(
																	color: const Color(0xFF1A1A1A),
																	borderRadius: BorderRadius.circular(16),
																	border: Border.all(
																		color: const Color(0xFF333333),
																		width: 1,
																	),
																	boxShadow: [
																		BoxShadow(
																			color: Colors.black.withOpacity(0.3),
																			blurRadius: 12,
																			offset: const Offset(0, 4),
																		),
																	],
																),
																padding: const EdgeInsets.all(16),
																child: Column(
																	crossAxisAlignment: CrossAxisAlignment.start,
																	children: [
																		Row(
																			children: [
																				Container(
																					padding: const EdgeInsets.all(6),
																					decoration: BoxDecoration(
																						color: const Color(0xFFE50914).withOpacity(0.2),
																						borderRadius: BorderRadius.circular(6),
																					),
																					child: const Icon(
																						Icons.closed_caption_rounded,
																						color: Color(0xFFE50914),
																						size: 16,
																					),
																				),
																				const SizedBox(width: 8),
																				const Text(
																					'Subtitles',
																					style: TextStyle(
																						color: Colors.white,
																						fontWeight: FontWeight.w600,
																						fontSize: 16,
																					),
																				),
																			],
																		),
																		const SizedBox(height: 12),
																		Expanded(
																			child: ListView.builder(
																				itemCount: subs.length + 1,
																				itemBuilder: (context, index) {
																					if (index == 0) {
																						return _NetflixRadioTile(
																							value: '',
																							groupValue: selectedSub,
																							title: 'Off',
																							onChanged: (v) async {
																								setModalState(() { selectedSub = ''; });
																								await _player.setSubtitleTrack(mk.SubtitleTrack.no());
																								await _persistTrackChoice(selectedAudio, '');
																							},
																						);
																					}
																					final s = subs[index - 1];
																					return _NetflixRadioTile(
																						value: s.id ?? '',
																						groupValue: selectedSub,
																						title: _labelForTrack(s, index - 1),
																						onChanged: (v) async {
																							if (v == null) return;
																							setModalState(() { selectedSub = v; });
																							await _player.setSubtitleTrack(s);
																							await _persistTrackChoice(selectedAudio, v);
																						},
																					);
																				},
																			),
																		),
																	],
																),
															),
														),
													],
												),
											),
										],
									);
								},
							),
						),
					),
				);
			},
		);
	}

	/// Restore audio and subtitle track preferences
	Future<void> _restoreTrackPreferences() async {
		try {
			final seriesPlaylist = _seriesPlaylist;
			Map<String, dynamic>? trackPreferences;
			
			if (seriesPlaylist != null && seriesPlaylist.isSeries) {
				// For series content, get preferences for the entire series
				trackPreferences = await StorageService.getSeriesTrackPreferences(
					seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
				);
			} else {
				// For non-series content, get preferences for this specific video
				final videoTitle = widget.title.isNotEmpty ? widget.title : 'Unknown Video';
				trackPreferences = await StorageService.getVideoTrackPreferences(
					videoTitle: videoTitle,
				);
			}
			
			if (trackPreferences != null) {
				final audioTrackId = trackPreferences['audioTrackId'] as String?;
				final subtitleTrackId = trackPreferences['subtitleTrackId'] as String?;
				
				// Apply audio track preference
				if (audioTrackId != null && audioTrackId.isNotEmpty && audioTrackId != 'auto') {
					final tracks = _player.state.tracks;
					final audioTrack = tracks.audio.firstWhere(
						(track) => track.id == audioTrackId,
						orElse: () => tracks.audio.first,
					);
					await _player.setAudioTrack(audioTrack);
				}
				
				// Apply subtitle track preference
				if (subtitleTrackId != null && subtitleTrackId.isNotEmpty) {
					final tracks = _player.state.tracks;
					final subtitleTrack = tracks.subtitle.firstWhere(
						(track) => track.id == subtitleTrackId,
						orElse: () => mk.SubtitleTrack.no(),
					);
					await _player.setSubtitleTrack(subtitleTrack);
				}
			}
		} catch (e) {
		}
	}

	Future<void> _persistTrackChoice(String audio, String subtitle) async {
		try {
			final seriesPlaylist = _seriesPlaylist;
			if (seriesPlaylist != null && seriesPlaylist.isSeries) {
				// For series content, save preferences for the entire series
				await StorageService.saveSeriesTrackPreferences(
					seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
					audioTrackId: audio,
					subtitleTrackId: subtitle,
				);
			} else {
				// For non-series content, save preferences for this specific video
				final videoTitle = widget.title.isNotEmpty ? widget.title : 'Unknown Video';
				await StorageService.saveVideoTrackPreferences(
					videoTitle: videoTitle,
					audioTrackId: audio,
					subtitleTrackId: subtitle,
				);
			}
		} catch (e) {
		}
	}

	/// Generate a stable hash from filename for non-series playlist state tracking
	String _generateFilenameHash(String filename) {
		// Remove file extension and normalize
		final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]*$'), '');
		// Create a simple hash (we could use a proper hash function, but this is sufficient for our needs)
		final hash = nameWithoutExt.hashCode.toString();
		return hash;
	}
}

// Netflix-style radio tile widget for track selection
class _NetflixRadioTile extends StatelessWidget {
	final String value;
	final String groupValue;
	final String title;
	final ValueChanged<String?> onChanged;

	const _NetflixRadioTile({
		required this.value,
		required this.groupValue,
		required this.title,
		required this.onChanged,
	});

	@override
	Widget build(BuildContext context) {
		final isSelected = value == groupValue;
		
		return Container(
			margin: const EdgeInsets.only(bottom: 8),
			decoration: BoxDecoration(
				color: isSelected 
					? const Color(0xFFE50914).withOpacity(0.2)
					: Colors.transparent,
				borderRadius: BorderRadius.circular(12),
				border: Border.all(
					color: isSelected 
						? const Color(0xFFE50914)
						: Colors.white.withOpacity(0.1),
					width: 1,
				),
			),
			child: Material(
				color: Colors.transparent,
				child: InkWell(
					onTap: () => onChanged(value),
					borderRadius: BorderRadius.circular(12),
					child: Padding(
						padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
						child: Row(
							children: [
								Container(
									width: 20,
									height: 20,
									decoration: BoxDecoration(
										shape: BoxShape.circle,
										border: Border.all(
											color: isSelected 
												? const Color(0xFFE50914)
												: Colors.white.withOpacity(0.5),
											width: 2,
										),
									),
									child: isSelected
										? Container(
											margin: const EdgeInsets.all(4),
											decoration: const BoxDecoration(
												shape: BoxShape.circle,
												color: Color(0xFFE50914),
											),
										)
										: null,
								),
								const SizedBox(width: 12),
								Expanded(
									child: Text(
										title,
										style: TextStyle(
											color: isSelected 
												? Colors.white
												: Colors.white.withOpacity(0.8),
											fontWeight: isSelected 
												? FontWeight.w600
												: FontWeight.w400,
											fontSize: 14,
										),
									),
								),
							],
						),
					),
				),
			),
		);
	}
}

// Netflix-style control button widget
class _NetflixControlButton extends StatelessWidget {
	final IconData icon;
	final String label;
	final VoidCallback onPressed;
	final bool isPrimary;
	final bool isCompact;

	const _NetflixControlButton({
		required this.icon,
		required this.label,
		required this.onPressed,
		this.isPrimary = false,
		this.isCompact = false,
	});

	@override
	Widget build(BuildContext context) {
		return Container(
			margin: EdgeInsets.only(right: isCompact ? 8 : 16),
			child: Material(
				color: Colors.transparent,
				child: InkWell(
					onTap: onPressed,
					borderRadius: BorderRadius.circular(8),
					child: Container(
						padding: EdgeInsets.symmetric(
							horizontal: isCompact ? 8 : 12, 
							vertical: isCompact ? 6 : 8
						),
						decoration: BoxDecoration(
							color: isPrimary 
								? const Color(0xFFE50914).withOpacity(0.9)
								: Colors.black.withOpacity(0.6),
							borderRadius: BorderRadius.circular(8),
							border: Border.all(
								color: isPrimary 
									? const Color(0xFFE50914)
									: Colors.white.withOpacity(0.2),
								width: 1,
							),
						),
						child: Row(
							mainAxisSize: MainAxisSize.min,
							children: [
								Icon(
									icon,
									color: Colors.white,
									size: isCompact ? 16 : 18,
								),
								if (!isCompact || label.isNotEmpty) ...[
									SizedBox(width: isCompact ? 4 : 6),
									Text(
										label,
										style: TextStyle(
											color: Colors.white,
											fontSize: isCompact ? 10 : 12,
											fontWeight: FontWeight.w500,
										),
									),
								],
							],
						),
					),
				),
			),
		);
	} 
}

/// Widget to build beautiful OTT-style metadata row
class _BuildMetadataRow extends StatelessWidget {
	final Map<String, dynamic> metadata;

	const _BuildMetadataRow(this.metadata);

	@override
	Widget build(BuildContext context) {
		final List<Widget> metadataItems = [];

		// Rating
		if (metadata['rating'] != null && metadata['rating'] > 0) {
			metadataItems.add(_buildMetadataItem(
				Icons.star_rounded,
				'${metadata['rating'].toStringAsFixed(1)}',
				'Rating',
			));
		}

		// Runtime
		if (metadata['runtime'] != null && metadata['runtime'] > 0) {
			metadataItems.add(_buildMetadataItem(
				Icons.access_time_rounded,
				'${metadata['runtime']} min',
				'Duration',
			));
		}

		// Year
		if (metadata['year'] != null && metadata['year'].isNotEmpty) {
			metadataItems.add(_buildMetadataItem(
				Icons.calendar_today_rounded,
				metadata['year'],
				'Year',
			));
		}

		// Language
		if (metadata['language'] != null && metadata['language'].isNotEmpty) {
			metadataItems.add(_buildMetadataItem(
				Icons.language_rounded,
				metadata['language'].toUpperCase(),
				'Language',
			));
		}

		// Genres (show first 2)
		if (metadata['genres'] != null && (metadata['genres'] as List).isNotEmpty) {
			final genres = metadata['genres'] as List;
			final displayGenres = genres.take(2).join(', ');
			metadataItems.add(_buildMetadataItem(
				Icons.category_rounded,
				displayGenres,
				'Genres',
			));
		}

		// Network
		if (metadata['network'] != null && metadata['network'].isNotEmpty) {
			metadataItems.add(_buildMetadataItem(
				Icons.tv_rounded,
				metadata['network'],
				'Network',
			));
		}

		if (metadataItems.isEmpty) {
			return const SizedBox.shrink();
		}

		return Container(
			width: 280,
			padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
			decoration: BoxDecoration(
				color: Colors.black.withOpacity(0.85),
				borderRadius: BorderRadius.circular(20),
				border: Border.all(
					color: Colors.white.withOpacity(0.15),
					width: 1,
				),
				boxShadow: [
					BoxShadow(
						color: Colors.black.withOpacity(0.3),
						blurRadius: 20,
						offset: const Offset(0, 10),
					),
				],
			),
			child: Column(
				mainAxisSize: MainAxisSize.min,
				children: [
					// Header
					Row(
						children: [
							Container(
								padding: const EdgeInsets.all(6),
								decoration: BoxDecoration(
									color: const Color(0xFFE50914).withOpacity(0.2),
									borderRadius: BorderRadius.circular(8),
								),
								child: const Icon(
									Icons.info_outline_rounded,
									color: Color(0xFFE50914),
									size: 16,
								),
							),
							const SizedBox(width: 8),
							const Text(
								'Episode Info',
								style: TextStyle(
									color: Colors.white,
									fontSize: 14,
									fontWeight: FontWeight.w600,
								),
							),
						],
					),
					const SizedBox(height: 12),
					// Metadata grid
					Wrap(
						spacing: 12,
						runSpacing: 8,
						children: metadataItems,
					),
				],
			),
		);
	}

	Widget _buildMetadataItem(IconData icon, String value, String label) {
		return Container(
			width: 120,
			padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
			decoration: BoxDecoration(
				color: Colors.white.withOpacity(0.08),
				borderRadius: BorderRadius.circular(12),
				border: Border.all(
					color: Colors.white.withOpacity(0.1),
					width: 1,
				),
			),
			child: Row(
				children: [
					Container(
						padding: const EdgeInsets.all(6),
						decoration: BoxDecoration(
							color: const Color(0xFFE50914).withOpacity(0.2),
							borderRadius: BorderRadius.circular(8),
						),
						child: Icon(
							icon,
							color: const Color(0xFFE50914),
							size: 14,
						),
					),
					const SizedBox(width: 8),
					Expanded(
						child: Column(
							crossAxisAlignment: CrossAxisAlignment.start,
							mainAxisSize: MainAxisSize.min,
							children: [
								Text(
									value,
									style: const TextStyle(
										color: Colors.white,
										fontSize: 12,
										fontWeight: FontWeight.w600,
									),
									maxLines: 1,
									overflow: TextOverflow.ellipsis,
								),
								Text(
									label,
									style: TextStyle(
										color: Colors.white.withOpacity(0.6),
										fontSize: 10,
										fontWeight: FontWeight.w400,
									),
									maxLines: 1,
									overflow: TextOverflow.ellipsis,
								),
							],
						),
					),
				],
			),
		);
	}
}