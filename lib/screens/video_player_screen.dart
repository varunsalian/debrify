import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/file_utils.dart';

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

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _openVideoInDefaultPlayer();
  }

  Future<void> _openVideoInDefaultPlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // Show format warning if needed
      final formatWarning = FileUtils.getVideoFormatWarning(widget.title);
      if (formatWarning.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showFormatWarning(formatWarning);
        });
      }

      // Debug: Print the video URL
      print('DEBUG: Attempting to open video URL: ${widget.videoUrl}');
      print('DEBUG: Video title: ${widget.title}');

      // Try different URL formats
      await _tryDifferentUrlFormats();
    } catch (e) {
      print('DEBUG: Error launching video: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = _getUserFriendlyErrorMessage(e, widget.title);
      });
    }
  }

  Future<void> _tryDifferentUrlFormats() async {
    final originalUrl = widget.videoUrl;
    final List<String> urlVariants = [
      originalUrl,
      // Try with different schemes
      originalUrl.replaceFirst('https://', 'http://'),
      // Try with explicit video MIME type
      '$originalUrl#video',
    ];

    for (final urlVariant in urlVariants) {
      try {
        print('DEBUG: Trying URL variant: $urlVariant');
        final Uri videoUri = Uri.parse(urlVariant);
        
        // First, check if we can launch the URL
        if (await canLaunchUrl(videoUri)) {
          print('DEBUG: URL can be launched, attempting to open...');
          
          // Try with external application mode first
          final launched = await launchUrl(
            videoUri,
            mode: LaunchMode.externalApplication,
          );
          
          if (launched) {
            print('DEBUG: Video launched successfully with URL: $urlVariant');
            // Close this screen after launching the video
            if (mounted) {
              Navigator.of(context).pop();
            }
            return;
          } else {
            print('DEBUG: Failed to launch URL with external application mode');
            // Try alternative launch methods
            final success = await _tryAlternativeLaunchMethods(videoUri);
            if (success) return;
          }
        } else {
          print('DEBUG: URL cannot be launched directly: $urlVariant');
        }
      } catch (e) {
        print('DEBUG: Error with URL variant $urlVariant: $e');
        continue; // Try next variant
      }
    }

    // If all URL variants fail, throw error
    throw Exception('No video player app found on device');
  }

  Future<bool> _tryAlternativeLaunchMethods(Uri videoUri) async {
    try {
      // Try with platform default mode
      print('DEBUG: Trying platform default mode...');
      final launched = await launchUrl(
        videoUri,
        mode: LaunchMode.platformDefault,
      );
      
      if (launched) {
        print('DEBUG: Video launched with platform default mode');
        if (mounted) {
          Navigator.of(context).pop();
        }
        return true;
      }

      // Try with inAppWebView mode as last resort
      print('DEBUG: Trying inAppWebView mode...');
      final launchedWebView = await launchUrl(
        videoUri,
        mode: LaunchMode.inAppWebView,
      );
      
      if (launchedWebView) {
        print('DEBUG: Video launched with inAppWebView mode');
        if (mounted) {
          Navigator.of(context).pop();
        }
        return true;
      }

      // Try opening in browser as last resort
      print('DEBUG: Trying to open in browser...');
      final launchedBrowser = await launchUrl(
        videoUri,
        mode: LaunchMode.externalApplication,
      );
      
      if (launchedBrowser) {
        print('DEBUG: Video opened in browser');
        if (mounted) {
          Navigator.of(context).pop();
        }
        return true;
      }

      // If all methods fail, return false
      print('DEBUG: All launch methods failed');
      return false;
    } catch (e) {
      print('DEBUG: Alternative launch methods failed: $e');
      return false;
    }
  }

  Future<void> _copyUrlToClipboard() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.videoUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video URL copied to clipboard'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Failed to copy URL to clipboard: $e');
    }
  }

  Future<void> _openInBrowser() async {
    try {
      final Uri videoUri = Uri.parse(widget.videoUrl);
      final launched = await launchUrl(
        videoUri,
        mode: LaunchMode.externalApplication,
      );
      
      if (launched) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to open in browser'),
              backgroundColor: Color(0xFFE50914),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('DEBUG: Failed to open in browser: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFE50914),
            duration: const Duration(seconds: 2),
          ),
        );
      }
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
    } else if (errorString.contains('no video player') || errorString.contains('launch')) {
      return 'No video player app found on your device. Please install a video player app like VLC, MX Player, or similar. You can also copy the URL and open it manually.';
    } else {
      return 'Failed to open video. Please try again.';
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
                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning,
                color: Color(0xFFF59E0B),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                warning,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: Color(0xFFE50914),
          ),
          const SizedBox(height: 24),
          const Text(
            'Opening Video Player...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.title,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (_hasError) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline,
              color: Color(0xFFE50914),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Video Playback Error',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF475569).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _errorMessage,
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _hasError = false;
                        _errorMessage = '';
                      });
                      _openVideoInDefaultPlayer();
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Close'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.grey),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _copyUrlToClipboard,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy URL'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      side: const BorderSide(color: Color(0xFF10B981)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: _openInBrowser,
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('Open in Browser'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B82F6),
                      side: const BorderSide(color: Color(0xFF3B82F6)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    // This should not be reached, but just in case
    return const Text(
      'Opening video...',
      style: TextStyle(color: Colors.white),
    );
  }
} 