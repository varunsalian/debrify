// Folder navigation state
class PikpakNavigationState {
  String? currentFolderId;

  String currentFolderName = 'My Files';

  final List<({String? id, String name})> navigationStack = [];

  String? restrictedFolderId;

  String? restrictedFolderName;

  bool isAtRestrictedRoot = false;
}
