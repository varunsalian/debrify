import '../../core/cloud/listing.dart';
import 'models/file.dart';

/// PikPak's shape, handed to the shared browser logic.
///
/// The only PikPak-specific part of filtering, ordering and grouping a folder.
/// Everything else lives in [CloudListing] and is the same for every provider.
const pikpakListing = CloudListing<PikPakFile>(
  isFolder: _isFolder,
  isVideo: _isVideo,
  sizeOf: _sizeOf,
  nameOf: _nameOf,
);

/// A client-side season grouping is a folder as far as browsing is concerned.
bool _isFolder(PikPakFile file) => file.isFolder || file.isVirtual;

bool _isVideo(PikPakFile file) => file.isVideo;

int _sizeOf(PikPakFile file) => file.size;

String _nameOf(PikPakFile file) => file.name;

/// Videos smaller than this are samples and extras, not the thing the user
/// came for. Shared by the browser filter and the TV picker.
const pikpakMinVideoBytes = 100 * 1024 * 1024;
