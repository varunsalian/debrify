class RDUser {
  final int id;
  final String username;
  final String email;
  final int points;
  final String locale;
  final String avatar;
  final String type;
  final int premium;
  final String expiration;

  RDUser({
    required this.id,
    required this.username,
    required this.email,
    required this.points,
    required this.locale,
    required this.avatar,
    required this.type,
    required this.premium,
    required this.expiration,
  });

  factory RDUser.fromJson(Map<String, dynamic> json) {
    return RDUser(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      points: json['points'] as int,
      locale: json['locale'] as String,
      avatar: json['avatar'] as String,
      type: json['type'] as String,
      premium: json['premium'] as int,
      expiration: json['expiration'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'points': points,
      'locale': locale,
      'avatar': avatar,
      'type': type,
      'premium': premium,
      'expiration': expiration,
    };
  }

  bool get isPremium => type == 'premium';
  
  String get premiumStatusText {
    if (isPremium) {
      final daysLeft = (premium / (24 * 60 * 60)).floor();
      if (daysLeft > 0) {
        return 'Premium ($daysLeft days left)';
      } else {
        return 'Premium (Expires soon)';
      }
    } else {
      return 'Free';
    }
  }

  String get formattedExpiration {
    try {
      final date = DateTime.parse(expiration);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return expiration;
    }
  }
} 