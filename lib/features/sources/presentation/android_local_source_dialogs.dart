import 'package:flutter/material.dart';

import '../../../models/local_source_document.dart';

Future<LocalSourceDocument?> showAndroidLocalMovieChoice(
  BuildContext context,
  List<LocalSourceDocument> videos,
) => showDialog<LocalSourceDocument>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Choose movie file'),
    content: SizedBox(
      width: 560,
      height: MediaQuery.sizeOf(dialogContext).height * 0.5,
      child: ListView.builder(
        itemCount: videos.length,
        itemBuilder: (_, index) => ListTile(
          autofocus: index == 0,
          title: Text(videos[index].name),
          subtitle: Text(videos[index].relativePath),
          onTap: () => Navigator.of(dialogContext).pop(videos[index]),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('Cancel'),
      ),
    ],
  ),
);

Future<bool?> showAndroidLocalSeriesConfirmation(
  BuildContext context, {
  required String title,
  required String folderName,
  required int episodeCount,
}) => showDialog<bool>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    scrollable: true,
    title: Text('Use folder for $title?'),
    content: Text(
      '$folderName\n$episodeCount episodes found.\n\nChoose a folder containing only this series.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(false),
        child: const Text('Cancel'),
      ),
      TextButton(
        autofocus: true,
        onPressed: () => Navigator.of(dialogContext).pop(true),
        child: const Text('Use folder'),
      ),
    ],
  ),
);
