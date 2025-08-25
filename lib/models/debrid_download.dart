// Import PlaylistEntry from video player screen
import '../screens/video_player_screen.dart' show PlaylistEntry;

class DebridDownload {
  final String id;
  final String filename;
  final String mimeType;
  final int filesize;
  final String link;
  final String host;
  final String? hostIcon;
  final int chunks;
  final String download;
  final int streamable;
  final String generated;
  final String? type;

  DebridDownload({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.filesize,
    required this.link,
    required this.host,
    this.hostIcon,
    required this.chunks,
    required this.download,
    required this.streamable,
    required this.generated,
    this.type,
  });

  factory DebridDownload.fromJson(Map<String, dynamic> json) {
    return DebridDownload(
      id: json['id'] ?? '',
      filename: json['filename'] ?? '',
      mimeType: json['mimeType'] ?? '',
      filesize: json['filesize'] ?? 0,
      link: json['link'] ?? '',
      host: json['host'] ?? '',
      hostIcon: json['host_icon'],
      chunks: json['chunks'] ?? 0,
      download: json['download'] ?? '',
      streamable: json['streamable'] ?? 0,
      generated: json['generated'] ?? '',
      type: json['type'],
    );
  }
}

/// Doubly linked list node for efficient torrent navigation
class TorrentNode {
  final String infohash;
  final String torrentName;
  final String videoUrl;
  final String title;
  final String? subtitle;
  final List<PlaylistEntry>? playlist;
  final int? startIndex;
  final int originalIndex;
  final DateTime playedAt;
  
  TorrentNode? next;
  TorrentNode? previous;
  
  TorrentNode({
    required this.infohash,
    required this.torrentName,
    required this.videoUrl,
    required this.title,
    this.subtitle,
    this.playlist,
    this.startIndex,
    required this.originalIndex,
    required this.playedAt,
  });
  

}

/// Doubly linked list for efficient torrent navigation
class TorrentLinkedList {
  TorrentNode? _head;
  TorrentNode? _tail;
  TorrentNode? _current;
  int _size = 0;
  
  /// Get current node
  TorrentNode? get current => _current;
  
  /// Get size of the list
  int get size => _size;
  
  /// Check if list is empty
  bool get isEmpty => _head == null;
  
  /// Add a new torrent to the end of the list
  void add(TorrentNode node) {
    if (_head == null) {
      _head = node;
      _tail = node;
      _current = node;
    } else {
      _tail!.next = node;
      node.previous = _tail;
      _tail = node;
    }
    _size++;
  }
  
  /// Remove current node and return next node
  TorrentNode? removeCurrent() {
    if (_current == null) return null;
    
    final nextNode = _current!.next;
    final prevNode = _current!.previous;
    
    // Update links
    if (prevNode != null) {
      prevNode.next = nextNode;
    } else {
      _head = nextNode;
    }
    
    if (nextNode != null) {
      nextNode.previous = prevNode;
    } else {
      _tail = prevNode;
    }
    
    // Update current pointer
    _current = nextNode ?? prevNode;
    _size--;
    
    return _current;
  }
  
  /// Remove a specific node by infohash
  bool removeNode(String infohash) {
    final nodeToRemove = find(infohash);
    if (nodeToRemove == null) return false;
    
    final nextNode = nodeToRemove.next;
    final prevNode = nodeToRemove.previous;
    
    // Update links
    if (prevNode != null) {
      prevNode.next = nextNode;
    } else {
      _head = nextNode;
    }
    
    if (nextNode != null) {
      nextNode.previous = prevNode;
    } else {
      _tail = prevNode;
    }
    
    // Update current pointer if it was the removed node
    if (_current == nodeToRemove) {
      _current = nextNode ?? prevNode;
    }
    
    _size--;
    return true;
  }
  
  /// Move to next node
  TorrentNode? next() {
    if (_current?.next != null) {
      _current = _current!.next;
      return _current;
    }
    return null;
  }
  
  /// Move to previous node
  TorrentNode? previous() {
    if (_current?.previous != null) {
      _current = _current!.previous;
      return _current;
    }
    return null;
  }
  
  /// Check if there's a next node
  bool hasNext() {
    return _current?.next != null;
  }
  
  /// Check if there's a previous node
  bool hasPrevious() {
    return _current?.previous != null;
  }
  
  /// Find node by infohash
  TorrentNode? find(String infohash) {
    TorrentNode? current = _head;
    while (current != null) {
      if (current.infohash == infohash) {
        return current;
      }
      current = current.next;
    }
    return null;
  }
  
  /// Set current node by infohash
  bool setCurrent(String infohash) {
    final node = find(infohash);
    if (node != null) {
      _current = node;
      return true;
    }
    return false;
  }
  

  
  /// Clear the list
  void clear() {
    _head = null;
    _tail = null;
    _current = null;
    _size = 0;
  }
  
  /// Get all nodes for debugging
  List<TorrentNode> getAllNodes() {
    final nodes = <TorrentNode>[];
    TorrentNode? current = _head;
    while (current != null) {
      nodes.add(current);
      current = current.next;
    }
    return nodes;
  }
} 