import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/formatters.dart';

/// Helper class to represent a folder item in the navigation
class _FolderItem {
  final String name;
  final String fullPath;
  final List<Map<String, dynamic>> files;
  final List<_FolderItem> subfolders;

  _FolderItem({
    required this.name,
    required this.fullPath,
    required this.files,
    required this.subfolders,
  });

  /// Get total count of files in this folder (recursively)
  int get totalFileCount {
    int count = files.length;
    for (final subfolder in subfolders) {
      count += subfolder.totalFileCount;
    }
    return count;
  }

  /// Get all file paths in this folder recursively
  Set<String> getAllFilePaths() {
    final Set<String> paths = {};
    for (final file in files) {
      paths.add(file['_fullPath'] as String);
    }
    for (final subfolder in subfolders) {
      paths.addAll(subfolder.getAllFilePaths());
    }
    return paths;
  }
}

class PikPakFileSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> files;
  final String torrentName;
  final void Function(List<Map<String, dynamic>>) onDownload;

  const PikPakFileSelectionDialog({
    super.key,
    required this.files,
    required this.torrentName,
    required this.onDownload,
  });

  @override
  State<PikPakFileSelectionDialog> createState() => _PikPakFileSelectionDialogState();
}

class _PikPakFileSelectionDialogState extends State<PikPakFileSelectionDialog> {
  late _FolderItem _rootFolder;
  late _FolderItem _currentFolder;
  final List<_FolderItem> _navigationStack = [];

  // Global selection state - tracks files by their full path
  late Map<String, Map<String, dynamic>> _selectedFilesByPath;

  // Track selected folders by their full path
  final Set<String> _selectedFolderPaths = {};

  final List<FocusNode> _itemFocusNodes = [];
  final List<bool> _itemFocusStates = [];
  final FocusNode _selectAllFocusNode = FocusNode();
  final FocusNode _downloadButtonFocusNode = FocusNode();
  final FocusNode _cancelButtonFocusNode = FocusNode();
  final FocusNode _backButtonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    // Build folder structure from flat file list
    _rootFolder = _buildFolderStructure(widget.files, widget.torrentName);
    _currentFolder = _rootFolder;

    // Start with NOTHING selected (Issue 2 fix)
    _selectedFilesByPath = {};

    _ensureFocusNodes();

