import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_transport.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/chapter_comment_paging.dart';
import 'package:kira/utils/data_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// 按请求里的 offset 返回一页 10 条假评论，并记录每次请求的 offset。
class _FakeCommentAdapter implements HttpClientAdapter {
  _FakeCommentAdapter({required this.total});

  final int total;
  final List<int> offsets = [];
  bool repeatFirstPage = false;
  bool returnEmptyPage = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final offset = int.parse(options.queryParameters['offset'].toString());
    offsets.add(offset);
    final start = repeatFirstPage ? 0 : offset;
    final end = returnEmptyPage
        ? start
        : (start + chapterCommentPageSize).clamp(0, total);
    final list = [
      for (var i = start; i < end; i++)
        {
          'id': i,
          'create_at': '2026-08-23 04:18:00',
          'user_id': 'user-$i',
          'user_name': '用户$i',
          'user_avatar': '',
          'comment': '评论$i',
        },
    ];
    return ResponseBody.fromString(
      '{"code":200,"message":"Success.","results":{"total":$total,'
      '"list":${_encode(list)},"limit":10,"offset":$offset}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  static String _encode(List<Map<String, Object>> list) {
    final items = list.map((item) {
      final fields = item.entries
          .map((e) => '"${e.key}":${_value(e.value)}')
          .join(',');
      return '{$fields}';
    });
    return '[${items.join(',')}]';
  }

  static String _value(Object value) => value is int ? '$value' : '"$value"';

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  late MangaApi api;
  late _FakeCommentAdapter adapter;

  Future<void> setUpApi({required int total}) async {
    SharedPreferences.setMockInitialValues({});
    final user = UserManager();
    await user.init();
    final commentDio = Dio()
      ..httpClientAdapter = (adapter = _FakeCommentAdapter(total: total));
    final transport = ApiTransport(
      dio: Dio(),
      commentDio: commentDio,
      user: user,
      cache: DataCache(),
    );
    api = MangaApi(transport);
  }

  test('随机翻页间隔保持在1–1.5秒且不会固定为同一值', () {
    final gaps = List.generate(
      100,
      (_) => chapterCommentPageGap.inMilliseconds,
    );
    expect(gaps, everyElement(inInclusiveRange(1000, 1500)));
    expect(gaps.toSet().length, greaterThan(1));
    expect(normalizeChapterCommentPages(0), 1);
    expect(normalizeChapterCommentPages(6), 5);
  });

  for (final pages in [1, 3, 5]) {
    test('getChapterCommentsPages 使用用户设置的$pages页', () async {
      await setUpApi(total: 78);
      await UserManager().setCommentInitialPages(pages);
      final data = await api.getChapterCommentsPages('chapter-1');
      expect(data.list.length, chapterCommentPageSize * pages);
      expect(
        adapter.offsets,
        List.generate(pages, (i) => i * chapterCommentPageSize),
      );
    });
  }

  test('加载任务开始后修改设置不会改变本次页数', () async {
    await setUpApi(total: 78);
    await UserManager().setCommentInitialPages(2);
    final loading = api.getChapterCommentsPages('chapter-1');
    await UserManager().setCommentInitialPages(5);
    final data = await loading;
    expect(data.list.length, 20);
    expect(adapter.offsets, [0, 10]);
  });

  test('显式页数覆盖用户设置，末页不足时提前停止', () async {
    await setUpApi(total: 12);
    await UserManager().setCommentInitialPages(1);
    final data = await api.getChapterCommentsPages('chapter-1', pages: 5);
    expect(data.list.length, 12);
    expect(adapter.offsets, [0, 10]);
  });

  test('重复数据不会继续请求后续页', () async {
    await setUpApi(total: 78);
    adapter.repeatFirstPage = true;
    final data = await api.getChapterCommentsPages('chapter-1', pages: 5);
    expect(data.list.length, 10);
    expect(adapter.offsets, [0, 10]);
  });

  test('返回空页即使总数非零也不继续请求', () async {
    await setUpApi(total: 78);
    adapter.returnEmptyPage = true;
    final data = await api.getChapterCommentsPages('chapter-1', pages: 5);
    expect(data.list, isEmpty);
    expect(adapter.offsets, [0]);
  });

  test('getChapterCommentsPages 按服务端页宽连续取两页', () async {
    await setUpApi(total: 78);

    final data = await api.getChapterCommentsPages('chapter-1');

    expect(data.list.length, chapterCommentPageSize * 2);
    expect(data.total, 78);
    expect(adapter.offsets, [0, chapterCommentPageSize]);
  });

  test('getChapterCommentsPages 不超出总条数', () async {
    await setUpApi(total: 12);

    final data = await api.getChapterCommentsPages('chapter-1');

    expect(data.list.length, 12);
    expect(adapter.offsets, [0, chapterCommentPageSize]);
  });

  test('getChapterCommentsPages 只有一页时不再发第二次请求', () async {
    await setUpApi(total: 3);

    final data = await api.getChapterCommentsPages('chapter-1');

    expect(data.list.length, 3);
    expect(adapter.offsets, [0]);
  });
}
