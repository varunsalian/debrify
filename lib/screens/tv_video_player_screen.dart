import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../models/tv_channel.dart';
import '../models/tv_channel_torrent.dart';
import '../services/tv_playback_service.dart';
import '../services/storage_service.dart';

/// A TV mode video player that provides a realistic TV experience
/// with minimal controls and a "Surprise Me" button for random content
class TVVideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? subtitle;
  final TVChannel channel;
  final List<TVChannelTorrent> torrents;
  final Map<String, dynamic>? debridResult;

  const TVVideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    this.subtitle,
    required this.channel,
    required this.torrents,
    this.debridResult,
  });

  @override
  State<TVVideoPlayerScreen> createState() => _TVVideoPlayerScreenState();
}

class _TVVideoPlayerScreenState extends State<TVVideoPlayerScreen> with TickerProviderStateMixin {
  late mk.Player _player;
  late mkv.VideoController _videoController;
  final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);

  Timer? _hideTimer;
  bool _isReady = false;
  bool _isPlaying = false;
  String _currentTitle = '';
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;

  @override
  void initState() {
    super.initState();
    print('🎬 [TVVideoPlayer] Initializing TV video player...');
    print('🎬 [TVVideoPlayer] Video URL: ${widget.videoUrl}');
    print('🎬 [TVVideoPlayer] Title: ${widget.title}');
    
    _currentTitle = widget.title;
    
    mk.MediaKit.ensureInitialized();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Default to landscape when entering the player
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.enable();
    _initializePlayer();
    _setupBrightness();
  }

  Future<void> _initializePlayer() async {
    print('🎬 [TVVideoPlayer] Initializing player...');
    
    try {
      _player = mk.Player(configuration: mk.PlayerConfiguration(
        ready: () {
          print('🎬 [TVVideoPlayer] Player ready callback triggered');
          _isReady = true;
          if (mounted) setState(() {});
        },
      ));
      print('🎬 [TVVideoPlayer] Player created successfully');
      
      _videoController = mkv.VideoController(_player);
      print('🎬 [TVVideoPlayer] Video controller created successfully');

      // Open the video
      print('🎬 [TVVideoPlayer] Opening media: ${widget.videoUrl}');
      await _player.open(mk.Media(widget.videoUrl));
      print('🎬 [TVVideoPlayer] Media opened successfully');
      
      // Start playing automatically
      print('🎬 [TVVideoPlayer] Starting playback...');
      await _player.play();
      print('🎬 [TVVideoPlayer] Playback started');

      // Set up stream listeners
      _posSub = _player.stream.position.listen((d) {
        if (mounted) setState(() {});
      });

      _durSub = _player.stream.duration.listen((d) {
        if (mounted) setState(() {});
      });

      _playSub = _player.stream.playing.listen((p) {
        print('🎬 [TVVideoPlayer] Playing state changed: $p');
        _isPlaying = p;
        if (mounted) setState(() {});
      });

      // Add error listener
      _player.stream.error.listen((error) {
        print('🎬 [TVVideoPlayer] Player error: $error');
      });

      // Add completion listener
      _player.stream.completed.listen((completed) {
        print('🎬 [TVVideoPlayer] Playback completed: $completed');
      });

      print('🎬 [TVVideoPlayer] Stream listeners set up successfully');

      // Auto-hide controls after 3 seconds
      _scheduleAutoHide();
      print('🎬 [TVVideoPlayer] Player initialization complete');
    } catch (e) {
      print('🎬 [TVVideoPlayer] Error initializing player: $e');
      print('🎬 [TVVideoPlayer] Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> _setupBrightness() async {
    try {
      await WakelockPlus.enable();
      await ScreenBrightness().setScreenBrightness(0.5);
    } catch (e) {
      // Ignore brightness errors
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _player.dispose();
    
    // Restore system UI and orientation
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      ScreenBrightness().resetScreenBrightness();
      WakelockPlus.disable();
    } catch (e) {
      // Ignore errors
    }
    
    super.dispose();
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



  Future<void> _surpriseMe() async {
    if (_isLoading.value) return; // Prevent multiple simultaneous attempts

    _isLoading.value = true;
    print('🎬 [TVVideoPlayer] Surprise Me clicked - finding new content...');

    try {
      // Get a random torrent from the channel
      final randomTorrent = TVPlaybackService.getRandomTorrent(widget.channel, widget.torrents);
      print('🎬 [TVVideoPlayer] Selected random torrent: ${randomTorrent.name}');
      
      // Attempt to play it
      final result = await TVPlaybackService.attemptTorrentPlayback(
        randomTorrent,
        await StorageService.getApiKey() ?? '',
      );

      if (result != null && mounted) {
        print('🎬 [TVVideoPlayer] Got new content, loading in same player...');
        
        // Update the widget's video URL and title
        final newVideoUrl = result['downloadLink'];
        final newTitle = randomTorrent.name;
        
        // Load the new media in the same player instance
        await _player.open(mk.Media(newVideoUrl));
        print('🎬 [TVVideoPlayer] New media loaded: $newTitle');
        
        // Start playing automatically
        await _player.play();
        print('🎬 [TVVideoPlayer] New content started playing');
        
        // Update the UI to reflect the new title
        setState(() {
          _currentTitle = newTitle;
        });
      } else {
        print('🎬 [TVVideoPlayer] No playable content found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No playable content found. Try again!'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('🎬 [TVVideoPlayer] Error in Surprise Me: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load content: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      _isLoading.value = false;
    }
  }



  @override
  Widget build(BuildContext context) {
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
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            
            // Space -> Toggle play/pause
            if (key == LogicalKeyboardKey.space) {
              if (_isReady) {
                if (_isPlaying) {
                  _player.pause();
                } else {
                  _player.play();
                }
              }
              return KeyEventResult.handled;
            }
            
            // Enter -> Toggle controls
            if (key == LogicalKeyboardKey.enter) {
              _toggleControls();
              return KeyEventResult.handled;
            }
            
            // Escape -> Go back
            if (key == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video texture
              if (_isReady)
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: 1920,
                    height: 1080,
                    child: mkv.Video(controller: _videoController, controls: null),
                  ),
                )
              else
                const Center(child: CircularProgressIndicator(color: Colors.white)),
              
              // Gesture detector for tap to toggle controls
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
              ),
              
              // LIVE tag - always visible (not part of controls)
              Positioned(
                bottom: 20,
                left: 20,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Small "Surprise Me" button - always visible
              Positioned(
                bottom: 20,
                right: 20,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: _surpriseMe,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _isLoading.value
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.shuffle_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

 