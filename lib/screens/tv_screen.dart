import 'package:flutter/material.dart';
import '../models/tv_channel.dart';
import '../models/tv_channel_torrent.dart';
import '../services/tv_service.dart';
import '../utils/formatters.dart';
import '../widgets/tv_channel_card.dart';
import '../widgets/add_channel_dialog.dart';
import '../screens/tv_video_player_screen.dart';
import '../services/tv_playback_service.dart';

class TVScreen extends StatefulWidget {
  const TVScreen({super.key});

  @override
  State<TVScreen> createState() => _TVScreenState();
}

class _TVScreenState extends State<TVScreen> {
  List<TVChannel> _channels = [];
  bool _isLoading = false;
  Map<String, List<TVChannelTorrent>> _channelTorrents = {};

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final channels = await TVService.getChannels();
      setState(() {
        _channels = channels;
      });

      // Load torrents for each channel
      for (final channel in channels) {
        final torrents = await TVService.getChannelTorrents(channel.id);
        setState(() {
          _channelTorrents[channel.id] = torrents;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading channels: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addChannel() async {
    final result = await showDialog<TVChannel>(
      context: context,
      builder: (context) => const AddChannelDialog(),
    );

    if (result != null) {
      try {
        // Add the channel to database
        await TVService.addChannel(result);
        
        // Add channel to UI immediately in disabled state
        setState(() {
          _channels.add(result);
          _channelTorrents[result.id] = []; // Empty list for loading state
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Channel "${result.name}" added! Searching for content...'),
            ),
          );
        }
        
        // Search for torrents in background
        _loadTorrentsForChannel(result);
        
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding channel: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadTorrentsForChannel(TVChannel channel) async {
    try {
      // Search for torrents
      await TVService.refreshChannelContent(channel);
      
      // Load the torrents
      final torrents = await TVService.getChannelTorrents(channel.id);
      
      if (mounted) {
        setState(() {
          _channelTorrents[channel.id] = torrents;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${channel.name}: Found ${torrents.length} torrents!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _channelTorrents[channel.id] = []; // Keep empty list on error
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading content for ${channel.name}: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _refreshChannel(TVChannel channel) async {
    try {
      await TVService.refreshChannelContent(channel);
      final torrents = await TVService.getChannelTorrents(channel.id);
      setState(() {
        _channelTorrents[channel.id] = torrents;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${channel.name} refreshed successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing ${channel.name}: $e')),
        );
      }
    }
  }

  Future<void> _onChannelTap(TVChannel channel, List<TVChannelTorrent> torrents) async {
    print('🎬 [TV] Channel tap started for: ${channel.name}');
    print('🎬 [TV] Available torrents: ${torrents.length}');
    
    if (torrents.isEmpty) {
      print('🎬 [TV] No torrents available for channel: ${channel.name}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No content available for this channel. Try refreshing first.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    print('🎬 [TV] Showing loading dialog...');
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF1E293B),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text(
              'Finding playable content...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      print('🎬 [TV] Calling TVPlaybackService.playRandomTorrentFromChannel...');
      // Attempt to play a random torrent from the channel
      final result = await TVPlaybackService.playRandomTorrentFromChannel(channel, torrents);
      print('🎬 [TV] TVPlaybackService result: ${result != null ? 'SUCCESS' : 'NULL'}');
      
      // Close loading dialog
      if (mounted) {
        print('🎬 [TV] Closing loading dialog...');
        Navigator.of(context).pop();
      }

      if (result != null && mounted) {
        print('🎬 [TV] Navigating to TVVideoPlayerScreen...');
        print('🎬 [TV] Video URL: ${result['downloadLink']}');
        print('🎬 [TV] Title: ${result['files']?.isNotEmpty == true ? result['files'][0]['name'] ?? channel.name : channel.name}');
        
        // Navigate to TV video player
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TVVideoPlayerScreen(
              videoUrl: result['downloadLink'],
              title: result['files']?.isNotEmpty == true 
                  ? result['files'][0]['name'] ?? channel.name
                  : channel.name,
              channel: channel,
              torrents: torrents,
              debridResult: result,
            ),
          ),
        );
      } else {
        print('🎬 [TV] No result from TVPlaybackService or widget not mounted');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No playable content found.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('🎬 [TV] Error in _onChannelTap: $e');
      print('🎬 [TV] Stack trace: ${StackTrace.current}');
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load content: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _deleteChannel(TVChannel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Channel'),
        content: Text('Are you sure you want to delete "${channel.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await TVService.deleteChannel(channel.id);
      setState(() {
        _channels.removeWhere((c) => c.id == channel.id);
        _channelTorrents.remove(channel.id);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${channel.name} deleted successfully!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _channels.isEmpty
              ? _buildEmptyState()
              : _buildChannelsGrid(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addChannel,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.tv_rounded,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No TV Channels Yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first channel to get started',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addChannel,
            icon: const Icon(Icons.add),
            label: const Text('Add Channel'),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelsGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _channels.length,
      itemBuilder: (context, index) {
        final channel = _channels[index];
        final torrents = _channelTorrents[channel.id] ?? [];
        
        return TVChannelCard(
          channel: channel,
          torrents: torrents,
          onRefresh: () => _refreshChannel(channel),
          onDelete: () => _deleteChannel(channel),
          onTap: () => _onChannelTap(channel, torrents),
          onInfo: () => _showChannelInfo(channel, torrents),
        );
      },
    );
  }

  void _showChannelInfo(TVChannel channel, List<TVChannelTorrent> torrents) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.tv_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(channel.name),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Keywords
              Text(
                'Keywords',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: channel.keywords.map((keyword) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      keyword,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
              
              const SizedBox(height: 20),
              
              // Recent content
              Text(
                'Recent Content (${torrents.length} total)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (torrents.isNotEmpty) ...[
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: torrents.take(5).length,
                    itemBuilder: (context, index) {
                      final torrent = torrents[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.video_file,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        title: Text(
                          torrent.name,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          '${torrent.seeders}↑',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                Text(
                  'No content available',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
              
              const SizedBox(height: 16),
              
              // Stats
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Updated ${Formatters.formatRelativeTime(channel.lastUpdated)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
} 