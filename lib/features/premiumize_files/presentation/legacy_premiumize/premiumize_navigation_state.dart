class PremiumizeNavigationState {
  // Folder navigation state (server-side, by id).
  String? currentFolderId; // null = root

  String currentFolderName = 'My Files';

  final List<({String? id, String name})> navigationStack = [];
}
