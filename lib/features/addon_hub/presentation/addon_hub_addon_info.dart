import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/addon_hub/application/addon_hub_labels.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:flutter/material.dart';

/// Shared name/version/types/description column, matching the Stremio addons
/// screen: title with a small muted version beside it, muted type line,
/// capability chips (what the addon actually provides), then a two-line
/// description.
class AddonHubAddonInfo extends StatelessWidget {
  final String name;
  final String? version;
  final List<String> types;
  final List<String> resources;
  final String? description;

  /// Show a "Needs debrid" hint — this addon provides streams but no debrid
  /// provider is configured, so its torrents can't play (debrify has no P2P).
  final bool warnDebrid;

  const AddonHubAddonInfo({
    required this.name,
    required this.version,
    required this.types,
    required this.resources,
    required this.description,
    this.warnDebrid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AddonHubAddonTitleLine(name: name, version: version),
        const SizedBox(height: 4),
        AddonHubAddonMeta(
          types: types,
          resources: resources,
          description: description,
          warnDebrid: warnDebrid,
        ),
      ],
    );
  }
}

/// The name + muted version, on one baseline-aligned line. Extracted so the
/// narrow card layout can hoist it into a header row (beside the logo / status)
/// while the rest of the info flows full-width below.
class AddonHubAddonTitleLine extends StatelessWidget {
  final String name;
  final String? version;

  /// When true, the version sits on its own line *under* the name instead of
  /// beside it — the narrow header row can't afford to give the version a
  /// fixed slice of the name's width.
  final bool stacked;

  const AddonHubAddonTitleLine({
    required this.name,
    required this.version,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
    final versionText = (version != null && version!.isNotEmpty)
        ? Text(
            'v.$version',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          )
        : null;

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          nameText,
          if (versionText != null) ...[const SizedBox(height: 2), versionText],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: nameText),
        if (versionText != null) ...[const SizedBox(width: 10), versionText],
      ],
    );
  }
}

/// The type line, capability chips and description — everything below the
/// title. Kept separate so the narrow layout can give it the full card width
/// (chips no longer wrap into a tall stack in a squeezed column).
class AddonHubAddonMeta extends StatelessWidget {
  final List<String> types;
  final List<String> resources;
  final String? description;
  final bool warnDebrid;
  const AddonHubAddonMeta({
    required this.types,
    required this.resources,
    required this.description,
    this.warnDebrid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          types.isEmpty ? 'Addon' : types.map(addonHubCapitalize).join(' & '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (addonHubCapabilities(resources).isNotEmpty || warnDebrid) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final cap in addonHubCapabilities(resources))
                AddonHubCapabilityChip(label: cap.$1, highlight: cap.$2),
              if (warnDebrid) const AddonHubWarningChip(label: 'Needs debrid'),
            ],
          ),
        ],
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/// Addon logo, Stremio-style: the image (or a plain muted puzzle piece) sits
/// directly on the card — no tinted chip behind it.
Widget addonHubLogo(String? url, {double size = 64}) => SizedBox(
  width: size,
  height: size,
  child: (url != null && url.isNotEmpty)
      ? ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            memCacheWidth: 192,
            errorWidget: (_, __, ___) => Icon(
              Icons.extension_rounded,
              color: Colors.white38,
              size: size * 0.72,
            ),
          ),
        )
      : Icon(Icons.extension_rounded, color: Colors.white38, size: size * 0.72),
);

class AddonHubStatusPill extends StatelessWidget {
  final bool enabled;
  final bool reconnect;
  const AddonHubStatusPill({required this.enabled, this.reconnect = false});

  @override
  Widget build(BuildContext context) {
    final color = reconnect
        ? Colors.amber
        : enabled
        ? kSeeAllAccent2
        : Colors.white.withValues(alpha: 0.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        reconnect ? 'RECONNECT' : (enabled ? 'ON' : 'OFF'),
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// A small pill stating one thing an addon provides (Streams / Catalog / …).
class AddonHubCapabilityChip extends StatelessWidget {
  final String label;
  final bool highlight;
  const AddonHubCapabilityChip({required this.label, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? kSeeAllAccent.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: highlight
              ? kSeeAllAccentBorder
              : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: highlight
              ? kSeeAllAccent2
              : Colors.white.withValues(alpha: 0.7),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// An amber caveat chip (e.g. "Needs debrid") — a heads-up, not a capability.
class AddonHubWarningChip extends StatelessWidget {
  final String label;
  const AddonHubWarningChip({required this.label});

  static const Color _amber = Color(0xFFF6B94A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline_rounded, size: 11, color: _amber),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: _amber,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
