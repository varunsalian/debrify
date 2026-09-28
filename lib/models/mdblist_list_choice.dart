/// A selectable MDBList list. Value-equal by its numeric id so a dropdown can
/// match the current selection across rebuilds.
class MdblistListChoice {
  final int id;
  final String name;
  final int itemCount;
  final String? mediatype;

  /// The list owner's username (`user_name`), used to label public/top lists
  /// ("Name · owner"). Null/absent for the user's own lists.
  final String? ownerName;

  /// Whether the authenticated user has liked this list (per-user `liked`
  /// flag; flips immediately when toggled via the like endpoint).
  final bool liked;

  /// Total like count on MDBList.
  final int likes;

  const MdblistListChoice({
    required this.id,
    required this.name,
    this.itemCount = 0,
    this.mediatype,
    this.ownerName,
    this.liked = false,
    this.likes = 0,
  });

  factory MdblistListChoice.fromJson(Map<String, dynamic> j) {
    int? integer(Object? value) => value is num
        ? value.toInt()
        : value is String
        ? int.tryParse(value)
        : null;
    final rawName = j['name']?.toString();
    final owner = j['user_name']?.toString().trim();
    return MdblistListChoice(
      id: integer(j['id']) ?? -1,
      name: (rawName == null || rawName.trim().isEmpty)
          ? 'Untitled list'
          : rawName,
      itemCount: integer(j['items']) ?? 0,
      mediatype: j['mediatype']?.toString(),
      ownerName: (owner == null || owner.isEmpty) ? null : owner,
      liked: j['liked'] == true,
      likes: integer(j['likes']) ?? 0,
    );
  }

  String get label => name;

  @override
  bool operator ==(Object other) =>
      other is MdblistListChoice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
