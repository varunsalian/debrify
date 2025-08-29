import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel_hub.dart';
import '../widgets/shimmer.dart';

class MovieDetailScreen extends StatefulWidget {
  final MovieInfo movie;

  const MovieDetailScreen({
    super.key,
    required this.movie,
  });

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.movie.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Movie poster and basic info
            _buildMovieHeader(),
            const SizedBox(height: 24),
            
            // Movie details
            _buildMovieDetails(),
            const SizedBox(height: 24),
            
            // Synopsis
            if (widget.movie.summary != null && widget.movie.summary!.isNotEmpty) ...[
              _buildSynopsis(),
              const SizedBox(height: 24),
            ],
            
            // Genres
            if (widget.movie.genres.isNotEmpty) ...[
              _buildGenres(),
              const SizedBox(height: 24),
            ],
            
            // Cast (if available)
            if (widget.movie.actors.isNotEmpty) ...[
              _buildCast(),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMovieHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Movie poster
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 120,
            height: 180,
            child: widget.movie.originalImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: widget.movie.originalImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Shimmer(),
                    errorWidget: (context, url, error) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.movie_rounded,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        size: 48,
                      ),
                    ),
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.movie_rounded,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      size: 48,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        
        // Movie info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.movie.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              // Year and runtime
              Row(
                children: [
                  if (widget.movie.year != null) ...[
                    Text(
                      widget.movie.year!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (widget.movie.runtimeSeconds > 0) ...[
                    Text(
                      '${(widget.movie.runtimeSeconds / 60).round()} min',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              
              // Rating
              if (widget.movie.rating != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.movie.rating!.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              

            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMovieDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Movie Details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // Director
            if (widget.movie.director != null && widget.movie.director!.isNotEmpty) ...[
              _buildDetailRow('Director', widget.movie.director!),
              const SizedBox(height: 8),
            ],
            

            
            // Language
            if (widget.movie.language != null && widget.movie.language!.isNotEmpty) ...[
              _buildDetailRow('Language', widget.movie.language!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildSynopsis() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Synopsis',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.movie.summary!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenres() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Genres',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.movie.genres.map((genre) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    genre,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCast() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cast',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.movie.actors.take(10).map((actor) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    actor,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (widget.movie.actors.length > 10) ...[
              const SizedBox(height: 8),
              Text(
                'and ${widget.movie.actors.length - 10} more...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
} 