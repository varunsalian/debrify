import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

typedef IptvCenteredItemBuilder =
    Widget Function(
      BuildContext context,
      int index,
      bool selected,
      VoidCallback centerItem,
    );

/// Touch-first, fixed-cursor channel selector for large tablet layouts.
///
/// The arrow never moves. Rows scroll and snap beneath it; [onSelected] fires
/// only once the list settles, so a fast fling never opens every stream it
/// crosses.
class IptvCenteredSelector extends StatefulWidget {
  final int itemCount;
  final double itemExtent;
  final IptvCenteredItemBuilder itemBuilder;
  final ValueChanged<int> onSelected;
  final int initialIndex;

  /// Identity of the externally selected item.
  ///
  /// A changed token can select a different item at the same index without
  /// keying this whole widget to the backing List and losing its scroll state.
  final Object? selectionToken;

  const IptvCenteredSelector({
    super.key,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
    required this.onSelected,
    this.initialIndex = 0,
    this.selectionToken,
  });

  @override
  State<IptvCenteredSelector> createState() => _IptvCenteredSelectorState();
}

class _IptvCenteredSelectorState extends State<IptvCenteredSelector> {
  final ScrollController _controller = ScrollController();
  int _selectedIndex = 0;
  int _settleTicket = 0;
  bool _snapping = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _safeIndex(widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _presentInitialItem());
  }

  @override
  void didUpdateWidget(IptvCenteredSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final externalSelectionChanged =
        widget.initialIndex != oldWidget.initialIndex ||
        widget.selectionToken != oldWidget.selectionToken;
    final nextIndex = _safeIndex(
      externalSelectionChanged ? widget.initialIndex : _selectedIndex,
    );
    final indexChanged = nextIndex != _selectedIndex;
    final needsRealignment =
        widget.itemExtent != oldWidget.itemExtent || indexChanged;
    _selectedIndex = nextIndex;
    if (!needsRealignment && !externalSelectionChanged) return;
    final ticket = ++_settleTicket;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ticket != _settleTicket ||
          !_controller.hasClients ||
          widget.itemCount == 0) {
        return;
      }
      if (needsRealignment) {
        _controller.jumpTo(_targetOffset(nextIndex));
      }
      if (externalSelectionChanged || indexChanged) {
        widget.onSelected(nextIndex);
      }
    });
  }

  int _safeIndex(int index) {
    if (widget.itemCount == 0) return 0;
    return index.clamp(0, widget.itemCount - 1);
  }

  double _targetOffset(int index) => index * widget.itemExtent;

  int _indexAtOffset(double offset) =>
      _safeIndex((offset / widget.itemExtent).round());

  void _presentInitialItem() {
    if (!mounted || !_controller.hasClients || widget.itemCount == 0) return;
    _controller.jumpTo(_targetOffset(_selectedIndex));
    widget.onSelected(_selectedIndex);
  }

  void _invalidateSettle() {
    _settleTicket++;
  }

  Future<void> _center(int index) async {
    if (!_controller.hasClients || widget.itemCount == 0) return;
    final safeIndex = _safeIndex(index);
    final ticket = ++_settleTicket;
    _snapping = true;
    try {
      await _controller.animateTo(
        _targetOffset(safeIndex),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _snapping = false;
    }
    if (!mounted || ticket != _settleTicket) return;
    _commitSelection(safeIndex);
  }

  Future<void> _settleAfterScroll() async {
    if (_snapping || !_controller.hasClients || widget.itemCount == 0) return;
    final index = _indexAtOffset(_controller.offset);
    final target = _targetOffset(index);
    final ticket = ++_settleTicket;
    if ((_controller.offset - target).abs() > 0.5) {
      _snapping = true;
      try {
        await _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } finally {
        _snapping = false;
      }
    }
    if (!mounted || ticket != _settleTicket) return;
    _commitSelection(index);
  }

  void _commitSelection(int index) {
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
    widget.onSelected(index);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _invalidateSettle();
    } else if (notification is ScrollEndNotification && !_snapping) {
      unawaited(_settleAfterScroll());
    }
    return false;
  }

  @override
  void dispose() {
    _settleTicket++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerPadding = math.max(
          0.0,
          (constraints.maxHeight - widget.itemExtent) / 2,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: ListView.builder(
                key: const ValueKey('iptv-tablet-centered-list'),
                controller: _controller,
                itemCount: widget.itemCount,
                itemExtent: widget.itemExtent,
                padding: EdgeInsets.fromLTRB(
                  24,
                  centerPadding,
                  24,
                  centerPadding,
                ),
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                itemBuilder: (context, index) => widget.itemBuilder(
                  context,
                  index,
                  index == _selectedIndex,
                  () => unawaited(_center(index)),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('iptv-tablet-selector-arrow'),
                  width: 28,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.14),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(14),
                    ),
                    border: Border.all(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.38),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.18),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_right_rounded,
                    color: Color(0xFF00E5FF),
                    size: 27,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
