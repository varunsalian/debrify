import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/storage_service.dart';

class VideoPlayerScreen extends StatefulWidget {
	final String videoUrl;
	final String title;
	final String? subtitle;

	const VideoPlayerScreen({
		Key? key,
		required this.videoUrl,
		required this.title,
		this.subtitle,
	}) : super(key: key);

	@override
	State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

enum _GestureMode { none, seek, volume, brightness }

enum _AspectMode { contain, cover, fitWidth, fitHeight }

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with TickerProviderStateMixin {
	late final VideoPlayerController _controller;
	final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);
	Timer? _hideTimer;
	bool _isSeekingWithSlider = false;
	_DoubleTapRipple? _ripple;
	bool _panIgnore = false;

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
		SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
		// Default to landscape when entering the player
		SystemChrome.setPreferredOrientations(<DeviceOrientation>[
			DeviceOrientation.landscapeLeft,
			DeviceOrientation.landscapeRight,
		]);
		_landscapeLocked = true;
		WakelockPlus.enable();
		VolumeController().showSystemUI = false;
		_controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl),
			videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
		)
			..addListener(_onVideoUpdate)
			..initialize().then((_) async {
				if (!mounted) return;
				await _maybeRestoreResume();
				setState(() {});
				_controller.play();
				_scheduleAutoHide();
			});
		_autosaveTimer = Timer.periodic(const Duration(seconds: 6), (_) => _saveResume(debounced: true));
	}

	void _onVideoUpdate() {
		// Update slider-driven seeks HUD if needed
		if (!mounted) return;
		setState(() {});
	}

	@override
	void dispose() {
		_saveResume();
		_hideTimer?.cancel();
		_autosaveTimer?.cancel();
		_controlsVisible.dispose();
		_seekHud.dispose();
		_verticalHud.dispose();
		_controller.removeListener(_onVideoUpdate);
		_controller.dispose();
		WakelockPlus.disable();
		SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
		SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
		super.dispose();
	}

	Timer? _autosaveTimer;

	String get _resumeKey {
		// Use a canonical key stripping volatile query parts
		final uri = Uri.tryParse(widget.videoUrl);
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
		final dur = _controller.value.duration;
		if (dur > Duration.zero && position > const Duration(seconds: 10) && position < dur * 0.9) {
			await _controller.seekTo(position);
		}
		// restore speed
		if (speed != 1.0) {
			await _controller.setPlaybackSpeed(speed);
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
		if (!_controller.value.isInitialized) return;
		final pos = _controller.value.position;
		final dur = _controller.value.duration;
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
		final target = _controller.value.position + (isLeft ? -delta : delta);
		final minPos = Duration.zero;
		final maxPos = _controller.value.duration;
		final clamped = target < minPos ? minPos : (target > maxPos ? maxPos : target);
		await _controller.seekTo(clamped);
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
		_gestureStartVideoPosition = _controller.value.position;
		_gestureStartVolume = await VolumeController().getVolume();
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
			final duration = _controller.value.duration;
			if (duration == Duration.zero) return;
			// Map horizontal delta to seconds, proportional to width
			final totalSeconds = duration.inSeconds.toDouble();
			final seekSeconds = (dx / size.width) * math.min(120.0, totalSeconds);
			var newPos = _gestureStartVideoPosition + Duration(seconds: seekSeconds.round());
			if (newPos < Duration.zero) newPos = Duration.zero;
			if (newPos > duration) newPos = duration;
			_seekHud.value = _SeekHudState(
				target: newPos,
				base: _controller.value.position,
				isForward: newPos >= _controller.value.position,
			);
		} else if (_mode == _GestureMode.volume) {
			var newVol = (_gestureStartVolume - dy / size.height).clamp(0.0, 1.0);
			VolumeController().setVolume(newVol);
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
			_controller.seekTo(_seekHud.value!.target);
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
		if (!_controller.value.isInitialized) return;
		if (_controller.value.isPlaying) {
			_controller.pause();
		} else {
			_controller.play();
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
		_controller.setPlaybackSpeed(next);
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

	@override
	Widget build(BuildContext context) {
		final isReady = _controller.value.isInitialized;
		final duration = _controller.value.duration;
		final pos = _controller.value.position;
		// final remaining = (duration - pos).clamp(Duration.zero, duration); // not used

		return Scaffold(
			backgroundColor: Colors.black,
			body: SafeArea(
				left: false,
				top: false,
				right: false,
				bottom: false,
				child: Stack(
					fit: StackFit.expand,
					children: [
						// Video texture
						if (isReady)
							FittedBox(
								fit: _currentFit(),
								child: SizedBox(
									width: _controller.value.size.width,
									height: _controller.value.size.height,
									child: VideoPlayer(_controller),
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
						// Controls overlay
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
											isPlaying: _controller.value.isPlaying,
											onPlayPause: _togglePlay,
											onBack: () => Navigator.of(context).pop(),
											onAspect: _cycleAspectMode,
											onSpeed: _changeSpeed,
											speed: _playbackSpeed,
											isLandscape: _landscapeLocked,
											onRotate: _toggleOrientation,
											onSeekBarChangedStart: () {
												_isSeekingWithSlider = true;
											},
											onSeekBarChanged: (v) {
												final newPos = duration * v;
												_controller.seekTo(newPos);
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
						// Top-most gesture layer to always receive pans/double-taps
						GestureDetector(
							behavior: HitTestBehavior.translucent,
							onTap: _controlsVisible.value ? null : _toggleControls,
							onDoubleTapDown: _handleDoubleTap,
							onPanStart: _onPanStart,
							onPanUpdate: _onPanUpdate,
							onPanEnd: _onPanEnd,
						),
					],
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
	final VoidCallback onPlayPause;
	final VoidCallback onBack;
	final VoidCallback onAspect;
	final VoidCallback onSpeed;
	final double speed;
	final bool isLandscape;
	final VoidCallback onRotate;
	final VoidCallback onSeekBarChangedStart;
	final ValueChanged<double> onSeekBarChanged;
	final VoidCallback onSeekBarChangeEnd;

	const _Controls({
		required this.title,
		required this.subtitle,
		required this.duration,
		required this.position,
		required this.isPlaying,
		required this.onPlayPause,
		required this.onBack,
		required this.onAspect,
		required this.onSpeed,
		required this.speed,
		required this.isLandscape,
		required this.onRotate,
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

		return Container(
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
			child: SafeArea(
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
											icon: Icon(isLandscape ? Icons.stay_current_landscape_rounded : Icons.screen_rotation_rounded, color: Colors.white),
											onPressed: onRotate,
											tooltip: isLandscape ? 'Portrait' : 'Rotate',
										),
									],
								),
							],
						),

						// Center play/pause
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