import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/android_local_source_service.dart';
import '../../../utils/file_utils.dart';
import '../data/local_source_file_picker.dart';
import '../data/local_source_file_rules.dart';
import '../data/local_source_files.dart';
import 'android_local_source_picker.dart';
import 'desktop_local_source_picker.dart';
import 'local_series_folder_resolution.dart';
import 'local_source_picker.dart';

const localBindingMobileDisabledReason =
    'Local source binding is not supported on iOS yet.';

/// App-lifetime stateless wiring; no request, profile or widget state is retained.
final localSourcePicker = _createLocalSourcePicker();

final localSourcePickerProvider = Provider<LocalSourcePicker>(
  (ref) => localSourcePicker,
  dependencies: const [],
);

LocalSourcePicker _createLocalSourcePicker() {
  final android = Platform.isAndroid;
  final androidPicker = AndroidLocalSourcePicker(
    pick: AndroidLocalSourceService.pick,
    scan: AndroidLocalSourceService.videos,
    isVideoFile: FileUtils.isVideoFile,
    episodeCount: (documents) =>
        AndroidLocalSourceService.episodes(documents).length,
  );
  return LocalSourcePicker(
    androidFolderSelection: android,
    disabledReason: Platform.isIOS ? localBindingMobileDisabledReason : null,
    file: (context, {canContinue}) => android
        ? androidPicker.pickMovie(
            context,
            folder: false,
            canContinue: canContinue,
          )
        : pickLocalVideoSource(canContinue: canContinue),
    movieFolder: (context, {required title, year, canContinue}) => android
        ? androidPicker.pickMovie(
            context,
            folder: true,
            canContinue: canContinue,
          )
        : pickDesktopMovieFolder(
            context,
            pickDirectory: pickLocalDirectory,
            scan: (path) =>
                scanLocalVideoFolder(path, canContinue: canContinue),
            match: (candidates) =>
                matchLocalMovieFiles(candidates, title: title, year: year),
            describe: (candidate) =>
                localSourceFromFile(candidate.file, canContinue: canContinue),
            canContinue: canContinue,
          ),
    seriesFolder: (context, {required title, canContinue}) => android
        ? androidPicker.pickSeries(context, title, canContinue: canContinue)
        : pickDesktopSeriesFolder(
            context,
            pickDirectory: pickLocalDirectory,
            resolve: (path) => resolveLocalSeriesFolder(
              context,
              title: title,
              pickedFolderName: localPathName(path),
              lookup: () => lookupLocalSeriesFolders(
                path,
                title: title,
                canContinue: canContinue,
              ),
              canContinue: canContinue,
            ),
            scan: (path) =>
                scanLocalSeriesFolder(path, canContinue: canContinue),
            describe: (folder, count) => localSourceFromSeriesFolder(
              folder,
              title: title,
              episodeCount: count,
              canContinue: canContinue,
            ),
            canContinue: canContinue,
          ),
  );
}
