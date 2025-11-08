class Torrent {
  final int rowid;
  final String infohash;
  final String name;
  final int sizeBytes;
  final int createdUnix;
  final int seeders;
  final int leechers;
  final int completed;
  final int scrapedDate;
  final String? category; // Optional: PirateBay category (5xx = NSFW)
  final String source;

  Torrent({
    required this.rowid,
    required this.infohash,
    required this.name,
    required this.sizeBytes,
    required this.createdUnix,
    required this.seeders,
    required this.leechers,
    required this.completed,
    required this.scrapedDate,
    this.category,
    String? source,
  }) : source = (source ?? '').trim().toLowerCase();

  factory Torrent.fromJson(
    Map<String, dynamic> json, {
    String? source,
  }) {
    final dynamic rawSource =
        json['source'] ?? json['provider'] ?? json['engine'] ?? source;
    return Torrent(
      rowid: json['rowid'] ?? 0,
      infohash: json['infohash'] ?? '',
      name: json['name'] ?? '',
      sizeBytes: json['size_bytes'] ?? 0,
      createdUnix: json['created_unix'] ?? 0,
      seeders: json['seeders'] ?? 0,
      leechers: json['leechers'] ?? 0,
      completed: json['completed'] ?? 0,
      scrapedDate: json['scraped_date'] ?? 0,
      category: json['category']?.toString(),
      source: rawSource?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rowid': rowid,
      'infohash': infohash,
      'name': name,
      'size_bytes': sizeBytes,
      'created_unix': createdUnix,
      'seeders': seeders,
      'leechers': leechers,
      'completed': completed,
      'scraped_date': scrapedDate,
      if (category != null) 'category': category,
      if (source.isNotEmpty) 'source': source,
    };
  }
}
