/// 评论正文的长度规则，客户端校验与 API 层前置检查共用。
///
/// 此前 `3` / `200` 硬编码在 10 处、跨 3 个文件，改一个上限要改十处。
class CommentText {
  const CommentText._();

  static const minLength = 3;
  static const maxLength = 200;

  /// 有效长度：去掉首尾空白后按码位计数。
  ///
  /// 用 `runes` 而非 `String.length`，否则 emoji 等增补平面字符会按 UTF-16
  /// 的两个单元计算，用户看到的字数和校验结果对不上。
  static int lengthOf(String text) => text.trim().runes.length;

  static bool isValid(String text) {
    final length = lengthOf(text);
    return length >= minLength && length <= maxLength;
  }
}
