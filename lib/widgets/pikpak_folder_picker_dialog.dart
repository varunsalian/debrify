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

  // Track the last focused folder for creating subfolders
  _FolderNode? _lastFocusedFolder;

  // TV Navigation support
  bool _isTelevision = false;
  final List<FocusNode> _folderFocusNodes = [];
  final List<ValueNotifier<bool>> _folderFocusStates = [];
  late final FocusNode _cancelButtonFocusNode;
  late final FocusNode _confirmButtonFocusNode;
  late final FocusNode _closeButtonFocusNode;
  late final FocusNode _newFolderButtonFocusNode;

  @override
  void initState() {
    super.initState();
    _setupButtonFocusNodes();
    _detectTelevision();
    _loadRootFolders();
  }

  void _setupButtonFocusNodes() {
    _closeButtonFocusNode = FocusNode(debugLabel: 'close-button');

    _newFolderButtonFocusNode = FocusNode(
      debugLabel: 'new-folder-button',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // DPAD Right: Move to Cancel button
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _cancelButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        // DPAD Up: Move to last folder item
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          final flatFolders = _getFlattenedFolders();
          if (flatFolders.isNotEmpty && _folderFocusNodes.isNotEmpty) {
            _folderFocusNodes[flatFolders.length - 1].requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _cancelButtonFocusNode = FocusNode(
      debugLabel: 'cancel-button',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // DPAD Left: Move to New Folder button
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _newFolderButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        // DPAD Right: Move to Confirm button
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _confirmButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        // DPAD Up: Move to last folder item
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          final flatFolders = _getFlattenedFolders();
          if (flatFolders.isNotEmpty && _folderFocusNodes.isNotEmpty) {
            _folderFocusNodes[flatFolders.length - 1].requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _confirmButtonFocusNode = FocusNode(
      debugLabel: 'confirm-button',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // DPAD Left: Move to Cancel button
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _cancelButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        // DPAD Up: Move to last folder item
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          final flatFolders = _getFlattenedFolders();
          if (flatFolders.isNotEmpty && _folderFocusNodes.isNotEmpty) {
            _folderFocusNodes[flatFolders.length - 1].requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
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
        // When expanding a folder, set it as the context for creating new folders
        if (folder.isExpanded) {
          _lastFocusedFolder = folder;
        }
      });
      return;
    }

    // Load children - set this folder as context for new folder creation
    setState(() {
      folder.isLoading = true;
      _lastFocusedFolder = folder;
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
    // Find the folder node to update _lastFocusedFolder
    final flatFolders = _getFlattenedFolders();
    _FolderNode? selectedFolder;
    try {
      selectedFolder = flatFolders.firstWhere((f) => f.id == folderId);
    } catch (_) {
      // Folder not found in flattened list
      selectedFolder = null;
    }

    setState(() {
      _selectedFolderId = folderId;
      _selectedFolderName = folderName;
      // Update last focused folder when selecting
      if (selectedFolder != null) {
        _lastFocusedFolder = selectedFolder;
      }
    });
  }

  Future<void> _showNewFolderDialog() async {
    final parentName = _lastFocusedFolder?.name ?? 'Root';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _NewFolderDialog(
        parentFolderName: parentName,
        isTelevision: _isTelevision,
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _createNewFolder(result);
    }
  }

  Future<void> _createNewFolder(String folderName) async {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text('Creating folder "$folderName"...'),
              ],
            ),
            duration: const Duration(seconds: 30),
          ),
        );
      }

      // Create folder via API - use last focused folder as parent
      final parentFolderId = _lastFocusedFolder?.id;
      final result = await _apiService.createFolder(
        folderName: folderName,
        parentFolderId: parentFolderId,
      );

      final newFolderId = result['file']?['id'] ?? result['id'];
      final newFolderName = result['file']?['name'] ?? result['name'] ?? folderName;

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Folder "$newFolderName" created successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Add the new folder to the appropriate list
      final newNode = _FolderNode(
        id: newFolderId,
        name: newFolderName,
        level: _lastFocusedFolder == null ? 0 : _lastFocusedFolder!.level + 1,
      );

      setState(() {
        if (_lastFocusedFolder == null) {
          // Add to root
          _rootFolders.add(newNode);
          _rootFolders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        } else {
          // Add to last focused folder's children
          _lastFocusedFolder!.children = [..._lastFocusedFolder!.children, newNode];
          _lastFocusedFolder!.children.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          _lastFocusedFolder!.hasLoadedChildren = true;
          _lastFocusedFolder!.isExpanded = true;
        }
      });

      _ensureFocusNodes();

      // Focus the newly created folder
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isTelevision) {
          final flatFolders = _getFlattenedFolders();
          final newFolderIndex = flatFolders.indexWhere((f) => f.id == newFolderId);
          if (newFolderIndex >= 0 && newFolderIndex < _folderFocusNodes.length) {
            _folderFocusNodes[newFolderIndex].requestFocus();
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create folder: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
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
    if (!_isTelevision) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // If there are folders, focus the first one
      if (_folderFocusNodes.isNotEmpty) {
        _folderFocusNodes[0].requestFocus();
        return;
      }

      // If no folders, focus New Folder button (now at bottom left)
      _newFolderButtonFocusNode.requestFocus();
    });
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

    return FocusScope(
      node: FocusScopeNode(debugLabel: 'pikpak-folder-picker-scope'),
      autofocus: true,
      child: Focus(
        autofocus: _isTelevision,
        skipTraversal: true, // Prevent this from being a focus target
        descendantsAreFocusable: true,
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
              SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
              SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(TraversalDirection.left),
              SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(TraversalDirection.right),
              SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
            },
            child: Dialog(
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
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(0),
                          child: IconButton(
                            focusNode: _closeButtonFocusNode,
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Current location indicator
                    Text(
                      _lastFocusedFolder == null
                          ? 'Creating in: Root'
                          : 'Creating in: ${_lastFocusedFolder!.name}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),

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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // New Folder button on the left
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1000),
                          child: FilledButton.tonalIcon(
                            focusNode: _newFolderButtonFocusNode,
                            onPressed: _showNewFolderDialog,
                            icon: const Icon(Icons.create_new_folder, size: 18),
                            label: const Text('New Folder'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),

                        // Cancel and Confirm buttons on the right
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(1001),
                              child: TextButton(
                                focusNode: _cancelButtonFocusNode,
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: FocusTraversalOrder(
                                order: const NumericFocusOrder(1002),
                                child: FilledButton.icon(
                                  focusNode: _confirmButtonFocusNode,
                                  onPressed: _selectedFolderId != null
                                      ? () {
                                          Navigator.pop(context, {
                                            'folderId': _selectedFolderId,
                                            'folderName': _selectedFolderName,
                                          });
                                        }
                                      : null,
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('Select'),
                                ),
                              ),
                            ),
                          ],
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderItem(BuildContext context, int index) {
    final folder = _getFlattenedFolders()[index];
    final isSelected = _selectedFolderId == folder.id;
    final canExpand = !folder.hasLoadedChildren || folder.children.isNotEmpty;

    // Use GestureDetector instead of InkWell to avoid focus conflicts on TV
    final itemWidget = GestureDetector(
      onTap: () => _selectFolder(folder.id, folder.name),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.only(
          left: 8.0 + (folder.level * 24.0),
          right: 8.0,
          top: 8.0,
          bottom: 8.0,
        ),
        child: Row(
          children: [
            // Expand/collapse icon - use GestureDetector instead of IconButton for TV
            SizedBox(
              width: 24,
              height: 24,
              child: canExpand
                  ? GestureDetector(
                      onTap: folder.isLoading
                          ? null
                          : () => _loadFolderChildren(folder),
                      child: folder.isLoading
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
                    )
                  : null,
            ),
            const SizedBox(width: 8),

            // Radio indicator (visual only, not focusable)
            ExcludeFocus(
              child: Radio<String>(
                value: folder.id,
                groupValue: _selectedFolderId,
                onChanged: (_) {}, // Non-null to keep enabled styling
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
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
      return FocusTraversalOrder(
        order: NumericFocusOrder(2.0 + index),
        child: Focus(
          focusNode: _folderFocusNodes[index],
          onFocusChange: (hasFocus) {
            if (hasFocus) {
              // Update the last focused folder when user navigates
              setState(() {
                _lastFocusedFolder = folder;
              });
            }
          },
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

          // Arrow Down: Move to New Folder button if this is the last folder item
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final flatFolders = _getFlattenedFolders();
            if (index == flatFolders.length - 1) {
              // This is the last folder item, move to New Folder button
              _newFolderButtonFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
          }

          // Select/Enter: Select folder for restriction
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
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
    _newFolderButtonFocusNode.dispose();
    super.dispose();
  }
}

// DPAD-compatible input dialog for creating new folders
class _NewFolderDialog extends StatefulWidget {
  final String parentFolderName;
  final bool isTelevision;

  const _NewFolderDialog({
    required this.parentFolderName,
    required this.isTelevision,
  });

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _inputFocusNode;
  late final FocusNode _cancelButtonFocusNode;
  late final FocusNode _createButtonFocusNode;

  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _setupFocusNodes();

    // Auto-focus input field for TV
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputFocusNode.requestFocus();
        }
      });
    }
  }

  void _setupFocusNodes() {
    _inputFocusNode = FocusNode(
      debugLabel: 'folder-name-input',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // DPAD Down: Move to Create button
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _createButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        // Enter/Select: Submit the form
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
          _validateAndSubmit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    _cancelButtonFocusNode = FocusNode(
      debugLabel: 'cancel-btn',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // DPAD Up: Back to input
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _inputFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        // DPAD Right: Move to Create button
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _createButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    _createButtonFocusNode = FocusNode(
      debugLabel: 'create-btn',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // DPAD Up: Back to input
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _inputFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        // DPAD Left: Move to Cancel button
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _cancelButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    _createButtonFocusNode.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final folderName = _controller.text.trim();

    if (folderName.isEmpty) {
      setState(() {
        _errorMessage = 'Folder name cannot be empty';
      });
      return;
    }

    // Check for invalid characters
    final invalidChars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
    for (final char in invalidChars) {
      if (folderName.contains(char)) {
        setState(() {
          _errorMessage = 'Folder name contains invalid character: $char';
        });
        return;
      }
    }

    Navigator.pop(context, folderName);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;

    return FocusScope(
      autofocus: true,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
          SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
          SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(TraversalDirection.left),
          SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(TraversalDirection.right),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        },
        child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (screenWidth * 0.9).clamp(300.0, 500.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.create_new_folder, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Create New Folder',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Parent folder info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Creating in: ${widget.parentFolderName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Input field
              TextField(
                controller: _controller,
                focusNode: _inputFocusNode,
                autofocus: !widget.isTelevision,
                decoration: InputDecoration(
                  labelText: 'Folder Name',
                  hintText: 'Enter folder name',
                  errorText: _errorMessage.isEmpty ? null : _errorMessage,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  prefixIcon: const Icon(Icons.drive_file_rename_outline),
                ),
                onChanged: (value) {
                  // Clear error when user types
                  if (_errorMessage.isNotEmpty) {
                    setState(() {
                      _errorMessage = '';
                    });
                  }
                },
                onSubmitted: (_) => _validateAndSubmit(),
              ),
              const SizedBox(height: 20),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    focusNode: _cancelButtonFocusNode,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    focusNode: _createButtonFocusNode,
                    onPressed: _validateAndSubmit,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}
