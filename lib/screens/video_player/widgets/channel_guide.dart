import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/channel_entry.dart';

/// Callback when a channel is selected from the guide
typedef OnChannelSelected = void Function(ChannelEntry channel);

/// A channel guide overlay for browsing and selecting channels.
class ChannelGuide extends StatefulWidget {
  final List<ChannelEntry> channels;
  final String? currentChannelId;
  final int? currentChannelNumber;
  final OnChannelSelected onChannelSelected;
  final VoidCallback onClose;

  const ChannelGuide({
    Key? key,
    required this.channels,
    this.currentChannelId,
    this.currentChannelNumber,
    required this.onChannelSelected,
    required this.onClose,
  }) : super(key: key);

  @override
  State<ChannelGuide> createState() => _ChannelGuideState();
}

class _ChannelGuideState extends State<ChannelGuide>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<ChannelEntry> _filteredChannels = [];
  int _focusedIndex = 0;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _filteredChannels = List.from(widget.channels);

    // Find current channel index
    if (widget.currentChannelId != null) {
      final idx = _filteredChannels
          .indexWhere((c) => c.id == widget.currentChannelId);
      if (idx >= 0) _focusedIndex = idx;
    }

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();

    // Auto-focus after animation completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToFocused();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _filterChannels(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredChannels = List.from(widget.channels);
      } else {
        _filteredChannels =
            widget.channels.where((c) => c.matches(query)).toList();
      }
      _focusedIndex = 0;
    });
  }

  void _scrollToFocused() {
    if (_filteredChannels.isEmpty || !_scrollController.hasClients) return;

    const itemHeight = 72.0;
    final targetOffset = _focusedIndex * itemHeight;
    final viewportHeight = _scrollController.position.viewportDimension;
    final currentOffset = _scrollController.offset;

    // Check if item is visible
    if (targetOffset < currentOffset ||
        targetOffset > currentOffset + viewportHeight - itemHeight) {
      _scrollController.animateTo(
        (targetOffset - viewportHeight / 2 + itemHeight / 2)
            .clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    // Handle back/escape
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      widget.onClose();
      return;
    }

    // If search is focused, let it handle text input
    if (_searchFocusNode.hasFocus) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        // Move focus away from search to enable list navigation
        _searchFocusNode.unfocus();
        setState(() {}); // Trigger rebuild to show focus highlight
      }
      return;
    }

    // List navigation
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() => _focusedIndex--);
        _scrollToFocused();
      } else {
        // At top, move to search
        _searchFocusNode.requestFocus();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _filteredChannels.length - 1) {
        setState(() => _focusedIndex++);
        _scrollToFocused();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      if (_filteredChannels.isNotEmpty) {
        widget.onChannelSelected(_filteredChannels[_focusedIndex]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: child,
          );
        },
        child: GestureDetector(
          onTap: widget.onClose,
          child: Container(
            color: Colors.black.withOpacity(0.7),
            child: Center(
              child: GestureDetector(
                onTap: () {}, // Consume taps on panel
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: _buildPanel(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      width: 420,
      height: MediaQuery.of(context).size.height * 0.75,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xF0141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(child: _buildChannelList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final currentNum = widget.currentChannelNumber;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Current channel indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF66FF00), Color(0xFF00BCD4)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              currentNum != null ? currentNum.toString().padLeft(2, '0') : '--',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Title
          const Expanded(
            child: Text(
              'CHANNEL GUIDE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
          // Channel count
          Text(
            '${widget.channels.length} channels',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search channels...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.white.withOpacity(0.5),
            size: 20,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF66FF00), width: 1),
          ),
        ),
        onChanged: _filterChannels,
        textInputAction: TextInputAction.search,
      ),
    );
  }

  Widget _buildChannelList() {
    if (_filteredChannels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              color: Colors.white.withOpacity(0.3),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No channels found',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _filteredChannels.length,
      itemExtent: 72,
      itemBuilder: (context, index) {
        final channel = _filteredChannels[index];
        // Show focus highlight when search is not focused
        final isFocused = index == _focusedIndex && !_searchFocusNode.hasFocus;
        final isCurrent = channel.id == widget.currentChannelId;

        return _ChannelListItem(
          channel: channel,
          isFocused: isFocused,
          isCurrent: isCurrent,
          onTap: () => widget.onChannelSelected(channel),
        );
      },
    );
  }
}

class _ChannelListItem extends StatelessWidget {
  final ChannelEntry channel;
  final bool isFocused;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ChannelListItem({
    required this.channel,
    required this.isFocused,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isFocused
              ? Colors.white.withOpacity(0.15)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFocused
                ? const Color(0xFF66FF00).withOpacity(0.6)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        transform: isFocused
            ? (Matrix4.identity()..scale(1.02))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: Row(
          children: [
            // Channel number
            Container(
              width: 44,
              alignment: Alignment.center,
              child: Text(
                channel.displayNumber,
                style: TextStyle(
                  color: isCurrent
                      ? const Color(0xFF66FF00)
                      : Colors.white.withOpacity(0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Channel name and status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    channel.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent
                          ? const Color(0xFF66FF00)
                          : Colors.white.withOpacity(0.95),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isCurrent ? 'Currently playing' : 'Press OK to tune',
                    style: TextStyle(
                      color: isCurrent
                          ? const Color(0xFF66FF00).withOpacity(0.7)
                          : Colors.white.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // NOW badge for current channel
            if (isCurrent)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF66FF00), Color(0xFF00BCD4)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'NOW',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
