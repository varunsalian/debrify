import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math';
import '../models/channel_hub.dart';
import '../screens/channel_hub_detail_screen.dart';
import '../widgets/add_channel_hub_dialog.dart';

class ChannelHubCard extends StatefulWidget {
  final ChannelHub hub;
  final VoidCallback onDelete;
  final Function(ChannelHub) onEdit;

  const ChannelHubCard({
    super.key,
    required this.hub,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<ChannelHubCard> createState() => _ChannelHubCardState();
}

class _ChannelHubCardState extends State<ChannelHubCard>
    with TickerProviderStateMixin {
  late AnimationController _slideshowController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  int _currentImageIndex = 0;
  List<dynamic> _shuffledContent = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    // Combine series and movies for slideshow
    _shuffledContent = <dynamic>[];
    _shuffledContent.addAll(widget.hub.series);
    _shuffledContent.addAll(widget.hub.movies);
    _shuffledContent.shuffle(_random);
    
    _slideshowController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    if (_shuffledContent.isNotEmpty) {
      _startSlideshow();
    }
  }

  void _startSlideshow() {
    _slideshowController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextImage();
        _slideshowController.reset();
        _slideshowController.forward();
      }
    });
    _slideshowController.forward();
  }

  void _nextImage() {
    if (_shuffledContent.isEmpty) return;
    
    setState(() {
      _fadeController.reverse().then((_) {
        _currentImageIndex = (_currentImageIndex + 1) % _shuffledContent.length;
        _fadeController.forward();
      });
    });
  }

  @override
  void dispose() {
    _slideshowController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                Icons.edit_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(context).pop();
                _editChannelHub(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Delete'),
              onTap: () {
                Navigator.of(context).pop();
                _deleteChannelHub(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.info_rounded,
                color: Theme.of(context).colorScheme.secondary,
              ),
              title: const Text('Info'),
              onTap: () {
                Navigator.of(context).pop();
                _showChannelHubInfo(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _editChannelHub(BuildContext context) async {
    final result = await showDialog<ChannelHub>(
      context: context,
      builder: (context) => AddChannelHubDialog(
        initialHub: widget.hub,
      ),
    );

    if (result != null && mounted) {
      widget.onEdit(result);
    }
  }

  void _deleteChannelHub(BuildContext context) async {
    widget.onDelete();
  }

  void _showChannelHubInfo(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChannelHubDetailScreen(hub: widget.hub),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 100,
        height: 140, // Increased height to accommodate name container
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Image Container
            Expanded(
              flex: 4, // Takes up most of the space
              child: Stack(
                children: [
                  // Background Image
                  _buildBackgroundImage(context),
                  // Options Menu Button
                  _buildOptionsButton(context),
                ],
              ),
            ),
            // Channel Name Container
            _buildNameContainer(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundImage(BuildContext context) {
    if (_shuffledContent.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: Icon(
            Icons.tv_off_rounded,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            size: 24,
          ),
        ),
      );
    }

    final currentContent = _shuffledContent[_currentImageIndex];
    final imageUrl = currentContent is SeriesInfo 
        ? currentContent.originalImageUrl 
        : (currentContent as MovieInfo).originalImageUrl;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: imageUrl != null
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildLoadingPlaceholder(context),
                errorWidget: (context, url, error) => _buildErrorPlaceholder(context),
              )
            : _buildErrorPlaceholder(context),
      ),
    );
  }

  Widget _buildLoadingPlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Icon(
          Icons.signal_wifi_off_rounded,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildNameContainer(BuildContext context) {
    final totalCount = widget.hub.series.length + widget.hub.movies.length;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
            Colors.black.withValues(alpha: 0.9),
          ],
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.hub.name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 10,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '$totalCount items',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsButton(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: GestureDetector(
        onTap: () => _showOptionsMenu(context),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.more_vert_rounded,
            size: 12,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
} 