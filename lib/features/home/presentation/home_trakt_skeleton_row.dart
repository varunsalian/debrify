import 'package:flutter/material.dart';
import '../../../widgets/skeleton_poster.dart';

/// A reserved-but-not-yet-loaded Trakt row: a header above a strip of static
/// poster placeholders supplied by the Home row builder that
/// hold the Trakt slot open while its fetch runs. Static — nothing animates
/// while the CPU is busy loading (see [ShimmerBox]).
class HomeTraktSkeletonRow extends StatelessWidget {
  final Widget header;
  final double posterW;
  final double cellH;
  final double rowH;

  const HomeTraktSkeletonRow({
    super.key,
    required this.header,
    required this.posterW,
    required this.cellH,
    required this.rowH,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: 6,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: _SkeletonPoster(width: posterW, height: cellH),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A poster-shaped static placeholder matching the board's poster radius. Thin
/// wrapper that sizes a [ShimmerBox].
class _SkeletonPoster extends StatelessWidget {
  final double width;
  final double height;

  const _SkeletonPoster({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height, child: const ShimmerBox());
  }
}
