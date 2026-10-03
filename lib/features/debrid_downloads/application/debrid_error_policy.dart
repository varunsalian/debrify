String getUserFriendlyErrorMessage(dynamic error) {
  final errorString = error.toString().toLowerCase();

  if (errorString.contains('file is not readily available in real debrid')) {
    return 'This torrent is not available on Real Debrid servers. Try a different torrent.';
  } else if (errorString.contains('invalid api key') ||
      errorString.contains('401')) {
    return 'Invalid API key. Please check your Real Debrid settings.';
  } else if (errorString.contains('account locked') ||
      errorString.contains('403')) {
    return 'Your Real Debrid account is locked. Please check your account status.';
  } else if (errorString.contains('network error') ||
      errorString.contains('connection')) {
    return 'Network connection error. Please check your internet connection.';
  } else if (errorString.contains('timeout')) {
    return 'Request timed out. Please try again.';
  } else if (errorString.contains('no files found in torrent')) {
    return 'No files found in this torrent.';
  } else if (errorString.contains('failed to get download link')) {
    return 'Unable to get download link. The torrent may not be available.';
  } else if (errorString.contains('long') || errorString.contains('int')) {
    return 'Data format error. Please refresh and try again.';
  } else if (errorString.contains('json')) {
    return 'Invalid response format. Please try again.';
  } else if (errorString.contains('failed to load torrents') ||
      errorString.contains('failed to load downloads')) {
    return 'Unable to load downloads. Please check your connection and try again.';
  } else {
    return 'Failed to add torrent. Please try again.';
  }
}

String getLinkUnrestrictErrorMessage(String errorMessage) {
  final errorString = errorMessage.toLowerCase();

  // Handle specific Real Debrid error codes and messages
  if (errorString.contains('infringing_file')) {
    return 'This file contains copyrighted content and cannot be unrestricted.';
  } else if (errorString.contains('invalid_link')) {
    return 'Invalid or unsupported link format.';
  } else if (errorString.contains('file_not_found')) {
    return 'File not found or no longer available.';
  } else if (errorString.contains('host_not_supported')) {
    return 'This file hosting service is not supported by Real Debrid.';
  } else if (errorString.contains('file_too_large')) {
    return 'File size exceeds Real Debrid limits.';
  } else if (errorString.contains('quota_exceeded')) {
    return 'Real Debrid quota exceeded. Please try again later.';
  } else if (errorString.contains('invalid api key') ||
      errorString.contains('401')) {
    return 'Invalid API key. Please check your Real Debrid settings.';
  } else if (errorString.contains('account_locked') ||
      errorString.contains('403')) {
    return 'Your Real Debrid account is locked. Please check your account status.';
  } else if (errorString.contains('network error') ||
      errorString.contains('connection')) {
    return 'Network connection error. Please check your internet connection.';
  } else if (errorString.contains('timeout')) {
    return 'Request timed out. Please try again.';
  } else {
    // For other errors, try to extract a clean message
    if (errorString.contains('failed to unrestrict link:')) {
      // Extract the status code and clean up the message
      final parts = errorMessage.split(' - ');
      if (parts.length > 1) {
        return 'Failed to unrestrict link (${parts[0].split(': ').last}). Please try a different link.';
      }
    }
    return 'Failed to unrestrict link. Please try a different link.';
  }
}
