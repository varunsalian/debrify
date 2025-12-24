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
  final FocusNode _cancelButtonFocusNode = FocusNode(
    debugLabel: 'cancel-button',
  );
  final FocusNode _confirmButtonFocusNode = FocusNode(
    debugLabel: 'confirm-button',
  );
  final FocusNode _closeButtonFocusNode = FocusNode(debugLabel: 'close-button');
  final FocusNode _newFolderButtonFocusNode = FocusNode(
    debugLabel: 'new-folder-button',
  );

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

      // If no folders but no error, focus New Folder button
      if (_errorMessage == null && _rootFolders.isEmpty) {
        _newFolderButtonFocusNode.requestFocus();
        return;
      }

      // Otherwise focus New Folder button as fallback
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
        descendantsAreFocusable: true,
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
              SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
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
                          child: Focus(
                            focusNode: _closeButtonFocusNode,
                            child: IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Current location and New Folder button
                    Row(
                      children: [
                        Expanded(
                          child: Text(
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
                        ),
                        const SizedBox(width: 8),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: Focus(
                            focusNode: _newFolderButtonFocusNode,
                            child: FilledButton.tonalIcon(
                              onPressed: _showNewFolderDialog,
                              icon: const Icon(Icons.create_new_folder, size: 16),
                              label: const Text('New Folder'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ),
                      ],
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
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1000),
                          child: Focus(
                            focusNode: _cancelButtonFocusNode,
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(1001),
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
  final FocusNode _inputFocusNode = FocusNode(debugLabel: 'folder-name-input');
  final FocusNode _cancelButtonFocusNode = FocusNode(debugLabel: 'cancel-btn');
  final FocusNode _createButtonFocusNode = FocusNode(debugLabel: 'create-btn');

  String _errorMessage = '';

  @override
  void initState() {
    super.initState();

    // Auto-focus input field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inputFocusNode.requestFocus();
      }
    });
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

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
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
              Focus(
                focusNode: _inputFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;

                  // DPAD Down: Move to Create button
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _createButtonFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  // Enter when input is focused: Submit
                  if (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.select) {
                    _validateAndSubmit();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
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
              ),
              const SizedBox(height: 20),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Focus(
                    focusNode: _cancelButtonFocusNode,
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
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Focus(
                    focusNode: _createButtonFocusNode,
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
                    child: FilledButton.icon(
                      onPressed: _validateAndSubmit,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
