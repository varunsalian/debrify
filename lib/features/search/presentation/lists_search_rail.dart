import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/mdblist_list_choice.dart';
import '../../../utils/tv_keys.dart';
import '../../../widgets/see_all/mdblist_list_card.dart';

/// Lists search's single lazy result rail and DPAD card behavior. Nodes and
/// result storage are borrowed; card actions capture the rendered list.
Widget buildListsSearchRail({
  required double posterW,
  required Widget header,
  required List<MdblistListChoice> Function() results,
  required List<FocusNode> nodes,
  required bool isTelevision,
  required ValueChanged<MdblistListChoice> onOpen,
  required VoidCallback onSidebar,
  required VoidCallback onUp,
}) {
  final posterH = posterW * 3 / 2;
  final rowH = posterH + 14;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      header,
      SizedBox(
        height: rowH,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          cacheExtent: 400,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          itemCount: results().length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: SizedBox(
              width: posterW,
              height: posterH,
              child: _buildListRailCard(
                results()[index],
                index,
                nodes: nodes,
                tv: isTelevision,
                onOpen: onOpen,
                onSidebar: onSidebar,
                onUp: onUp,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _buildListRailCard(
  MdblistListChoice list,
  int index, {
  required List<FocusNode> nodes,
  required bool tv,
  required ValueChanged<MdblistListChoice> onOpen,
  required VoidCallback onSidebar,
  required VoidCallback onUp,
}) {
  final node = index < nodes.length ? nodes[index] : null;
  return Focus(
    focusNode: node,
    onKeyEvent: (n, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (isActivateKey(key)) {
        onOpen(list);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (index > 0) {
          nodes[index - 1].requestFocus();
        } else if (tv) {
          onSidebar();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        if (index < nodes.length - 1) {
          nodes[index + 1].requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        onUp();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        // Lists is a dedicated single-rail search mode; there is no unrelated
        // catalog row below it to receive focus.
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Builder(
      builder: (context) {
        final focused = Focus.of(context).hasFocus;
        if (focused) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (node != null && node.hasFocus && context.mounted) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.5,
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                duration: const Duration(milliseconds: 150),
              );
            }
          });
        }
        return MdblistListCard(
          list: list,
          focused: focused,
          onTap: () => onOpen(list),
        );
      },
    ),
  );
}
