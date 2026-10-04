import 'package:debrify/features/addon_hub/presentation/addon_hub_addon_info.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_focus_card.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';

class AddonHubInstalledRow extends StatelessWidget {
  final StremioAddon addon;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool warnDebrid;
  const AddonHubInstalledRow({
    required this.addon,
    required this.onTap,
    this.focusNode,
    this.warnDebrid = false,
  });

  @override
  Widget build(BuildContext context) {
    final chevron = Icon(
      Icons.chevron_right_rounded,
      size: 26,
      color: Colors.white.withValues(alpha: 0.3),
    );
    return AddonHubFocusCard(
      onTap: onTap,
      focusNode: focusNode,
      builder: (focused) => LayoutBuilder(
        builder: (context, c) {
          // On a phone-width card the logo + status pill + chevron leave the
          // info column too narrow (name/type truncate, chips wrap into a tall
          // stack). Below the breakpoint, keep only the logo + title + status
          // in a header row and let the type/chips/description use the full
          // width beneath. Wide (tablet/desktop/TV) keeps the single-row look.
          final narrow = c.maxWidth < 480;
          final meta = AddonHubAddonMeta(
            types: addon.types,
            resources: addon.resources,
            description: addon.description,
            warnDebrid: warnDebrid,
          );
          return Container(
            decoration: addonHubCardDecoration(focused),
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 16 : 22,
              vertical: narrow ? 16 : 20,
            ),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Compact logo + version-under-name: the header row
                          // also carries the pill and chevron, so every fixed
                          // pixel here comes straight out of the name's width.
                          addonHubLogo(null, size: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: AddonHubAddonTitleLine(
                              name: addon.displayName,
                              version: addon.version,
                              stacked: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          AddonHubStatusPill(
                            enabled: addon.enabled,
                            reconnect: addon.connectionResourceSecretPending,
                          ),
                          const SizedBox(width: 4),
                          chevron,
                        ],
                      ),
                      const SizedBox(height: 14),
                      meta,
                    ],
                  )
                : Row(
                    children: [
                      addonHubLogo(null),
                      const SizedBox(width: 20),
                      Expanded(
                        child: AddonHubAddonInfo(
                          name: addon.displayName,
                          version: addon.version,
                          types: addon.types,
                          resources: addon.resources,
                          description: addon.description,
                          warnDebrid: warnDebrid,
                        ),
                      ),
                      const SizedBox(width: 16),
                      AddonHubStatusPill(
                        enabled: addon.enabled,
                        reconnect: addon.connectionResourceSecretPending,
                      ),
                      const SizedBox(width: 8),
                      chevron,
                    ],
                  ),
          );
        },
      ),
    );
  }
}