    // Auto-focus first item after dialog is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _itemFocusNodes.isNotEmpty) {
        _itemFocusNodes[0].requestFocus();
      }
    });
  }

  /// Build folder structure from flat file list
  _FolderItem _buildFolderStructure(List<Map<String, dynamic>> allFiles, String rootName) {
    final Map<String, _FolderItem> folderMap = {};
    final List<Map<String, dynamic>> rootFiles = [];

    // Create root folder
    final root = _FolderItem(
      name: rootName,
      fullPath: '',
      files: rootFiles,
      subfolders: [],
    );
    folderMap[''] = root;

    // Process each file and build folder hierarchy
    for (final file in allFiles) {
      // Use _fullPath if available (from API's includePaths: true)
      // Otherwise fall back to name for backward compatibility
      final fileName = (file['_fullPath'] as String?) ?? (file['name'] as String? ?? 'Unknown');

      // Extract folder path from file name if it contains '/'
      if (fileName.contains('/')) {
        final parts = fileName.split('/');
        String currentPath = '';
        _FolderItem currentFolder = root;

        // Navigate/create folder hierarchy
        for (int i = 0; i < parts.length - 1; i++) {
          final folderName = parts[i];
          final newPath = currentPath.isEmpty ? folderName : '$currentPath/$folderName';

          if (!folderMap.containsKey(newPath)) {
            final newFolder = _FolderItem(
              name: folderName,
              fullPath: newPath,
              files: [],
              subfolders: [],
            );
            folderMap[newPath] = newFolder;
            currentFolder.subfolders.add(newFolder);
          }

          currentFolder = folderMap[newPath]!;
          currentPath = newPath;
        }

        // Add file to its folder with full path preserved
        final fileWithPath = Map<String, dynamic>.from(file);
        fileWithPath['_fullPath'] = fileName;
        fileWithPath['_displayName'] = parts.last;
        currentFolder.files.add(fileWithPath);
      } else {
        // File in root
        final fileWithPath = Map<String, dynamic>.from(file);
        fileWithPath['_fullPath'] = fileName;
        fileWithPath['_displayName'] = fileName;
        root.files.add(fileWithPath);
      }
    }

    // Sort folders and files alphabetically
    void sortFolder(_FolderItem folder) {
      folder.subfolders.sort((a, b) => a.name.compareTo(b.name));
      folder.files.sort((a, b) =>
        (a['_displayName'] as String).compareTo(b['_displayName'] as String));
      for (final subfolder in folder.subfolders) {
        sortFolder(subfolder);
      }
    }
    sortFolder(root);

    return root;
  }

  void _ensureFocusNodes() {
    // Dispose old focus nodes
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    _itemFocusNodes.clear();
    _itemFocusStates.clear();

    // Create focus nodes for current view items (folders + files)
    final itemCount = _currentFolder.subfolders.length + _currentFolder.files.length;
    for (int i = 0; i < itemCount; i++) {
      final node = FocusNode(debugLabel: 'item-$i');
      node.addListener(() {
        if (mounted) {
          setState(() {
            _itemFocusStates[i] = node.hasFocus;
          });
        }
      });
      _itemFocusNodes.add(node);
      _itemFocusStates.add(false);
    }
  }

  void _navigateToFolder(_FolderItem folder) {
    setState(() {
      _navigationStack.add(_currentFolder);
      _currentFolder = folder;
      _ensureFocusNodes();
    });

    // Focus first item in new folder
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _itemFocusNodes.isNotEmpty) {
        _itemFocusNodes[0].requestFocus();
      }
    });
  }

  void _navigateBack() {
    if (_navigationStack.isEmpty) return;

    setState(() {
      _currentFolder = _navigationStack.removeLast();
      _ensureFocusNodes();
    });

    // Focus first item
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _itemFocusNodes.isNotEmpty) {
        _itemFocusNodes[0].requestFocus();
      }
    });
  }

  /// Toggle folder selection (Issue 1 fix)
  /// When folder is selected, all files and subfolders within are selected recursively
  void _toggleFolder(_FolderItem folder) {
    setState(() {
      final isCurrentlySelected = _isFolderSelected(folder);

      if (isCurrentlySelected) {
        // Deselect folder and all its contents
        _deselectFolderRecursive(folder);
      } else {
        // Select folder and all its contents
        _selectFolderRecursive(folder);
      }
    });
  }

  /// Check if a folder is fully selected
  bool _isFolderSelected(_FolderItem folder) {
    // A folder is considered selected if all its files are selected
    // and all its subfolders are selected
    for (final file in folder.files) {
      if (!_selectedFilesByPath.containsKey(file['_fullPath'] as String)) {
        return false;
      }
    }
    for (final subfolder in folder.subfolders) {
      if (!_isFolderSelected(subfolder)) {
        return false;
      }
    }
    return folder.files.isNotEmpty || folder.subfolders.isNotEmpty;
  }

  /// Select folder and all its contents recursively
  void _selectFolderRecursive(_FolderItem folder) {
    _selectedFolderPaths.add(folder.fullPath);

    // Select all files in this folder
    for (final file in folder.files) {
      _selectedFilesByPath[file['_fullPath'] as String] = file;
    }

    // Recursively select all subfolders
    for (final subfolder in folder.subfolders) {
      _selectFolderRecursive(subfolder);
    }
  }

  /// Deselect folder and all its contents recursively
  void _deselectFolderRecursive(_FolderItem folder) {
    _selectedFolderPaths.remove(folder.fullPath);

    // Deselect all files in this folder
    for (final file in folder.files) {
      _selectedFilesByPath.remove(file['_fullPath'] as String);
    }

    // Recursively deselect all subfolders
    for (final subfolder in folder.subfolders) {
      _deselectFolderRecursive(subfolder);
    }
  }

  void _toggleFile(Map<String, dynamic> file) {
    setState(() {
      final path = file['_fullPath'] as String;
      if (_selectedFilesByPath.containsKey(path)) {
        _selectedFilesByPath.remove(path);
      } else {
        _selectedFilesByPath[path] = file;
      }
    });
  }

  /// Toggle select all in current folder (including folders and files)
  void _toggleSelectAllInCurrentFolder() {
    setState(() {
      final allItemsSelected = _areAllItemsSelectedInCurrentFolder();

      if (allItemsSelected) {
        // Deselect all folders and files in current folder
        for (final subfolder in _currentFolder.subfolders) {
          _deselectFolderRecursive(subfolder);
        }
        for (final file in _currentFolder.files) {
          _selectedFilesByPath.remove(file['_fullPath'] as String);
        }
      } else {
        // Select all folders and files in current folder
        for (final subfolder in _currentFolder.subfolders) {
          _selectFolderRecursive(subfolder);
        }
        for (final file in _currentFolder.files) {
          _selectedFilesByPath[file['_fullPath'] as String] = file;
        }
      }
    });
  }

  /// Check if all items (folders and files) in current folder are selected
  bool _areAllItemsSelectedInCurrentFolder() {
    // Check if all subfolders are selected
    for (final subfolder in _currentFolder.subfolders) {
      if (!_isFolderSelected(subfolder)) {
        return false;
      }
    }

    // Check if all files are selected
    for (final file in _currentFolder.files) {
      if (!_selectedFilesByPath.containsKey(file['_fullPath'] as String)) {
        return false;
      }
    }

    return _currentFolder.subfolders.isNotEmpty || _currentFolder.files.isNotEmpty;
  }

  void _onDownloadPressed() {
    final selectedFiles = _selectedFilesByPath.values.toList();
    Navigator.of(context).pop();
    widget.onDownload(selectedFiles);
  }

  /// Count selected folders in current view
  int _getSelectedFolderCount() {
    int count = 0;
    for (final subfolder in _currentFolder.subfolders) {
      if (_isFolderSelected(subfolder)) {
        count++;
      }
    }
    return count;
  }

  @override
  void dispose() {
    _selectAllFocusNode.dispose();
    _downloadButtonFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    _backButtonFocusNode.dispose();
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedFileCount = _selectedFilesByPath.length;
    final totalFiles = widget.files.length;
    final selectedFolderCount = _getSelectedFolderCount();
    final allItemsSelectedInCurrentFolder = _areAllItemsSelectedInCurrentFolder();

    // Build selection count text
    String selectionText;
    if (selectedFolderCount > 0 && selectedFileCount > 0) {
      selectionText = '$selectedFolderCount folder${selectedFolderCount > 1 ? 's' : ''} + $selectedFileCount file${selectedFileCount > 1 ? 's' : ''} selected';
    } else if (selectedFolderCount > 0) {
      selectionText = '$selectedFolderCount folder${selectedFolderCount > 1 ? 's' : ''} selected ($selectedFileCount files)';
    } else if (selectedFileCount > 0) {
      selectionText = '$selectedFileCount of $totalFiles files selected';
    } else {
      selectionText = 'No items selected';
    }

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: 600,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Files to Download',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectionText,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Focus(
                    focusNode: _cancelButtonFocusNode,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          (event.logicalKey == LogicalKeyboardKey.select ||
                              event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey == LogicalKeyboardKey.space)) {
                        Navigator.of(context).pop();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Breadcrumb / Current Path
              if (_navigationStack.isNotEmpty)
                Row(
                  children: [
                    Focus(
                      focusNode: _backButtonFocusNode,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.space)) {
                          _navigateBack();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextButton.icon(
                        onPressed: _navigateBack,
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Back'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentFolder.name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

              if (_navigationStack.isNotEmpty) const SizedBox(height: 8),

              // Select All / Deselect All (for current folder)
              if (_currentFolder.files.isNotEmpty || _currentFolder.subfolders.isNotEmpty)
                Focus(
                  focusNode: _selectAllFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      _toggleSelectAllInCurrentFolder();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: _selectAllFocusNode.hasFocus
                          ? Border.all(
                              color: const Color(0xFF3B82F6),
                              width: 2,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CheckboxListTile(
                      value: allItemsSelectedInCurrentFolder,
                      tristate: true,
                      onChanged: (_) => _toggleSelectAllInCurrentFolder(),
                      title: Text(
                        allItemsSelectedInCurrentFolder ? 'Deselect All in Folder' : 'Select All in Folder',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(0xFF10B981),
                      checkColor: Colors.white,
                      tileColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),

              if (_currentFolder.files.isNotEmpty || _currentFolder.subfolders.isNotEmpty)
                const Divider(color: Colors.white24, height: 24),

              // Folder and file list
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _currentFolder.subfolders.length + _currentFolder.files.length,
                  itemBuilder: (context, index) {
                    final isFolder = index < _currentFolder.subfolders.length;

                    if (isFolder) {
                      // Render folder with checkbox (Issue 1 fix)
                      final folder = _currentFolder.subfolders[index];
                      final isFocused = _itemFocusStates[index];
                      final isFolderSelected = _isFolderSelected(folder);
                      final fileCount = folder.totalFileCount;

                      return Focus(
                        focusNode: _itemFocusNodes[index],
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            // Space/Enter/Select on folders should toggle selection, not navigate
                            if (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.space) {
                              _toggleFolder(folder);
                              return KeyEventResult.handled;
                            }
                            // Use right arrow to navigate into folder
                            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                              _navigateToFolder(folder);
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            border: isFocused
                                ? Border.all(
                                    color: const Color(0xFF3B82F6),
                                    width: 2,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: CheckboxListTile(
                            value: isFolderSelected,
                            onChanged: (_) => _toggleFolder(folder),
                            title: Row(
                              children: [
                                const Icon(
                                  Icons.folder,
                                  color: Color(0xFFFBBF24),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    folder.name,
                                    style: const TextStyle(color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '$fileCount file${fileCount != 1 ? 's' : ''}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            secondary: IconButton(
                              icon: const Icon(
                                Icons.chevron_right,
                                color: Colors.white54,
                              ),
                              onPressed: () => _navigateToFolder(folder),
                              tooltip: 'Open folder',
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: const Color(0xFF10B981),
                            checkColor: Colors.white,
                            tileColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      );
                    } else {
                      // Render file
                      final fileIndex = index - _currentFolder.subfolders.length;
                      final file = _currentFolder.files[fileIndex];
                      final fileName = file['_displayName'] as String? ?? 'Unknown';
                      final fullPath = file['_fullPath'] as String;
                      final sizeBytes = int.tryParse(file['size']?.toString() ?? '0') ?? 0;
                      final sizeStr = Formatters.formatFileSize(sizeBytes);
                      final isSelected = _selectedFilesByPath.containsKey(fullPath);
                      final isFocused = _itemFocusStates[index];

                      return Focus(
                        focusNode: _itemFocusNodes[index],
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.select ||
                                  event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey == LogicalKeyboardKey.space)) {
                            _toggleFile(file);
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            border: isFocused
                                ? Border.all(
                                    color: const Color(0xFF3B82F6),
                                    width: 2,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: CheckboxListTile(
                            value: isSelected,
                            onChanged: (_) => _toggleFile(file),
                            title: Text(
                              fileName,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              sizeStr,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            secondary: const Icon(
                              Icons.insert_drive_file,
                              color: Colors.white70,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: const Color(0xFF10B981),
                            checkColor: Colors.white,
                            tileColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Download button
              Focus(
                focusNode: _downloadButtonFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    if (selectedFileCount > 0) {
                      _onDownloadPressed();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: selectedFileCount > 0 ? _onDownloadPressed : null,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF10B981),
                      disabledBackgroundColor: Colors.white24,
                      disabledForegroundColor: Colors.white38,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      selectedFileCount > 0
                          ? 'Download $selectedFileCount file${selectedFileCount > 1 ? 's' : ''}'
                          : 'No files selected',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
