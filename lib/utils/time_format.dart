/// 相对时间格式化工具。
///
/// 将时间转换为"刚刚 / N 分钟前 / N 小时前 / N 天前 / N 个月前 / N 年前"的描述，
/// 统一各页面历史版本中重复的实现。
class TimeFormat {
  TimeFormat._();

  /// 解析日期字符串并返回相对时间；解析失败时原样返回。
  /// 兼容 `2024-01-01T12:00:00` 与 `2024-01-01 12:00:00` 两种写法。
  static String relativeOf(String dateStr) {
    if (dateStr.isEmpty) return dateStr;
    final normalized = dateStr.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return dateStr;
    return relative(parsed);
  }

  /// 将 [DateTime] 转换为相对时间描述，未来时间视为"刚刚"。
  static String relative(DateTime time) {
    final local = time.isUtc ? time.toLocal() : time;
    final diff = DateTime.now().difference(local);
    if (diff.isNegative || diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }
}
