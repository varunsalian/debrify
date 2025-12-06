import 'package:intl/intl.dart';

class Formatters {
  static String formatFileSize(int bytes) {
    if (bytes == 0) return 'Unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String formatDate(int unixTimestamp) {
    // Check if timestamp is in seconds or milliseconds
    // If it's a small number (less than year 3000 in seconds), assume it's seconds
    // Otherwise, assume it's already in milliseconds
    final timestamp = unixTimestamp < 32503680000 
        ? unixTimestamp * 1000  // Convert seconds to milliseconds
        : unixTimestamp;         // Already in milliseconds
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('MMM dd, yyyy').format(date);
  }

  static String formatDateString(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  static String formatDateTime(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
  }
} 