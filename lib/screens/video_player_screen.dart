import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/file_utils.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? subtitle;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    this.subtitle,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  double _currentAspectRatio = 16 / 9; // Default aspect ratio
  double _currentBrightness = 1.0; // Current brightness level (0.0 to 1.0)
  bool _showBrightnessIndicator = false;
  String _brightnessText = '';
  bool _showBrightnessArea = false; // Show active area indicator
  bool _isFullscreen = false; // Track fullscreen state
  bool _showControls = true; // Show/hide video controls
  bool _isPlaying = true; // Track play/pause state

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    // Keep screen awake during video playback
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      // Check if this is a problematic video format
      final fileName = widget.title;
      final formatWarning = FileUtils.getVideoFormatWarning(fileName);
      
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _videoPlayerController.initialize();
      
      print('DEBUG: Response status: ${_videoPlayerController.value.isInitialized}');
      print('DEBUG: Response headers: ${_videoPlayerController.value.duration}');
      if (_videoPlayerController.value.isInitialized) {
        print('DEBUG: Response body: ${_videoPlayerController.value.position}');
      }
      
      // Add listener to track playing state
      _videoPlayerController.addListener(() {
        if (mounted) {
          setState(() {
            _isPlaying = _videoPlayerController.value.isPlaying;
          });
        }
      });

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: false, // We'll handle controls ourselves
        aspectRatio: _currentAspectRatio,
        // Disable built-in gesture handling to use our custom gestures
        allowPlaybackSpeedChanging: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFE50914),
          handleColor: const Color(0xFFE50914),
          backgroundColor: Colors.grey[600]!,
          bufferedColor: Colors.grey[400]!,
        ),
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFE50914),
            ),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.white,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading video',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      );

      setState(() {
        _isLoading = false;
      });
      
      // Show warning for problematic formats
      if (formatWarning.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showFormatWarning(formatWarning);
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = _getUserFriendlyErrorMessage(e, widget.title);
      });
    }
  }

  String _getUserFriendlyErrorMessage(dynamic error, String fileName) {
    final errorString = error.toString().toLowerCase();
    final isProblematic = FileUtils.isProblematicVideo(fileName);
    
    if (isProblematic) {
      return 'This video format is not well supported on mobile devices. Try downloading and playing with a different app.';
    } else if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    } else if (errorString.contains('format') || errorString.contains('codec')) {
      return 'Video format not supported. Try a different video file.';
    } else {
      return 'Failed to load video. Please try again.';
    }
  }

  void _showFormatWarning(String warning) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                warning,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // Aspect ratio options
  static const List<Map<String, dynamic>> _aspectRatioOptions = [
    {'name': 'Original', 'ratio': null, 'description': 'Original video aspect ratio'},
    {'name': '16:9', 'ratio': 16 / 9, 'description': 'Widescreen (HD)'},
    {'name': '4:3', 'ratio': 4 / 3, 'description': 'Standard (SD)'},
    {'name': '21:9', 'ratio': 21 / 9, 'description': 'Ultrawide'},
    {'name': '2.35:1', 'ratio': 2.35, 'description': 'Cinema scope'},
    {'name': '1.85:1', 'ratio': 1.85, 'description': 'Widescreen cinema'},
    {'name': '1:1', 'ratio': 1.0, 'description': 'Square'},
    {'name': '3:2', 'ratio': 3 / 2, 'description': 'Classic photo'},
    {'name': '5:4', 'ratio': 5 / 4, 'description': 'Large format'},
    {'name': '9:16', 'ratio': 9 / 16, 'description': 'Portrait'},
    {'name': 'Stretch', 'ratio': -1, 'description': 'Fill screen'},
    {'name': 'Fit', 'ratio': -2, 'description': 'Fit to screen'},
  ];

  void _handleDoubleTap(Offset position) {
    if (_videoPlayerController.value.isInitialized) {
      final currentPosition = _videoPlayerController.value.position;
      final duration = _videoPlayerController.value.duration;
      
      // Get the screen width to determine left/right side
      final screenWidth = MediaQuery.of(context).size.width;
      final orientation = MediaQuery.of(context).orientation;
      
      // Debug: Print double-tap details
      print('Double-tap: x=${position.dx}, screenWidth=$screenWidth, orientation=$orientation, currentPos=${currentPosition.inSeconds}s, duration=${duration.inSeconds}s');
      
      final isRightSide = position.dx > screenWidth / 2;
      
      Duration newPosition;
      
      if (isRightSide) {
        // Forward 10 seconds
        newPosition = currentPosition + const Duration(seconds: 10);
        print('Seeking forward 10s to ${newPosition.inSeconds}s');
      } else {
        // Backward 10 seconds
        newPosition = currentPosition - const Duration(seconds: 10);
        print('Seeking backward 10s to ${newPosition.inSeconds}s');
      }
      
      // Ensure position is within bounds
      if (newPosition < Duration.zero) {
        newPosition = Duration.zero;
      } else if (newPosition > duration) {
        newPosition = duration;
      }
      
      // Seek to new position
      _videoPlayerController.seekTo(newPosition);
    } else {
      print('Video controller not initialized for double-tap');
    }
  }

  void _handleBrightnessGesture(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final orientation = MediaQuery.of(context).orientation;
    
    // Determine the active area based on orientation
    double activeAreaWidth;
    if (orientation == Orientation.portrait) {
      // In portrait: left 1/3 of screen
      activeAreaWidth = screenWidth / 3;
    } else {
      // In landscape: left 1/4 of screen (smaller area for better UX)
      activeAreaWidth = screenWidth / 4;
    }
    
    // Debug: Print gesture details
    print('Brightness Gesture: x=${details.localPosition.dx}, y=${details.localPosition.dy}, activeArea=$activeAreaWidth, orientation=$orientation, deltaY=${details.delta.dy}');
    
    // Only respond to gestures on the left side of the screen
    if (details.localPosition.dx < activeAreaWidth) {
      // Calculate brightness change based on vertical movement
      // Up = increase brightness, Down = decrease brightness
      final brightnessChange = -details.delta.dy / screenHeight * 2.0; // Sensitivity factor
      
      print('Brightness change: $brightnessChange, current: $_currentBrightness');
      
      setState(() {
        _currentBrightness = (_currentBrightness + brightnessChange).clamp(0.0, 1.0);
        _showBrightnessIndicator = true;
        _showBrightnessArea = false; // Don't show the red line
        _brightnessText = '${(_currentBrightness * 100).round()}%';
      });
      
      // Set system brightness
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarBrightness: _currentBrightness > 0.5 ? Brightness.light : Brightness.dark,
      ));
      
      // Hide indicator after a delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showBrightnessIndicator = false;
            _showBrightnessArea = false;
          });
        }
      });
    }
  }

  void _resetBrightness() {
    setState(() {
      _currentBrightness = 1.0;
      _showBrightnessIndicator = false;
    });
  }

  void _togglePlayPause() {
    if (_videoPlayerController.value.isInitialized) {
      setState(() {
        if (_videoPlayerController.value.isPlaying) {
          _videoPlayerController.pause();
          _isPlaying = false;
        } else {
          _videoPlayerController.play();
          _isPlaying = true;
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    
    // Auto-hide controls after 3 seconds
    if (_showControls) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isPlaying) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _handleTap() {
    _toggleControls();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

    void _showAspectRatioDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.aspect_ratio,
                          color: Color(0xFF6366F1),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Aspect Ratio',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: _aspectRatioOptions.map((option) {
                        final isSelected = _currentAspectRatio == option['ratio'];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected 
                              ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                              : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected 
                                ? const Color(0xFF6366F1)
                                : const Color(0xFF475569).withValues(alpha: 0.3),
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              option['name'],
                              style: TextStyle(
                                color: isSelected ? const Color(0xFF6366F1) : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              option['description'],
                              style: TextStyle(
                                color: isSelected 
                                  ? const Color(0xFF6366F1).withValues(alpha: 0.7)
                                  : Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                            trailing: isSelected 
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF6366F1),
                                )
                              : null,
                            onTap: () {
                              setState(() {
                                _currentAspectRatio = option['ratio'] ?? 16 / 9;
                              });
                              Navigator.of(context).pop();
                              _updateChewieController();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                
                // Footer with cancel button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateChewieController() {
    if (_chewieController != null && _videoPlayerController.value.isInitialized) {
      _chewieController!.dispose();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: false, // We'll handle controls ourselves
        aspectRatio: _currentAspectRatio,
        // Disable built-in gesture handling to use our custom gestures
        allowPlaybackSpeedChanging: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFE50914),
          handleColor: const Color(0xFFE50914),
          backgroundColor: Colors.grey[600]!,
          bufferedColor: Colors.grey[400]!,
        ),
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFE50914),
            ),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.white,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading video',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 16, 
                vertical: MediaQuery.of(context).orientation == Orientation.portrait ? 12 : 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: MediaQuery.of(context).orientation == Orientation.portrait ? 16 : 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: MediaQuery.of(context).orientation == Orientation.portrait ? 12 : 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      // Show aspect ratio options
                      _showAspectRatioDialog();
                    },
                    icon: const Icon(
                      Icons.aspect_ratio,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      // Reset brightness
                      _resetBrightness();
                    },
                    icon: const Icon(
                      Icons.brightness_6,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      // Debug: Test gesture detection
                      print('Debug: Testing gesture detection');
                      print('Screen size: ${MediaQuery.of(context).size}');
                      print('Orientation: ${MediaQuery.of(context).orientation}');
                      print('Video controller initialized: ${_videoPlayerController.value.isInitialized}');
                    },
                    icon: const Icon(
                      Icons.bug_report,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      // Toggle fullscreen
                      if (_chewieController != null) {
                        _chewieController!.toggleFullScreen();
                        setState(() {
                          _isFullscreen = !_isFullscreen;
                        });
                      }
                    },
                    icon: Icon(
                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            
            // Video Player
            Expanded(
              child: _buildVideoPlayer(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFFE50914),
            ),
            SizedBox(height: 16),
            Text(
              'Loading video...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load video',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
                _initializePlayer();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_chewieController != null) {
      return Stack(
        children: [
          // Video player
          Chewie(controller: _chewieController!),
          
          // Overlay gesture detector for custom gestures
          Positioned.fill(
            child: GestureDetector(
              onTap: _handleTap,
              onDoubleTapDown: (details) {
                print('Double-tap detected at: ${details.localPosition}');
                _handleDoubleTap(details.localPosition);
              },
              onPanUpdate: (details) {
                print('Pan update detected at: ${details.localPosition}');
                _handleBrightnessGesture(details);
              },
              onPanStart: (details) {
                print('Pan start detected at: ${details.localPosition}');
                // Ensure gestures work in both orientations
                final orientation = MediaQuery.of(context).orientation;
                final screenWidth = MediaQuery.of(context).size.width;
                final activeAreaWidth = orientation == Orientation.portrait 
                  ? screenWidth / 3 
                  : screenWidth / 4;
                
                if (details.localPosition.dx < activeAreaWidth) {
                  setState(() {
                    _showBrightnessIndicator = true;
                    _brightnessText = '${(_currentBrightness * 100).round()}%';
                  });
                }
              },
              // Make the gesture detector transparent to touch events
              behavior: HitTestBehavior.opaque,
            ),
          ),
          
          // Custom video controls overlay
          if (_showControls)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    // Top controls
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.subtitle!,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _showAspectRatioDialog,
                            icon: const Icon(
                              Icons.aspect_ratio,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          IconButton(
                            onPressed: _resetBrightness,
                            icon: const Icon(
                              Icons.brightness_6,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              if (_chewieController != null) {
                                _chewieController!.toggleFullScreen();
                                setState(() {
                                  _isFullscreen = !_isFullscreen;
                                });
                              }
                            },
                            icon: Icon(
                              _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Center play/pause button
                    Expanded(
                      child: Center(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Bottom progress bar
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Progress bar
                          if (_videoPlayerController.value.isInitialized)
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFFE50914),
                                inactiveTrackColor: Colors.grey[600],
                                thumbColor: const Color(0xFFE50914),
                                overlayColor: const Color(0xFFE50914).withValues(alpha: 0.2),
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              ),
                              child: Slider(
                                value: _videoPlayerController.value.position.inMilliseconds.toDouble(),
                                max: _videoPlayerController.value.duration.inMilliseconds.toDouble(),
                                onChanged: (value) {
                                  _videoPlayerController.seekTo(Duration(milliseconds: value.toInt()));
                                },
                              ),
                            ),
                          
                          // Time indicators
                          if (_videoPlayerController.value.isInitialized)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_videoPlayerController.value.position),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(_videoPlayerController.value.duration),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
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
            ),
          
          // Brightness area indicator removed to prevent red line issue
          
          // Brightness indicator overlay
          if (_showBrightnessIndicator)
            Positioned(
              left: MediaQuery.of(context).orientation == Orientation.portrait ? 50 : 80,
              top: MediaQuery.of(context).size.height / 2 - 50,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFE50914),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _currentBrightness > 0.5 ? Icons.brightness_high : Icons.brightness_low,
                      color: const Color(0xFFE50914),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _brightnessText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return const Center(
      child: Text(
        'Video player not initialized',
        style: TextStyle(color: Colors.white),
      ),
    );
  }
} 