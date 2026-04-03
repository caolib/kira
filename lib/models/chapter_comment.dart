class ChapterComment {
  final int id;
  final String createAt;
  final String userId;
  final String userName;
  final String userAvatar;
  final String comment;

  const ChapterComment({
    required this.id,
    required this.createAt,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.comment,
  });

  factory ChapterComment.fromJson(Map<String, dynamic> json) => ChapterComment(
    id: json['id'] is int
        ? json['id'] as int
        : int.tryParse(json['id']?.toString() ?? '') ?? 0,
    createAt: json['create_at']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    userName: json['user_name']?.toString() ?? '匿名用户',
    userAvatar: json['user_avatar']?.toString() ?? '',
    comment: json['comment']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'create_at': createAt,
    'user_id': userId,
    'user_name': userName,
    'user_avatar': userAvatar,
    'comment': comment,
  };
}
