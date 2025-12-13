import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pikpak_api_service.dart';
import '../services/android_native_downloader.dart';

class PikPakFolderPickerDialog extends StatefulWidget {
  final String? initialFolderId;

  const PikPakFolderPickerDialog({super.key, this.initialFolderId});

  @override
  State<PikPakFolderPickerDialog> createState() =>
      _PikPakFolderPickerDialogState();
}

class _FolderNode {
  final String id;
  final String name;
  final int level;
  bool isExpanded;
  bool isLoading;
  bool hasLoadedChildren;
  List<_FolderNode> children;

  _FolderNode({
    required this.id,
    required this.name,
    required this.level,
    this.isExpanded = false,
    this.isLoading = false,
    this.hasLoadedChildren = false,
    this.children = const [],
  });
}

class _PikPakFolderPickerDialogState extends State<PikPakFolderPickerDialog> {
  final PikPakApiService _apiService = PikPakApiService();

  List<_FolderNode> _rootFolders = [];
  bool _isLoading = false;
  String? _errorMessage;

  String? _selectedFolderId;
  String? _selectedFolderName;

  // TV Navigation support
  bool _isTelevision = false;
  final List<FocusNode> _folderFocusNodes = [];
  final List<ValueNotifier<bool>> _folderFocusStates = [];
  final FocusNode _cancelButtonFocusNode = FocusNode(
    debugLabel: 'cancel-button',
  );
  final FocusNode _confirmButtonFocusNode = FocusNode(
    debugLabel: 'confirm-button',
  );
  final FocusNode _closeButtonFocusNode = FocusNode(debugLabel: 'close-button');

  @override
  void initState() {
    super.initState();
    _detectTelevision();
    _loadRootFolders();
  }

  Future<void> _detectTelevision() async {
    try {
      final isTv = await AndroidNativeDownloader.isTelevision();
      if (mounted) {
        setState(() {
          _isTelevision = isTv;
        });
      }
    } catch (_) {
      // Not on Android TV
    }
  }

  Future<void> _loadRootFolders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _apiService.listFiles(
        parentId: null, // Root folder
        limit: 100,
      );

      // Filter to show only folders
      final folders = result.files.where((file) {
        return file['kind'] == 'drive#folder';
      }).toList();

