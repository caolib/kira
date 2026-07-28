/// 评论分页合并，供漫画评论与章节评论共用。
library;

/// 按 id 去重地把 [incoming] 追加到 [existing] 之后。
///
/// 三处调用点原本各写一遍 `incoming.where((x) => !existing.any((y) => y.id == x.id))`，
/// 是 O(existing × incoming)；改用 Set 后为线性，评论量大时差别明显。
/// 同时也会去掉 [incoming] 自身的重复项——服务端在分页边界重复返回同一条
/// 评论时，旧写法会把它放进去。
List<T> appendDedupedById<T>(
  Iterable<T> existing,
  Iterable<T> incoming,
  Object Function(T) idOf,
) {
  final result = existing.toList();
  final seen = result.map(idOf).toSet();
  for (final item in incoming) {
    if (seen.add(idOf(item))) result.add(item);
  }
  return result;
}
