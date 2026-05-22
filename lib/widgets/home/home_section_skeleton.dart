import 'package:flutter/material.dart';
import '../shimmer.dart';
import 'home_theme.dart';

enum HomeSectionSkeletonStyle {
  poster,
  channel,
}

class HomeSectionSkeleton extends StatelessWidget {
  const HomeSectionSkeleton({
    super.key,
    this.style = HomeSectionSkeletonStyle.poster,
    this.isTelevision = false,
  });

  final HomeSectionSkeletonStyle style;
  final bool isTelevision;

  @override
  Widget build(BuildContext context) {
    final m = HomeTheme.metricsOf(context, isTelevision: isTelevision);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isChannel = style == HomeSectionSkeletonStyle.channel;
    final cardCount = isChannel ? 5 : 4;
    final cardWidth = isChannel ? 100.0 : 130.0;
    final cardHeight = isChannel
        ? 115.0
        : isMobile
            ? 200.0
            : 220.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            m.sectionHPadding,
            m.sectionVPadding + 18,
            m.sectionHPadding,
            m.sectionVPadding + 6,
          ),
          child: Shimmer(
            width: 140,
            height: m.headerFontSize + 4,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: m.sectionHPadding),
            itemCount: cardCount,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(right: index < cardCount - 1 ? 14 : 0),
                child: Shimmer(
                  width: cardWidth,
                  height: cardHeight,
                  borderRadius: BorderRadius.circular(14),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
