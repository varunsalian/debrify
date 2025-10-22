import '../models/rd_torrent.dart';
import '../models/torbox_torrent.dart';

enum TorboxQuickAction {
  play,
  download,
  files,
}

class MainPageBridge {
  static void Function(int index)? switchTab;
  static void Function(RDTorrent torrent)? openDebridOptions;
  static void Function(TorboxTorrent torrent, TorboxQuickAction action)?
      openTorboxAction;
}

