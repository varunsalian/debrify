import 'package:debrify/features/merged_detail/presentation/merged_detail_action_descriptions.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';

/// The "More" quick-actions menu — a labelled sheet with an icon, name and a
/// one-line description for every action, so users know what each one does.
class _QuickActionsMenu extends StatelessWidget {
  final String title;
  final List<TraktMenuOption> options;
  final bool isTelevision;
  final void Function(TraktItemMenuAction action) onSelected;

  const _QuickActionsMenu({
    required this.title,
    required this.options,
    required this.isTelevision,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Standard sheet chrome (background + drag handle) is provided by
    // showModalBottomSheet — this widget is just the header + clean list, so it
    // reads the same as the per-episode ⋮ menu.
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'More',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: options.length,
                itemBuilder: (context, i) => _item(options[i], i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(TraktMenuOption o, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: isTelevision && index == 0,
        // The default focus overlay is invisible on the dark sheet — make the
        // DPAD cursor obvious.
        focusColor: Colors.white.withValues(alpha: 0.12),
        onTap: () => onSelected(o.action),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 18, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(o.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      o.label,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      MergedDetailActionDescriptions.descriptionFor(o.action),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef MergedQuickActionsMenu = _QuickActionsMenu;

const mergedQuickActionsMenuConstructor = _QuickActionsMenu.new;
