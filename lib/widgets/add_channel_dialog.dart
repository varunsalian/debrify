import 'package:flutter/material.dart';
import '../models/tv_channel.dart';

class AddChannelDialog extends StatefulWidget {
  const AddChannelDialog({super.key});

  @override
  State<AddChannelDialog> createState() => _AddChannelDialogState();
}

class _AddChannelDialogState extends State<AddChannelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _keywordController = TextEditingController();
  final List<String> _keywords = [];
  bool _showAdvancedOptions = false;
  bool _showChannelName = true;
  bool _showLiveTag = true;

  @override
  void dispose() {
    _nameController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _addKeyword() {
    final keyword = _keywordController.text.trim();
    if (keyword.isNotEmpty && !_keywords.contains(keyword)) {
      setState(() {
        _keywords.add(keyword);
        _keywordController.clear();
      });
    }
  }

  void _removeKeyword(String keyword) {
    setState(() {
      _keywords.remove(keyword);
    });
  }

  void _submit() {
    if (_formKey.currentState!.validate() && _keywords.isNotEmpty) {
      final channel = TVChannel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        keywords: List.from(_keywords),
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
        showChannelName: _showChannelName,
        showLiveTag: _showLiveTag,
      );
      Navigator.of(context).pop(channel);
    } else if (_keywords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one keyword')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.tv_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Add TV Channel',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Channel Name
              Text(
                'Channel Name',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Enter channel name',
                  prefixIcon: Icon(Icons.tv),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a channel name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              // Keywords
              Text(
                'Search Keywords',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _keywordController,
                      decoration: const InputDecoration(
                        hintText: 'Enter search keyword',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onFieldSubmitted: (_) => _addKeyword(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addKeyword,
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              
              // Keywords List
              if (_keywords.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Added Keywords (${_keywords.length})',
                                     style: Theme.of(context).textTheme.bodySmall?.copyWith(
                     color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                   ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _keywords.map((keyword) {
                        return Chip(
                          label: Text(keyword),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () => _removeKeyword(keyword),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Advanced Options
              InkWell(
                onTap: () {
                  setState(() {
                    _showAdvancedOptions = !_showAdvancedOptions;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.settings,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Advanced Options',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        _showAdvancedOptions ? Icons.expand_less : Icons.expand_more,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
              
              // Advanced Options Content
              if (_showAdvancedOptions) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Display Options',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Show Channel Name Toggle
                      SwitchListTile(
                        title: const Text('Show Channel Name'),
                        subtitle: const Text('Display channel name in video player'),
                        value: _showChannelName,
                        onChanged: (value) {
                          setState(() {
                            _showChannelName = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                      
                      // Show Live Tag Toggle
                      SwitchListTile(
                        title: const Text('Show LIVE Tag'),
                        subtitle: const Text('Display LIVE indicator in video player'),
                        value: _showLiveTag,
                        onChanged: (value) {
                          setState(() {
                            _showLiveTag = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: const Text('Add Channel'),
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