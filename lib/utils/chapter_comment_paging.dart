/// 章节评论（`/api/v3/roasts`）的分页参数。
///
/// 服务端已把每页条数强制压到 10：请求里传更大的 `limit` 也只返回 10 条，
/// 响应里的 `results.limit` 也回显 10。客户端按实际页宽分页，避免合并逻辑
/// 按错误的页宽推算溢出项。
library;

import 'dart:math';

/// 章节评论接口实际返回的每页条数。
const int chapterCommentPageSize = 10;

/// 初始加载页数的默认值与设置范围。
const int chapterCommentInitialPages = 2;
const int chapterCommentMinPages = 1;
const int chapterCommentMaxPages = 5;

int normalizeChapterCommentPages(int pages) =>
    pages.clamp(chapterCommentMinPages, chapterCommentMaxPages);

final _pageGapRandom = Random();

/// 每次连续翻页随机等待 1–1.5 秒，避免短时间内连发请求。
Duration get chapterCommentPageGap =>
    Duration(milliseconds: 1000 + _pageGapRandom.nextInt(501));
