class MergedDetailSimklLabels {
  static String simklStatusLabel(String status) {
    switch (status) {
      case 'plantowatch':
        return 'Plan to Watch';
      case 'watching':
        return 'Watching';
      case 'hold':
        return 'On Hold';
      case 'completed':
        return 'Completed';
      case 'dropped':
        return 'Dropped';
      default:
        return status;
    }
  }
}
