import 'package:flutter/material.dart';

/// A tile widget for displaying search statistics.
///
/// Shows the queue size and last search timestamp for Debrify TV.
class StatsTile extends StatelessWidget {
  final int queue;
  final DateTime? lastSearchedAt;

  const StatsTile({
    super.key,
    required this.queue,
    required this.lastSearchedAt,
  });

  @override
  Widget build(BuildContext context) {
    final last = lastSearchedAt == null
        ? '—'
        : '${lastSearchedAt!.hour.toString().padLeft(2, '0')}:${lastSearchedAt!.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Search snapshot',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Queue prepared: $queue • Last search: $last',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
