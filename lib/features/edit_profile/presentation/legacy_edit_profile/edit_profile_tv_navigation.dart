import 'package:debrify/features/edit_profile/models/edit_profile_tv_section.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditProfileTvNavigation {
  final EditProfileDependencies _deps;
  EditProfileTvNavigation(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  void restoreTvSaveFocus() {
    if (!PlatformUtil.isTelevision) return;
    // Saving temporarily disables every form focus node. Re-enable them in
    // layout before restoring the remote's position after an error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_deps.mounted() &&
          !_owners.form.saving &&
          ModalRoute.of(_deps.context())?.isCurrent == true) {
        _owners.tv.tvTabFocusNodes.last.requestFocus();
      }
    });
  }

  TraversalDirection? tvDirection(KeyEvent event) {
    if (event is KeyUpEvent) return null;
    return switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
  }

  KeyEventResult handleTvRailKey(int index, KeyEvent event) {
    final direction = _sections.tvNav.tvDirection(event);
    if (direction == null) return KeyEventResult.ignored;
    switch (direction) {
      case TraversalDirection.left:
        _owners.tv.tvFocusRequest++;
        break;
      case TraversalDirection.right:
        if (index < EditProfileTvSection.values.length) {
          _sections.tvNav.selectTvSection(EditProfileTvSection.values[index]);
        }
        _sections.tvNav.focusTvContent();
      case TraversalDirection.up:
      case TraversalDirection.down:
        _owners.tv.tvFocusRequest++;
        final delta = direction == TraversalDirection.up ? -1 : 1;
        final target = (index + delta).clamp(
          0,
          _owners.tv.tvTabFocusNodes.length - 1,
        );
        if (index == 0 && delta < 0 && Navigator.of(_deps.context()).canPop()) {
          _owners.tv.tvBackFocus.requestFocus();
        } else {
          // Select synchronously: a quick RIGHT must never enter the old pane.
          if (target < EditProfileTvSection.values.length) {
            _sections.tvNav.selectTvSection(
              EditProfileTvSection.values[target],
            );
          }
          _owners.tv.tvTabFocusNodes[target].requestFocus();
        }
    }
    return KeyEventResult.handled;
  }

  void selectTvSection(EditProfileTvSection section) {
    if (_owners.tv.tvSection == section) return;
    _owners.tv.tvLastContentFocus = null;
    _owners.tv.tvFocusRequest++;
    _deps.setState(() => _owners.tv.tvSection = section);
  }

  List<FocusNode> get _tvContentStops => _owners
      .tv
      .tvContentFocus
      .traversalDescendants
      .where((node) => node is! FocusScopeNode && !node.rect.size.isEmpty)
      .toList();
  void _requestTvContentFocus(FocusNode node) {
    _owners.tv.tvLastContentFocus = node;
    FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
      node,
      alignment: .35,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void focusTvContent() {
    if (_owners.form.saving) return;
    final section = _owners.tv.tvSection;
    final request = ++_owners.tv.tvFocusRequest;
    // Section changes rebuild the pane. Resolve its live controls after layout,
    // including conditional controls and async Access rows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() ||
          _owners.form.saving ||
          _owners.tv.tvSection != section ||
          request != _owners.tv.tvFocusRequest ||
          ModalRoute.of(_deps.context())?.isCurrent == false) {
        return;
      }
      final stops = _sections.tvNav._tvContentStops;
      if (stops.isEmpty) return; // Empty/loading panes leave focus on the rail.
      if (stops.contains(_owners.tv.tvLastContentFocus)) {
        _sections.tvNav._requestTvContentFocus(_owners.tv.tvLastContentFocus!);
        return;
      }
      stops.sort((a, b) {
        final vertical = a.rect.top.compareTo(b.rect.top);
        return vertical == 0 ? a.rect.left.compareTo(b.rect.left) : vertical;
      });
      _sections.tvNav._requestTvContentFocus(stops.first);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void returnToTvRail() {
    _owners.tv.tvFocusRequest++;
    final focused = FocusManager.instance.primaryFocus;
    if (_sections.tvNav._tvContentStops.contains(focused))
      _owners.tv.tvLastContentFocus = focused;
    _owners.tv.tvTabFocusNodes[_owners.tv.tvSection.index].requestFocus();
  }

  void moveTvContent(TraversalDirection direction) {
    final current = FocusManager.instance.primaryFocus;
    if (current == null || !_owners.tv.tvContentFocus.hasFocus) return;
    final rect = current.rect;
    final horizontal =
        direction == TraversalDirection.left ||
        direction == TraversalDirection.right;
    final forward =
        direction == TraversalDirection.right ||
        direction == TraversalDirection.down;
    final candidates = _sections.tvNav._tvContentStops.where((node) {
      if (node == current) return false;
      final other = node.rect;
      // Horizontal movement belongs to the current visual row. Default
      // traversal can otherwise jump diagonally into a distant form field.
      final sameRow =
          (other.center.dy - rect.center.dy).abs() <
          (other.height < rect.height ? other.height : rect.height) / 2;
      if (horizontal != sameRow) return false;
      final delta = horizontal
          ? other.center.dx - rect.center.dx
          : other.center.dy - rect.center.dy;
      return forward ? delta > 1 : delta < -1;
    }).toList();
    candidates.sort((a, b) {
      final aDelta = a.rect.center - rect.center;
      final bDelta = b.rect.center - rect.center;
      final main = horizontal
          ? aDelta.dx.abs().compareTo(bDelta.dx.abs())
          : aDelta.dy.abs().compareTo(bDelta.dy.abs());
      return main != 0 ? main : aDelta.dx.abs().compareTo(bDelta.dx.abs());
    });
    if (candidates.isNotEmpty) {
      _sections.tvNav._requestTvContentFocus(candidates.first);
    } else if (direction == TraversalDirection.left) {
      _sections.tvNav.returnToTvRail();
    }
    // Other outer edges stay put rather than wrapping to the rail or AppBar.
  }
}
