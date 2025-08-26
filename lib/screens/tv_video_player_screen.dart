import 'dart:async';
import 'dart:math';

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
import '../utils/series_parser.dart';

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
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _showDoubleTapFeedback = ValueNotifier<bool>(false);

  Timer? _hideTimer;
  bool _isReady = false;
  bool _isPlaying = false;
  String _currentTitle = '';
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  
  // Animation controllers for LIVE tag effects
  late AnimationController _livePulseController;
  late Animation<double> _livePulseAnimation;
  late Animation<double> _liveGlowAnimation;
  
  // Animation controllers for title folding effect
  late AnimationController _titleFoldController;
  late Animation<double> _titleFoldAnimation;
  late Animation<double> _titleOpacityAnimation;
  
  // Animation controller for LIVE dot blinking
  late AnimationController _liveDotController;
  late Animation<double> _liveDotAnimation;

  @override
  void initState() {
    super.initState();
    print('🎬 [TVVideoPlayer] Initializing TV video player...');
    print('🎬 [TVVideoPlayer] Video URL: ${widget.videoUrl}');
    print('🎬 [TVVideoPlayer] Widget title: "${widget.title}"');
    print('🎬 [TVVideoPlayer] Channel name: "${widget.channel.name}"');
    
    _currentTitle = widget.title;
    print('🎬 [TVVideoPlayer] Set _currentTitle to: "$_currentTitle"');
    
    // Initialize LIVE tag animations
    _livePulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _livePulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _livePulseController,
      curve: Curves.easeInOut,
    ));
    
    _liveGlowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _livePulseController,
      curve: Curves.easeInOut,
    ));
    
    // Start the pulse animation
    _livePulseController.repeat(reverse: true);
    
    // Initialize title folding animation
    _titleFoldController = AnimationController(
      duration: const Duration(seconds: 20), // Show for 20 seconds, then fold
      vsync: this,
    );
    
    _titleFoldAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _titleFoldController,
      curve: const Interval(0.0, 0.3, curve: Curves.easeInOut), // Fold in first 30%
    ));
    
    _titleOpacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _titleFoldController,
      curve: const Interval(0.0, 0.3, curve: Curves.easeInOut), // Fade out with fold
    ));
    
    // Start the title folding animation cycle
    _startTitleFoldCycle();
    
    // Initialize LIVE dot blinking animation
    _liveDotController = AnimationController(
      duration: const Duration(milliseconds: 1000), // 1 second blink cycle
      vsync: this,
    );
    
    _liveDotAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _liveDotController,
      curve: Curves.easeInOut,
    ));
    
    // Start the dot blinking animation
    _liveDotController.repeat(reverse: true);
    
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
      
      // Try to seek to random timestamp (fallback if duration not available yet)
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isReady) {
          _seekToRandomTimestamp();
        }
      });

      // Set up stream listeners
      _posSub = _player.stream.position.listen((d) {
        if (mounted) setState(() {});
      });

      _durSub = _player.stream.duration.listen((d) {
        if (mounted) setState(() {});
        // When duration becomes available, seek to random timestamp
        if (d != null && d.inSeconds > 60) {
          _seekToRandomTimestamp(d);
        }
      });

      _playSub = _player.stream.playing.listen((p) {
        print('🎬 [TVVideoPlayer] Playing state changed: $p');
        _isPlaying = p;
        if (mounted) setState(() {});
      });

      // Add error listener
      _player.stream.error.listen((error) {
        print('🎬 [TVVideoPlayer] Player error: $error');
        
        // Auto-trigger Surprise Me on file format errors
        if (error.toString().contains('Failed to recognize file format') || 
            error.toString().contains('file format') ||
            error.toString().contains('unsupported format')) {
          print('🎬 [TVVideoPlayer] File format error detected - auto-triggering Surprise Me');
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              _surpriseMe();
            }
          });
        }
      });

      // Add completion listener
      _player.stream.completed.listen((completed) {
        print('🎬 [TVVideoPlayer] Playback completed: $completed');
      });

      print('🎬 [TVVideoPlayer] Stream listeners set up successfully');


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
    _livePulseController.dispose();
    _titleFoldController.dispose();
    _liveDotController.dispose();
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



  void _seekToRandomTimestamp([Duration? duration]) async {
    if (!mounted || !_isReady) return;
    
    try {
      // Use provided duration or get from player state
      final videoDuration = duration ?? _player.state.duration;
      if (videoDuration != null && videoDuration.inSeconds > 60) { // Only if video is longer than 1 minute
        // Seek to a random position between 10% and 80% of the video
        final minSeek = (videoDuration.inSeconds * 0.1).round();
        final maxSeek = (videoDuration.inSeconds * 0.8).round();
        final randomSeconds = minSeek + (Random().nextInt(maxSeek - minSeek));
        
        print('🎬 [TVVideoPlayer] Seeking to random timestamp: ${randomSeconds}s / ${videoDuration.inSeconds}s');
        await _player.seek(Duration(seconds: randomSeconds));
      }
    } catch (e) {
      print('🎬 [TVVideoPlayer] Error seeking to random timestamp: $e');
    }
  }

  /// Starts the title folding animation cycle
  void _startTitleFoldCycle() {
    // Show title for 20 seconds, then fold it away
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted) {
        _titleFoldController.forward().then((_) {
          // After folding, wait 3 seconds then unfold
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              _titleFoldController.reverse().then((_) {
                // Restart the cycle
                _startTitleFoldCycle();
              });
            }
          });
        });
      }
    });
  }

  /// Extracts a clean title from a torrent filename
  String _extractCleanTitle(String torrentName) {
    print('🎬 [TVVideoPlayer] Cleaning title: "$torrentName"');
    
    // Remove file extension first
    String cleanName = torrentName.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,4}$'), '');
    
    // Try to extract title before year/quality/technical details
    final parts = cleanName.split(RegExp(r'\s+\d{4}|\s+1080p|\s+720p|\s+WEB|\s+h264|\s+x264|\s+\['));
    if (parts.isNotEmpty) {
      final result = parts.first.trim();
      if (result.isNotEmpty && result.length > 3) {
        print('🎬 [TVVideoPlayer] Extracted title: "$result"');
        return result;
      }
    }
    
    // Fallback: try SeriesParser
    try {
      final seriesInfo = SeriesParser.parseFilename(torrentName);
      if (seriesInfo.title != null && seriesInfo.title!.isNotEmpty) {
        print('🎬 [TVVideoPlayer] SeriesParser found title: "${seriesInfo.title}"');
        return seriesInfo.title!;
      }
    } catch (e) {
      print('🎬 [TVVideoPlayer] Error parsing torrent name: $e');
    }
    
    print('🎬 [TVVideoPlayer] Could not clean title, returning original: "$torrentName"');
    return torrentName;
  }



  Future<void> _surpriseMe() async {
    if (_isLoading.value) return; // Prevent multiple simultaneous attempts

    _isLoading.value = true;
    print('🎬 [TVVideoPlayer] Surprise Me clicked - finding new content...');

    // Try multiple torrents until we find a playable one
    const maxAttempts = 5; // Try up to 5 different torrents
    bool success = false;

    for (int attempt = 1; attempt <= maxAttempts && !success; attempt++) {
      try {
        print('🎬 [TVVideoPlayer] Attempt $attempt of $maxAttempts...');
        
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
          final newTitle = _extractCleanTitle(randomTorrent.name);
          
          // Load the new media in the same player instance
          await _player.open(mk.Media(newVideoUrl));
          print('🎬 [TVVideoPlayer] New media loaded: $newTitle');
          
          // Start playing automatically
          await _player.play();
          print('🎬 [TVVideoPlayer] New content started playing');
          
          // Try to seek to random timestamp (fallback if duration not available yet)
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && _isReady) {
              _seekToRandomTimestamp();
            }
          });
          
          // Update the UI to reflect the new title
          print('🎬 [TVVideoPlayer] Updating _currentTitle from "$_currentTitle" to "$newTitle"');
          setState(() {
            _currentTitle = newTitle;
          });
          print('🎬 [TVVideoPlayer] _currentTitle updated to: "$_currentTitle"');
          
          success = true;
          break;
        } else {
          print('🎬 [TVVideoPlayer] Attempt $attempt: No playable content found');
        }
      } catch (e) {
        print('🎬 [TVVideoPlayer] Attempt $attempt failed: $e');
        // Continue to next attempt instead of stopping
        if (attempt == maxAttempts) {
          // Only show error on final attempt
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to find playable content after $maxAttempts attempts'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    }

    if (!success) {
      print('🎬 [TVVideoPlayer] All attempts failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No playable content found. Try again!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    _isLoading.value = false;
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
        child: RawKeyboardListener(
          focusNode: FocusNode(),
          autofocus: true,
          onKey: (event) {
            if (event is! RawKeyDownEvent) return;
            
            // Space -> Toggle play/pause
            if (event.logicalKey == LogicalKeyboardKey.space) {
              if (_isReady) {
                if (_isPlaying) {
                  _player.pause();
                } else {
                  _player.play();
                }
              }
            }
            
            // Escape -> Go back
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              if (mounted && Navigator.of(context).canPop()) {
                // Use a microtask to avoid navigation conflicts
                Future.microtask(() {
                  if (mounted && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                });
              }
            }
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
              
              // Gesture detector for double-tap for Surprise Me
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () {
                  // Show brief feedback
                  _showDoubleTapFeedback.value = true;
                  Future.delayed(const Duration(milliseconds: 500), () {
                    _showDoubleTapFeedback.value = false;
                  });
                  _surpriseMe();
                },
              ),
              

              
              // Channel name - only visible if enabled (top left, TV-style)
              if (widget.channel.showChannelName)
                Positioned(
                  top: 20,
                  left: 20,
                  child: SafeArea(
                    child: Builder(
                      builder: (context) {
                        final displayText = _currentTitle.isNotEmpty ? _currentTitle : widget.channel.name;
                        print('🎬 [TVVideoPlayer] Displaying title: "$displayText" (currentTitle: "$_currentTitle", channelName: "${widget.channel.name}")');
                        return Text(
                          displayText,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4), // Less visible, more subtle
                            fontWeight: FontWeight.w300, // Light weight
                            fontSize: 14, // Smaller size
                            letterSpacing: 0.8, // Less spacing for subtlety
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                offset: const Offset(0.5, 0.5),
                                blurRadius: 1,
                              ),
                            ],
                          ),
                          maxLines: 1, // Single line for cleaner look
                          overflow: TextOverflow.ellipsis, // Ellipsis for overflow
                        );
                      },
                    ),
                  ),
                ),
              
                            // Channel name tag - only visible if enabled (bottom right)
              if (widget.channel.showLiveTag)
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: SafeArea(
                                          child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _liveDotController,
                            builder: (context, child) {
                              return Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B0000).withValues(alpha: _liveDotAnimation.value),
                                  shape: BoxShape.circle,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.channel.name,
                            style: const TextStyle(
                              color: Color(0xFF8B0000), // Dark red color
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black,
                                  offset: Offset(1, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ),
                ),
              
              // Double-tap feedback indicator
              ValueListenableBuilder<bool>(
                valueListenable: _showDoubleTapFeedback,
                builder: (context, showFeedback, child) {
                  return AnimatedOpacity(
                    opacity: showFeedback ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: showFeedback
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.all(Radius.circular(20)),
                              ),
                              child: const Text(
                                '🎲 Surprise Me!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
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

 