      // Sort folders alphabetically
      folders.sort((a, b) {
        final nameA = (a['name'] as String? ?? '').toLowerCase();
        final nameB = (b['name'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      // Convert to folder nodes
      final folderNodes = folders.map((folder) {
        return _FolderNode(
          id: folder['id'] as String,
          name: folder['name'] as String,
          level: 0,
        );
      }).toList();

      setState(() {
        _rootFolders = folderNodes;
        _isLoading = false;
      });
      _ensureFocusNodes();
      _autoFocusFirstFolder();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load folders: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFolderChildren(_FolderNode folder) async {
    if (folder.hasLoadedChildren) {
      // Already loaded, just toggle expansion
      setState(() {
        folder.isExpanded = !folder.isExpanded;
      });
      return;
    }

    // Load children
    setState(() {
      folder.isLoading = true;
    });

    try {
      final result = await _apiService.listFiles(
        parentId: folder.id,
        limit: 100,
      );

      // Filter to show only folders
      final subfolders = result.files.where((file) {
        return file['kind'] == 'drive#folder';
      }).toList();

      // Sort folders alphabetically
      subfolders.sort((a, b) {
        final nameA = (a['name'] as String? ?? '').toLowerCase();
        final nameB = (b['name'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      // Convert to folder nodes
      final childNodes = subfolders.map((subfolder) {
        return _FolderNode(
          id: subfolder['id'] as String,
          name: subfolder['name'] as String,
          level: folder.level + 1,
        );
      }).toList();

      setState(() {
        folder.children = childNodes;
        folder.hasLoadedChildren = true;
        folder.isExpanded = true;
        folder.isLoading = false;
      });
      _ensureFocusNodes();
    } catch (e) {
      setState(() {
        folder.isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load subfolders: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _selectFolder(String folderId, String folderName) {
    setState(() {
      _selectedFolderId = folderId;
      _selectedFolderName = folderName;
    });
  }

  void _ensureFocusNodes() {
    final flatFolders = _getFlattenedFolders();

    // Dispose old focus nodes if list shrunk
    while (_folderFocusNodes.length > flatFolders.length) {
      _folderFocusNodes.removeLast().dispose();
      _folderFocusStates.removeLast().dispose();
    }

    // Add new focus nodes if list grew
    while (_folderFocusNodes.length < flatFolders.length) {
      final index = _folderFocusNodes.length;
      final node = FocusNode(debugLabel: 'folder-item-$index');
      final focusState = ValueNotifier<bool>(false);

      node.addListener(() {
        if (!mounted) return;
        focusState.value = node.hasFocus;
      });

      _folderFocusNodes.add(node);
      _folderFocusStates.add(focusState);
    }
  }

  void _autoFocusFirstFolder() {
    if (_isTelevision && _folderFocusNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _folderFocusNodes.isNotEmpty) {
          _folderFocusNodes[0].requestFocus();
        }
      });
    }
  }

  List<_FolderNode> _getFlattenedFolders() {
    final List<_FolderNode> flattened = [];

    void addFolderAndChildren(_FolderNode folder) {
      flattened.add(folder);
      if (folder.isExpanded && folder.children.isNotEmpty) {
        for (final child in folder.children) {
          addFolderAndChildren(child);
        }
      }
    }

    for (final folder in _rootFolders) {
      addFolderAndChildren(folder);
    }

    return flattened;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenHeight = screenSize.height;
    final screenWidth = screenSize.width;

    // Calculate responsive dimensions
    final dialogWidth = (screenWidth * 0.85).clamp(300.0, 600.0);
    final dialogHeight = (screenHeight * 0.8).clamp(400.0, 700.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dialogWidth,
                maxHeight: dialogHeight,
                minWidth: 300,
                minHeight: 400,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: EdgeInsets.all(screenWidth < 400 ? 16 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.folder_open, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Select Folder to Restrict',
                            style: TextStyle(
                              fontSize: screenWidth < 400 ? 16 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Focus(
                          focusNode: _closeButtonFocusNode,
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Folder list
                    Flexible(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _errorMessage != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: Colors.red[300],
                                  ),
                                  const SizedBox(height: 16),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Text(
                                      _errorMessage!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.red[300]),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: _loadRootFolders,
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : _rootFolders.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.folder_off,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No folders found in your account',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _getFlattenedFolders().length,
                              itemBuilder: (context, index) {
                                return _buildFolderItem(context, index);
                              },
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Focus(
                          focusNode: _cancelButtonFocusNode,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Focus(
                            focusNode: _confirmButtonFocusNode,
                            child: FilledButton.icon(
                              onPressed: _selectedFolderId != null
                                  ? () {
                                      Navigator.pop(context, {
                                        'folderId': _selectedFolderId,
                                        'folderName': _selectedFolderName,
                                      });
                                    }
                                  : null,
                              icon: const Icon(Icons.check, size: 18),
                              label: Text(
                                _selectedFolderId != null
                                    ? 'Restrict to "${_truncateFolderName(_selectedFolderName ?? '')}"'
                                    : 'Select a folder',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFolderItem(BuildContext context, int index) {
    final folder = _getFlattenedFolders()[index];
    final isSelected = _selectedFolderId == folder.id;
    final canExpand = !folder.hasLoadedChildren || folder.children.isNotEmpty;

    final itemWidget = InkWell(
      onTap: () => _selectFolder(folder.id, folder.name),
      child: Container(
        padding: EdgeInsets.only(
          left: 8.0 + (folder.level * 24.0),
          right: 8.0,
          top: 8.0,
          bottom: 8.0,
        ),
        child: Row(
          children: [
            // Expand/collapse icon
            SizedBox(
              width: 24,
              height: 24,
              child: canExpand
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: folder.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              folder.isExpanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 20,
                            ),
                      onPressed: folder.isLoading
                          ? null
                          : () => _loadFolderChildren(folder),
                    )
                  : null,
            ),
            const SizedBox(width: 8),

            // Radio button
            Radio<String>(
              value: folder.id,
              groupValue: _selectedFolderId,
              onChanged: (value) => _selectFolder(folder.id, folder.name),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),

            // Folder icon
            const Icon(Icons.folder, color: Colors.amber, size: 20),
            const SizedBox(width: 8),

            // Folder name
            Expanded(
              child: Text(
                folder.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Wrap with Focus for TV navigation
    if (_isTelevision && index < _folderFocusNodes.length) {
      return Focus(
        focusNode: _folderFocusNodes[index],
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          // Arrow Right: Expand folder
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (canExpand && !folder.isExpanded && !folder.isLoading) {
              _loadFolderChildren(folder);
              return KeyEventResult.handled;
            }
          }

          // Arrow Left: Collapse folder
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (folder.isExpanded) {
              setState(() {
                folder.isExpanded = false;
              });
              _ensureFocusNodes();
              return KeyEventResult.handled;
            }
          }

          // Select/Enter/Space: Select folder
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            _selectFolder(folder.id, folder.name);
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: _folderFocusStates[index],
          builder: (context, isFocused, _) {
            return Container(
              decoration: BoxDecoration(
                color: isFocused
                    ? Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : isSelected
                    ? Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : null,
                border: isFocused
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: itemWidget,
            );
          },
        ),
      );
    }

    // Non-TV: Simple selection highlighting
    return Container(
      color: isSelected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: itemWidget,
    );
  }

  String _truncateFolderName(String name) {
    const maxLength = 30;
    if (name.length <= maxLength) return name;
    return '${name.substring(0, maxLength - 3)}...';
  }

  @override
  void dispose() {
    for (final node in _folderFocusNodes) {
      node.dispose();
    }
    for (final state in _folderFocusStates) {
      state.dispose();
    }
    _cancelButtonFocusNode.dispose();
    _confirmButtonFocusNode.dispose();
    _closeButtonFocusNode.dispose();
    super.dispose();
  }
}
