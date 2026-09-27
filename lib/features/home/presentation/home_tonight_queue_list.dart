import 'dart:math' show min;
import 'package:flutter/widgets.dart';
import 'home_tonight_layout.dart' show homeTonightRowGap;

/// The most of a queue row's width the still may take. The rest is the title
/// and episode, which is what the row exists to tell you.
const double _kTonightThumbShare = 0.40;

/// Tonight's fixed-extent lazy queue. The caller owns each row's data, borrowed
/// focus node and actions. Thumbnail width is supplied at the original build point.
Widget buildHomeTonightQueueList({
  required int itemCount,
  required double rowHeight,
  required double queueWidth,
  required Widget Function(
    BuildContext context,
    int index,
    double thumbnailWidth,
  )
  itemBuilder,
}) {
  // The thumb is capped by the row's WIDTH, not just its height. Sized
  // purely as `rowHeight * 16/9` it ate two thirds of a narrow queue and left
  // the title about ten characters — "Orange Is t…". Whatever is left of
  // 16:9 after this cap, BoxFit.cover crops.
  final thumbW = min(rowHeight * 16 / 9, queueWidth * _kTonightThumbShare);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Expanded(
        child: ListView.builder(
          key: const ValueKey('tonight-queue'),
          padding: EdgeInsets.zero,
          clipBehavior: Clip.hardEdge,
          itemCount: itemCount,
          itemExtent: rowHeight + homeTonightRowGap,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: homeTonightRowGap),
            child: itemBuilder(context, index, thumbW),
          ),
        ),
      ),
    ],
  );
}
