class PikpakCatalogState {
  final List<Map<String, dynamic>> files = [];

  bool isLoading = false;

  bool initialLoad = true;

  String errorMessage = '';

  bool pikpakEnabled = false;

  bool showVideosOnly = true;

  bool ignoreSmallVideos = true;

  String? nextPageToken;

  bool hasMore = true;

  bool isLoadingMore = false;
}
