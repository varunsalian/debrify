class PremiumizeDateFormat {
  String formatUnixDate(int seconds) {
    if (seconds <= 0) return '';
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      final diff = DateTime.now().difference(date);
      if (diff.inDays == 0) {
        if (diff.inHours == 0) return '${diff.inMinutes}m ago';
        return '${diff.inHours}h ago';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}d ago';
      }
      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return '';
    }
  }
}
