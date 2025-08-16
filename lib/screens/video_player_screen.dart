import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
// Removed volume_controller; using media_kit player volume instead
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/storage_service.dart';
import '../services/android_native_downloader.dart';
import '../services/debrid_service.dart';
import '../models/series_playlist.dart';
import '../widgets/series_browser.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

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

enum _AspectMode { contain, cover, fitWidth, fitHeight }

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with TickerProviderStateMixin {
	late mk.Player _player;
	late mkv.VideoController _videoController;
	final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);
	Timer? _hideTimer;
	bool _isSeekingWithSlider = false;
	_DoubleTapRipple? _ripple;
	bool _panIgnore = false;
	int _currentIndex = 0;
	Offset? _lastTapLocal;

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
		// Determine the initial URL
		String initialUrl = widget.videoUrl;
		if (widget.playlist != null && widget.playlist!.isNotEmpty) {
			final startIndex = widget.startIndex ?? 0;
			final entry = widget.playlist![startIndex];
			if (entry.url.isNotEmpty) {
				initialUrl = entry.url;
			}
		}
		
		_currentIndex = widget.playlist != null ? (widget.startIndex ?? 0) : 0;
		_player = mk.Player(configuration: mk.PlayerConfiguration(ready: () {
			_isReady = true;
			if (mounted) setState(() {});
		}));
		_videoController = mkv.VideoController(_player);
		
		// Only open the player if we have a valid URL
		if (initialUrl.isNotEmpty) {
			_player.open(mk.Media(initialUrl)).then((_) async {
				await _maybeRestoreResume();
				_scheduleAutoHide();
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

	void _onVideoUpdate() {
		// Update slider-driven seeks HUD if needed
		if (!mounted) return;
		// handled via stream.completed
		if (mounted) setState(() {});
	}

	Future<void> _onPlaybackEnded() async {
		if (widget.playlist == null || widget.playlist!.isEmpty) return;
		if (_currentIndex + 1 >= widget.playlist!.length) return; // end
		await _loadPlaylistIndex(_currentIndex + 1, autoplay: true);
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
				// Show loading indicator
				if (mounted) {
					ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(
							content: Row(
								children: [
									const SizedBox(
										width: 16,
										height: 16,
										child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
									),
									const SizedBox(width: 12),
									const Text('Unrestricting video...', style: TextStyle(color: Colors.white)),
								],
							),
							backgroundColor: const Color(0xFF1E293B),
							duration: const Duration(seconds: 2),
						),
					);
				}
				
				final unrestrictResult = await DebridService.unrestrictLink(entry.apiKey!, entry.restrictedLink!);
				videoUrl = unrestrictResult['download'] ?? entry.url;
				
				// Update the playlist entry with the unrestricted URL
				// Note: We can't modify the const PlaylistEntry, so we'll use the unrestricted URL directly
			} catch (e) {
				if (mounted) {
					ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(
							content: Text('Failed to unrestrict video: ${e.toString()}', style: const TextStyle(color: Colors.white)),
							backgroundColor: const Color(0xFFEF4444),
							duration: const Duration(seconds: 3),
						),
					);
				}
				// Fall back to the original URL
				videoUrl = entry.url;
			}
		}
		
		await _player.open(mk.Media(videoUrl), play: autoplay);
		await _maybeRestoreResume();
	}

	/// Preload episode information in the background
	Future<void> _preloadEpisodeInfo() async {
		final seriesPlaylist = widget._seriesPlaylist;
		if (seriesPlaylist != null && seriesPlaylist.isSeries) {
			// Preload episode information in the background
			seriesPlaylist.fetchEpisodeInfo().catchError((error) {
				// Silently handle errors - this is just preloading
				print('Episode info preload failed: $error');
			});
		}
	}

	@override
	void dispose() {
		_saveResume();
		_hideTimer?.cancel();
		_autosaveTimer?.cancel();
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
		final url = (widget.playlist != null && widget.playlist!.isNotEmpty)
			? widget.playlist![_currentIndex].url
			: widget.videoUrl;
		final uri = Uri.tryParse(url);
		if (uri == null) return widget.videoUrl;
		final base = uri.replace(queryParameters: {});
		return base.toString();
	}

	Future<void> _maybeRestoreResume() async {
		final data = await StorageService.getVideoResume(_resumeKey);
		if (data == null) return;
		final posMs = (data['positionMs'] ?? 0) as int;
		final speed = (data['speed'] ?? 1.0) as double;
		final aspect = (data['aspect'] ?? 'contain') as String;
		final position = Duration(milliseconds: posMs);
		final dur = _duration;
		if (dur > Duration.zero && position > const Duration(seconds: 10) && position < dur * 0.9) {
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
			default:
				_aspectMode = _AspectMode.contain;
		}
	}

	Future<void> _saveResume({bool debounced = false}) async {
		if (!_isReady) return;
		final pos = _position;
		final dur = _duration;
		if (dur <= Duration.zero) return;
		final aspectStr = () {
			switch (_aspectMode) {
				case _AspectMode.cover:
					return 'cover';
				case _AspectMode.fitWidth:
					return 'fitWidth';
				case _AspectMode.fitHeight:
					return 'fitHeight';
				case _AspectMode.contain:
				default:
					return 'contain';
			}
		}();
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
			if (mounted) setState(() => _ripple = null);
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
		setState(() {
			switch (_aspectMode) {
				case _AspectMode.contain:
					_aspectMode = _AspectMode.cover;
					break;
				case _AspectMode.cover:
					_aspectMode = _AspectMode.fitWidth;
					break;
				case _AspectMode.fitWidth:
					_aspectMode = _AspectMode.fitHeight;
					break;
				case _AspectMode.fitHeight:
					_aspectMode = _AspectMode.contain;
			}
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
		}
	}

	Future<void> _showPlaylistSheet(BuildContext context) async {
		if (widget.playlist == null || widget.playlist!.isEmpty) return;
		
		final seriesPlaylist = widget._seriesPlaylist;
		
		await showModalBottomSheet(
			context: context,
			backgroundColor: const Color(0xFF0F172A),
			isScrollControlled: true,
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
			),
			builder: (context) {
				return SafeArea(
					top: false,
					child: seriesPlaylist != null && seriesPlaylist.isSeries
						? SeriesBrowser(
							seriesPlaylist: seriesPlaylist,
							currentEpisodeIndex: _currentIndex,
							onEpisodeSelected: (episodeIndex) async {
								await _loadPlaylistIndex(episodeIndex, autoplay: true);
							},
						  )
						: _buildSimplePlaylist(),
				);
			},
		);
	}

	Widget _buildSimplePlaylist() {
		return Column(
			mainAxisSize: MainAxisSize.min,
			children: [
				Container(
					padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
					child: Row(
						children: [
							const Icon(Icons.playlist_play_rounded, color: Colors.white),
							const SizedBox(width: 8),
							const Text('All files', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
						],
					),
				),
				Flexible(
					child: ListView.builder(
						shrinkWrap: true,
						itemCount: widget.playlist!.length,
						itemBuilder: (context, index) {
							final entry = widget.playlist![index];
							final active = index == _currentIndex;
							return ListTile(
								onTap: () async {
									Navigator.of(context).pop();
									await _loadPlaylistIndex(index, autoplay: true);
								},
								title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
								leading: Icon(active ? Icons.play_arrow_rounded : Icons.movie_rounded, color: active ? Colors.greenAccent : Colors.white70),
							);
						},
					),
				),
			],
		);
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

						// DPAD up shows controls
						if (key == LogicalKeyboardKey.arrowUp) {
							_controlsVisible.value = true;
							_scheduleAutoHide();
							return KeyEventResult.handled;
						}

						// Media play/pause keys
						if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.mediaPlay || key == LogicalKeyboardKey.mediaPause) {
							_togglePlay();
							return KeyEventResult.handled;
						}
						return KeyEventResult.ignored;
					},
					child: Stack(
						fit: StackFit.expand,
						children: [
							// Video texture (media_kit renderer)
							if (isReady)
								FittedBox(
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
												title: widget.title,
												subtitle: widget.subtitle,
												duration: duration,
												position: pos,
												isPlaying: _isPlaying,
												isReady: isReady,
												onPlayPause: _togglePlay,
												onBack: () => Navigator.of(context).pop(),
												onAspect: _cycleAspectMode,
												onSpeed: _changeSpeed,
												speed: _playbackSpeed,
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
	final Duration duration;
	final Duration position;
	final bool isPlaying;
	final bool isReady;
	final VoidCallback onPlayPause;
	final VoidCallback onBack;
	final VoidCallback onAspect;
	final VoidCallback onSpeed;
	final double speed;
	final bool isLandscape;
	final VoidCallback onRotate;
	final VoidCallback onShowPlaylist;
	final VoidCallback onShowTracks;
	final bool hasPlaylist;
	final VoidCallback onSeekBarChangedStart;
	final ValueChanged<double> onSeekBarChanged;
	final VoidCallback onSeekBarChangeEnd;

	const _Controls({
		required this.title,
		required this.subtitle,
		required this.duration,
		required this.position,
		required this.isPlaying,
		required this.isReady,
		required this.onPlayPause,
		required this.onBack,
		required this.onAspect,
		required this.onSpeed,
		required this.speed,
		required this.isLandscape,
		required this.onRotate,
		required this.onShowPlaylist,
		required this.onShowTracks,
		required this.hasPlaylist,
		required this.onSeekBarChangedStart,
		required this.onSeekBarChanged,
		required this.onSeekBarChangeEnd,
	});

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
				// Interactive controls
				SafeArea(
				left: true,
				right: true,
				top: true,
				bottom: true,
				child: Column(
					mainAxisAlignment: MainAxisAlignment.spaceBetween,
					children: [
						// Top bar
						Row(
							children: [
								IconButton(
									icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
									onPressed: onBack,
								),
								Expanded(
									child: Column(
										crossAxisAlignment: CrossAxisAlignment.start,
										children: [
											Text(
												title,
												maxLines: 1,
												overflow: TextOverflow.ellipsis,
												style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
											),
											if (subtitle != null)
												Text(
													subtitle!,
													maxLines: 1,
													overflow: TextOverflow.ellipsis,
													style: const TextStyle(color: Colors.white70, fontSize: 12),
												),
										],
									),
								),
								Row(
									children: [
										Text('${speed}x', style: const TextStyle(color: Colors.white70, fontSize: 12)),
										IconButton(
											icon: const Icon(Icons.slow_motion_video_rounded, color: Colors.white),
											onPressed: onSpeed,
										),
										IconButton(
											icon: const Icon(Icons.crop_free_rounded, color: Colors.white),
											onPressed: onAspect,
										),
										IconButton(
											icon: const Icon(Icons.closed_caption_off_rounded, color: Colors.white),
											onPressed: onShowTracks,
											tooltip: 'Audio & Subtitles',
										),
										if (hasPlaylist)
											IconButton(
												icon: const Icon(Icons.playlist_play_rounded, color: Colors.white),
												onPressed: onShowPlaylist,
												tooltip: 'Playlist',
											),
										IconButton(
											icon: Icon(isLandscape ? Icons.stay_current_landscape_rounded : Icons.screen_rotation_rounded, color: Colors.white),
											onPressed: onRotate,
											tooltip: isLandscape ? 'Portrait' : 'Rotate',
										),
									],
								),
							],
						),

						// Center play/pause
						if (isReady)
						Row(
							mainAxisAlignment: MainAxisAlignment.center,
							children: [
								InkWell(
									onTap: onPlayPause,
									customBorder: const CircleBorder(),
									child: Container(
										padding: const EdgeInsets.all(14),
										decoration: BoxDecoration(
											shape: BoxShape.circle,
											color: Colors.black.withOpacity(0.4),
										),
										child: Icon(
											isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
											color: Colors.white,
											size: 42,
										),
									),
								),
							],
						),

						// Bottom bar
						Padding(
							padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
							child: Column(
								mainAxisSize: MainAxisSize.min,
								children: [
									Row(
										children: [
											Text(_format(position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
											const SizedBox(width: 8),
											Expanded(
												child: SliderTheme(
													data: SliderTheme.of(context).copyWith(
														trackHeight: 3,
														thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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
										const SizedBox(width: 8),
										Text(_format(duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
									],
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

Future<void> _persistTrackChoice(String audio, String subtitle) async {}

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
			backgroundColor: const Color(0xFF0B1222),
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
			),
			builder: (context) {
				return SafeArea(
					top: false,
					child: FractionallySizedBox(
						heightFactor: 0.7,
						child: Padding(
							padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
							child: StatefulBuilder(
								builder: (context, setModalState) {
									return Column(
										crossAxisAlignment: CrossAxisAlignment.stretch,
										children: [
											Row(
												children: [
													const Icon(Icons.tune_rounded, color: Colors.white),
													const SizedBox(width: 8),
													const Text('Audio & Subtitles', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
													const Spacer(),
													IconButton(
														icon: const Icon(Icons.close_rounded, color: Colors.white70),
														onPressed: () => Navigator.of(context).pop(),
													),
												],
											),
											const SizedBox(height: 10),
											Expanded(
												child: Row(
													children: [
														// Audio pane
														Expanded(
															child: Container(
																decoration: BoxDecoration(
																	color: const Color(0xFF121B30),
																	borderRadius: BorderRadius.circular(12),
																	border: Border.all(color: const Color(0xFF22304F)),
																),
																padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
																child: Column(
																	crossAxisAlignment: CrossAxisAlignment.start,
																	children: [
																		Row(
																			children: const [
																				Icon(Icons.volume_up_rounded, color: Colors.white70, size: 18),
																				SizedBox(width: 6),
																				Text('Audio', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
																			],
																		),
																		const SizedBox(height: 6),
																		Expanded(
																			child: ListView.builder(
																				itemCount: audios.length + 1,
																				itemBuilder: (context, index) {
																					if (index == 0) {
																						return RadioListTile<String>(
																							value: 'auto',
																							groupValue: selectedAudio.isEmpty ? 'auto' : selectedAudio,
																							title: const Text('Auto', style: TextStyle(color: Colors.white)),
																							dense: true,
																							onChanged: (v) async {
																								setModalState(() { selectedAudio = ''; });
																								await _player.setAudioTrack(mk.AudioTrack.auto());
																							},
																						);
																					}
																					final a = audios[index - 1];
																					return RadioListTile<String>(
																						value: a.id ?? '',
																						groupValue: selectedAudio.isEmpty ? 'auto' : selectedAudio,
																						title: Text(_labelForTrack(a, index - 1), style: const TextStyle(color: Colors.white)),
																						dense: true,
																						onChanged: (v) async {
																							if (v == null) return;
																							setModalState(() { selectedAudio = v; });
																							await _player.setAudioTrack(a);
																						},
																					);
																				},
																			),
																		),
																	],
																),
															),
														),
														const SizedBox(width: 12),
														// Subtitles pane
														Expanded(
															child: Container(
																decoration: BoxDecoration(
																	color: const Color(0xFF121B30),
																	borderRadius: BorderRadius.circular(12),
																	border: Border.all(color: const Color(0xFF22304F)),
																),
																padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
																child: Column(
																	crossAxisAlignment: CrossAxisAlignment.start,
																	children: [
																		Row(
																			children: const [
																				Icon(Icons.closed_caption_rounded, color: Colors.white70, size: 18),
																				SizedBox(width: 6),
																				Text('Subtitles', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
																			],
																		),
																		const SizedBox(height: 6),
																		Expanded(
																			child: ListView.builder(
																				itemCount: subs.length + 1,
																				itemBuilder: (context, index) {
																					if (index == 0) {
																						return RadioListTile<String>(
																							value: '',
																							groupValue: selectedSub,
																							title: const Text('Off', style: TextStyle(color: Colors.white)),
																							dense: true,
																							onChanged: (v) async {
																								setModalState(() { selectedSub = ''; });
																								await _player.setSubtitleTrack(mk.SubtitleTrack.no());
																							},
																						);
																					}
																					final s = subs[index - 1];
																					return RadioListTile<String>(
																						value: s.id ?? '',
																						groupValue: selectedSub,
																						title: Text(_labelForTrack(s, index - 1), style: const TextStyle(color: Colors.white)),
																						dense: true,
																						onChanged: (v) async {
																							if (v == null) return;
																							setModalState(() { selectedSub = v; });
																							await _player.setSubtitleTrack(s);
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
} 