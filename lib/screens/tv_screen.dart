import 'package:flutter/material.dart';
import '../models/channel_hub.dart';
import '../services/channel_hub_service.dart';
import '../widgets/channel_hub_card.dart';
import '../widgets/add_channel_hub_dialog.dart';

class TVScreen extends StatefulWidget {
  const TVScreen({super.key});

  @override
  State<TVScreen> createState() => _TVScreenState();
}

class _TVScreenState extends State<TVScreen> {
  List<ChannelHub> _channelHubs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChannelHubs();
  }

  Future<void> _loadChannelHubs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final hubs = await ChannelHubService.getChannelHubs();
      setState(() {
        _channelHubs = hubs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading channel hubs: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _addChannelHub() async {
    final result = await showDialog<ChannelHub>(
      context: context,
      builder: (context) => const AddChannelHubDialog(),
    );

    if (result != null && mounted) {
      await _loadChannelHubs();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Channel Hub "${result.name}" created successfully!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  Future<void> _editChannelHub(ChannelHub editedHub) async {
    final success = await ChannelHubService.saveChannelHub(editedHub);
    if (success && mounted) {
      await _loadChannelHubs();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Channel Hub "${editedHub.name}" updated'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  Future<void> _deleteChannelHub(ChannelHub hub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Channel Hub'),
        content: Text('Are you sure you want to delete "${hub.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ChannelHubService.deleteChannelHub(hub.id);
      if (success && mounted) {
        await _loadChannelHubs();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Channel Hub "${hub.name}" deleted'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _channelHubs.isEmpty
              ? _buildEmptyState()
              : _buildChannelHubsList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addChannelHub,
        icon: const Icon(Icons.add),
        label: const Text('Add Channel Hub'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No Channel Hubs Yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first channel hub to organize your favorite TV series',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addChannelHub,
            icon: const Icon(Icons.add),
            label: const Text('Create Channel Hub'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelHubsList() {
    return RefreshIndicator(
      onRefresh: _loadChannelHubs,
      child: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.71, // 100/140 = 0.71
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        itemCount: _channelHubs.length,
        itemBuilder: (context, index) {
          final hub = _channelHubs[index];
                      return ChannelHubCard(
              hub: hub,
              onDelete: () => _deleteChannelHub(hub),
              onEdit: (editedHub) => _editChannelHub(editedHub),
            );
        },
      ),
    );
  }
} 