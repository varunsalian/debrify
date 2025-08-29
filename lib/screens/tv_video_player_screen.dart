import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

/// A minimal TV video player screen for playing random movies from channel hubs.
///
/// Features:
/// - Basic play/pause controls
/// - Auto-play from random timestamp
/// - Minimal UI for TV viewing experience
class TVVideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? subtitle;

  const TVVideoPlayerScreen({
    Key? key,
    required this.videoUrl,
    required this.title,
    this.subtitle,
  }) : super(key: key);

  @override
  State<TVVideoPlayerScreen> createState() => _TVVideoPlayerScreenState();
}

class _TVVideoPlayerScreenState extends State<TVVideoPlayerScreen> {
  late mk.Player _player;
  late mkv.VideoController _videoController;
  
  // Player state
  bool _isReady = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _hasJumpedToRandom = false;
  
  // Stream subscriptions
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _completedSub;

  @override
  void initState() {
    super.initState();
    mk.MediaKit.ensureInitialized();
    
    // Set up system UI for TV viewing
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    WakelockPlus.enable();
    
    // Initialize the player
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // Create player and controller
      _player = mk.Player();
      _videoController = mkv.VideoController(_player);
      
      // Set up stream subscriptions
      _posSub = _player.stream.position.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });
      
      _durSub = _player.stream.duration.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
          
          // Jump to random timestamp once duration is available
          if (duration.inSeconds > 0 && _isReady && !_hasJumpedToRandom) {
            _hasJumpedToRandom = true;
            Timer(const Duration(milliseconds: 500), () {
              _jumpToRandomTimestamp();
            });
          }
        }
      });
      
      _playSub = _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
          });
        }
      });
      
      _completedSub = _player.stream.completed.listen((completed) {
        if (completed && mounted) {
          Navigator.of(context).pop();
        }
      });
      
      // Set up media
      await _player.open(mk.Media(widget.videoUrl));
      
      // Start playing
      await _player.play();
      
      setState(() {
        _isReady = true;
      });
      
    } catch (e) {
      print('Error initializing TV video player: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load video: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _jumpToRandomTimestamp() async {
    print('DEBUG: Attempting random timestamp jump. Duration: ${_duration.inSeconds}s');
    
    if (_duration.inSeconds > 60) {
      final random = Random();
      final maxJumpSeconds = _duration.inSeconds - 60;
      final randomSeconds = random.nextInt(maxJumpSeconds);
      final randomPosition = Duration(seconds: randomSeconds);
      
      print('DEBUG: Jumping to random timestamp: ${randomPosition.inMinutes}:${(randomPosition.inSeconds % 60).toString().padLeft(2, '0')}');
      
      try {
        await _player.seek(randomPosition);
        print('DEBUG: Successfully jumped to random timestamp');
      } catch (e) {
        print('DEBUG: Error jumping to random timestamp: $e');
      }
    } else {
      print('DEBUG: Video too short for random jump (${_duration.inSeconds}s)');
    }
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _completedSub?.cancel();
    
    _player.dispose();
    
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.disable();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video player
          Center(
            child: _isReady
                ? mkv.Video(
                    controller: _videoController,
                    controls: null,
                  )
                : const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
          ),
          
          // Minimal controls overlay
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Title
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                
                // Play/Pause button
                IconButton(
                  onPressed: _togglePlayPause,
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                
                // Close button
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 