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

      // Try to open the video URL - this will show the native Android app chooser
      final Uri videoUri = Uri.parse(widget.videoUrl);
      
      if (await canLaunchUrl(videoUri)) {
        await launchUrl(
          videoUri,
          mode: LaunchMode.externalApplication,
        );
        
        // Close this screen after launching the video
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        throw Exception('No video player app found on device');
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
    } else if (errorString.contains('no video player') || errorString.contains('launch')) {
      return 'No video player app found on your device. Please install a video player app.';
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