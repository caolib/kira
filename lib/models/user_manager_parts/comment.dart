part of '../user_manager.dart';

extension UserManagerCommentPart on UserManager {
  /// `entry` 格式：`userId|userName`（userId 可为空字符串，userName 作为兜底标识）。
  bool isCommentUserBlocked(String userId, String userName) {
    if (userId.isEmpty && userName.isEmpty) return false;
    for (final raw in _commentBlockedUsers) {
      final sep = raw.indexOf('|');
      if (sep < 0) {
        if (userId.isNotEmpty && raw == userId) return true;
        continue;
      }
      final bId = raw.substring(0, sep);
      final bName = raw.substring(sep + 1);
      if (userId.isNotEmpty && bId == userId) return true;
      if (userId.isEmpty && userName.isNotEmpty && bName == userName) {
        return true;
      }
    }
    return false;
  }

  Future<void> blockCommentUser(String userId, String userName) async {
    final key = '$userId|$userName';
    if (_commentBlockedUsers.any((e) => e == key)) return;
    _commentBlockedUsers = [..._commentBlockedUsers, key];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      UserManager._keyCommentBlockedUsers,
      _commentBlockedUsers,
    );
    _notifyListeners();
  }

  Future<void> unblockCommentUser(String rawKey) async {
    _commentBlockedUsers = _commentBlockedUsers
        .where((e) => e != rawKey)
        .toList(growable: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      UserManager._keyCommentBlockedUsers,
      _commentBlockedUsers,
    );
    _notifyListeners();
  }

  Future<void> clearCommentBlockedUsers() async {
    _commentBlockedUsers = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(UserManager._keyCommentBlockedUsers);
    _notifyListeners();
  }

  Future<void> setCommentBlockNoRemind(bool value) async {
    _commentBlockNoRemind = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCommentBlockNoRemind, value);
    _notifyListeners();
  }

  Future<void> setCommentBlockwords(List<String> list) async {
    _commentBlockwords = List.from(list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      UserManager._keyCommentBlockwords,
      _commentBlockwords,
    );
    _notifyListeners();
  }

  Future<void> addCommentBlockword(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty || _commentBlockwords.contains(trimmed)) return;
    _commentBlockwords = [..._commentBlockwords, trimmed];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      UserManager._keyCommentBlockwords,
      _commentBlockwords,
    );
    _notifyListeners();
  }

  Future<void> removeCommentBlockword(String word) async {
    _commentBlockwords = _commentBlockwords
        .where((e) => e != word)
        .toList(growable: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      UserManager._keyCommentBlockwords,
      _commentBlockwords,
    );
    _notifyListeners();
  }

  Future<void> clearCommentBlockwords() async {
    _commentBlockwords = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(UserManager._keyCommentBlockwords);
    _notifyListeners();
  }

  /// 评论内容是否命中任一屏蔽词（大小写不敏感）。
  bool isCommentBlockedByWord(String content) {
    if (_commentBlockwords.isEmpty || content.isEmpty) return false;
    final lower = content.toLowerCase();
    for (final word in _commentBlockwords) {
      if (word.isEmpty) continue;
      if (lower.contains(word.toLowerCase())) return true;
    }
    return false;
  }

  /// 群广告预设正则：内容含「群」且含 8~12 位连续数字。
  static final _groupSpamRegex = RegExp(r'\d{8,12}');

  bool isCommentGroupSpam(String content) {
    if (!_commentBlockGroupSpam || content.isEmpty) return false;
    if (!content.contains('群')) return false;
    return _groupSpamRegex.hasMatch(content);
  }

  Future<void> setCommentBlockGroupSpam(bool value) async {
    _commentBlockGroupSpam = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCommentBlockGroupSpam, value);
    _notifyListeners();
  }
}
