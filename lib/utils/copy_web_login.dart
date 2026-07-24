import 'dart:async';

import 'app_logger.dart';

/// 从拷贝官网 cookie 中提取的登录凭证。
class CopyWebCredentials {
  final String token;
  final String userId;
  final String nickname;
  final String avatar;

  const CopyWebCredentials({
    required this.token,
    required this.userId,
    required this.nickname,
    required this.avatar,
  });
}

/// 去掉 cookie 值两端的引号（拷贝官网会给部分值加引号）。
String _unquote(String value) {
  var v = value.trim();
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    v = v.substring(1, v.length - 1);
  }
  return v;
}

/// 从拷贝官网（copyLoginHost）的 cookie 表中解析登录凭证。
///
/// 登录成功后官网会写入 `token`、`user_id`、`name`（URL 编码的昵称）、
/// `avatar` 等 cookie。解析失败（未登录）时返回 null。
CopyWebCredentials? parseCopyWebCookies(Map<String, String> cookies) {
  final token = _unquote(cookies['token'] ?? '');
  if (token.isEmpty) return null;

  String nickname = '';
  try {
    nickname = Uri.decodeComponent(_unquote(cookies['name'] ?? ''));
  } catch (e, st) {
    unawaited(
      AppLogger.instance.recordWarning(
        e,
        stackTrace: st,
        source: 'copy_web_login.parse',
      ),
    );
  }

  return CopyWebCredentials(
    token: token,
    userId: _unquote(cookies['user_id'] ?? ''),
    nickname: nickname,
    avatar: _unquote(cookies['avatar'] ?? ''),
  );
}
