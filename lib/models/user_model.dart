// lib/models/user_model.dart

class AppUser {
  String id;
  String nickname;

  AppUser({required this.id, required this.nickname});

  factory AppUser.guest() => AppUser(id: '', nickname: '');

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        nickname: (json['nickname'] as String?) ?? '사용자',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
      };
}
