import 'package:flutter/material.dart';
import '../models/tv_channel.dart';
import '../models/tv_channel_torrent.dart';
import '../utils/formatters.dart';

class TVChannelCard extends StatelessWidget {
  final TVChannel channel;
  final List<TVChannelTorrent> torrents;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  final VoidCallback? onInfo;

  const TVChannelCard({
    super.key,
    required this.channel,
    required this.torrents,
    required this.onRefresh,
    required this.onDelete,
    this.onTap,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = torrents.isNotEmpty;
    
    return Card(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isEnabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isEnabled 
                ? [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.9),
                  ]
                : [
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                    Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
                  ],
            ),
          ),
          child: Stack(
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    // Top section with icon and count
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Channel icon
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isEnabled 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.tv_rounded,
                            color: isEnabled 
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            size: 12,
                          ),
                        ),
                        
                        // Count badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isEnabled 
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isEnabled ? '${torrents.length}' : '...',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isEnabled 
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const Spacer(),
                    
                    // Channel name - fills the middle
                    Text(
                      channel.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isEnabled 
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const Spacer(),
                    
                    // Status indicator at bottom
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: isEnabled 
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isEnabled ? Icons.play_circle : Icons.pending,
                            size: 10,
                            color: isEnabled 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            isEnabled ? 'Ready' : 'Loading',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isEnabled 
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Action buttons (top right)
              Positioned(
                top: 2,
                right: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Info button
                    if (onInfo != null)
                      Container(
                        margin: const EdgeInsets.only(right: 2),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: onInfo,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.info_outline,
                                size: 8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    
                    // Menu button
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 12,
                        color: isEnabled 
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'refresh':
                            onRefresh();
                            break;
                          case 'delete':
                            onDelete();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'refresh',
                          child: Row(
                            children: [
                              Icon(Icons.refresh),
                              SizedBox(width: 8),
                              Text('Refresh'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 