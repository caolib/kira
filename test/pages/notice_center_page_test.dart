import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/remote_notice.dart';
import 'package:kira/pages/notice_center_page.dart';
import 'package:kira/utils/remote_notice_service.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      useMaterial3: true,
      cardTheme: const CardThemeData(elevation: 3),
    ),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    RemoteNoticeService.unreadActiveCount.value = 0;
  });

  testWidgets('does not mark notices as read when opened', (tester) async {
    final notice = RemoteNotice(
      id: 'new-notice',
      title: '新通知',
      content: '通知内容',
      publishedAt: DateTime.now(),
    );
    final service = _FakeNoticeService(notices: [notice]);

    await tester.pumpWidget(_buildTestApp(NoticeCenterPage(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('新通知'), findsOneWidget);
    expect(find.text('未读'), findsNothing);
    expect(
      find.byKey(const ValueKey('notice-unread-dot-new-notice')),
      findsOneWidget,
    );
    expect(find.byTooltip('全部已读'), findsOneWidget);
    expect(service.markSeenCalls, 0);
    expect(RemoteNoticeService.unreadActiveCount.value, 1);
  });

  testWidgets('marks all notices as read after tapping the action', (
    tester,
  ) async {
    final notice = RemoteNotice(
      id: 'new-notice',
      title: '新通知',
      content: '通知内容',
      publishedAt: DateTime.now(),
    );
    final service = _FakeNoticeService(notices: [notice]);

    await tester.pumpWidget(_buildTestApp(NoticeCenterPage(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('全部已读'));
    await tester.pump();

    expect(find.text('已读通知'), findsNothing);
    expect(find.text('新通知'), findsOneWidget);
    expect(find.text('未读'), findsNothing);
    expect(
      find.byKey(const ValueKey('notice-unread-dot-new-notice')),
      findsNothing,
    );
    expect(service.markSeenCalls, 1);
    expect(RemoteNoticeService.unreadActiveCount.value, 0);
  });

  testWidgets('marks a single notice as read after tapping its card', (
    tester,
  ) async {
    final now = DateTime.now();
    final first = RemoteNotice(
      id: 'first-notice',
      title: '第一条通知',
      content: '第一条内容',
      publishedAt: now,
    );
    final second = RemoteNotice(
      id: 'second-notice',
      title: '第二条通知',
      content: '第二条内容',
      publishedAt: now.subtract(const Duration(minutes: 1)),
    );
    final service = _FakeNoticeService(notices: [first, second]);

    await tester.pumpWidget(_buildTestApp(NoticeCenterPage(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第一条通知'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('notice-unread-dot-first-notice')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('notice-unread-dot-second-notice')),
      findsOneWidget,
    );
    expect(find.textContaining('第一条内容', findRichText: true), findsOneWidget);
    expect(service.markSeenCalls, 1);
    expect(service.markedNoticeIds, ['first-notice']);
    expect(RemoteNoticeService.unreadActiveCount.value, 1);
  });

  testWidgets('collapses read notice content and toggles it on tap', (
    tester,
  ) async {
    final notice = RemoteNotice(
      id: 'read-notice',
      title: '已读通知标题',
      content: '已读通知正文',
      publishedAt: DateTime.now(),
    );
    final service = _FakeNoticeService(
      notices: [notice],
      seenKeys: {RemoteNoticeService.seenKeyFor(notice)},
    );

    await tester.pumpWidget(_buildTestApp(NoticeCenterPage(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('已读通知标题'), findsOneWidget);
    expect(find.textContaining('已读通知正文', findRichText: true), findsNothing);

    await tester.tap(find.text('已读通知标题'));
    await tester.pump();

    expect(find.textContaining('已读通知正文', findRichText: true), findsOneWidget);

    await tester.tap(find.text('已读通知标题'));
    await tester.pump();

    expect(find.textContaining('已读通知正文', findRichText: true), findsNothing);
    expect(service.markSeenCalls, 0);
  });

  testWidgets('uses notice type colors for 2px card borders', (tester) async {
    final now = DateTime.now();
    final notices = [
      RemoteNotice(
        id: 'note',
        title: '说明通知',
        content: '通知内容',
        publishedAt: now,
      ),
      RemoteNotice(
        id: 'tip',
        title: '提示通知',
        content: '通知内容',
        publishedAt: now.subtract(const Duration(minutes: 1)),
        type: RemoteNoticeType.tip,
      ),
      RemoteNotice(
        id: 'warning',
        title: '警告通知',
        content: '通知内容',
        publishedAt: now.subtract(const Duration(minutes: 2)),
        type: RemoteNoticeType.warning,
      ),
      RemoteNotice(
        id: 'important',
        title: '重要通知',
        content: '通知内容',
        publishedAt: now.subtract(const Duration(minutes: 3)),
        type: RemoteNoticeType.important,
      ),
      RemoteNotice(
        id: 'caution',
        title: '注意通知',
        content: '通知内容',
        publishedAt: now.subtract(const Duration(minutes: 4)),
        type: RemoteNoticeType.caution,
      ),
    ];
    final service = _FakeNoticeService(notices: notices);

    await tester.pumpWidget(_buildTestApp(NoticeCenterPage(service: service)));
    await tester.pumpAndSettle();

    final cards = tester.widgetList<Card>(find.byType(Card)).toList();
    final borderSides = cards.map(_cardBorderSide).toList();
    final borderColors = borderSides
        .map((side) => side.color.toARGB32())
        .toSet();

    expect(cards, hasLength(5));
    expect(borderSides.map((side) => side.width).toSet(), {2.0});
    expect(borderColors, hasLength(5));
    for (final card in cards) {
      expect(card.color, isNot(_cardBorderSide(card).color));
      expect(card.color!.a, 1.0);
      expect(card.elevation, isNull);
    }

    final colorScheme = Theme.of(
      tester.element(find.byType(NoticeCenterPage)),
    ).colorScheme;
    expect(
      cards.first.color,
      Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.045),
        colorScheme.surface,
      ),
    );
  });

  testWidgets('uses timeline marker shape instead of pinned tag', (
    tester,
  ) async {
    final notice = RemoteNotice(
      id: 'pinned-notice',
      title: '置顶样式通知',
      content: '通知内容',
      publishedAt: DateTime.now(),
      level: RemoteNoticeLevel.pinned,
    );
    final service = _FakeNoticeService(notices: [notice]);

    await tester.pumpWidget(_buildTestApp(NoticeCenterPage(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('置顶'), findsNothing);
    expect(find.bySemanticsLabel('置顶通知节点'), findsOneWidget);
  });

  testWidgets('folds expired notices only', (tester) async {
    final now = DateTime.now();
    final readNotice = RemoteNotice(
      id: 'read-notice',
      title: '已读通知标题',
      content: '已读内容',
      publishedAt: now.subtract(const Duration(hours: 2)),
    );
    final expiredNotice = RemoteNotice(
      id: 'expired-notice',
      title: '过期通知标题',
      content: '过期内容',
      publishedAt: now.subtract(const Duration(days: 3)),
      expiresAt: now.subtract(const Duration(days: 1)),
    );
    final service = _FakeNoticeService(
      notices: [readNotice, expiredNotice],
      seenKeys: {RemoteNoticeService.seenKeyFor(readNotice)},
    );

    await tester.pumpWidget(_buildTestApp(NoticeCenterPage(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('已读通知标题'), findsOneWidget);
    expect(find.text('已读通知'), findsNothing);
    expect(find.text('过期通知'), findsOneWidget);
    expect(find.text('过期通知标题'), findsNothing);

    await tester.tap(find.text('过期通知'));
    await tester.pump();

    expect(find.text('过期通知标题'), findsOneWidget);
  });

  testWidgets('does not badge expired unread notices', (tester) async {
    final now = DateTime.now();
    final expiredNotice = RemoteNotice(
      id: 'expired-unread-notice',
      title: '过期未读通知标题',
      content: '过期未读内容',
      publishedAt: now.subtract(const Duration(days: 3)),
      expiresAt: now.subtract(const Duration(days: 1)),
    );
    final service = _FakeNoticeService(notices: [expiredNotice]);

    await tester.pumpWidget(_buildTestApp(NoticeCenterPage(service: service)));
    await tester.pumpAndSettle();

    expect(find.byTooltip('全部已读'), findsNothing);
    expect(RemoteNoticeService.unreadActiveCount.value, 0);

    await tester.tap(find.text('过期通知'));
    await tester.pump();

    expect(find.text('过期未读通知标题'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notice-unread-dot-expired-unread-notice')),
      findsNothing,
    );
  });

  testWidgets('shows only relative time on notice cards', (tester) async {
    final notice = RemoteNotice(
      id: 'relative-time',
      title: '相对时间通知',
      content: '通知内容',
      publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    final service = _FakeNoticeService(notices: [notice]);

    await tester.pumpWidget(_buildTestApp(NoticeCenterPage(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('2小时前'), findsOneWidget);
    expect(find.textContaining(' · '), findsNothing);
  });
}

BorderSide _cardBorderSide(Card card) {
  final shape = card.shape;
  if (shape is RoundedRectangleBorder) return shape.side;
  fail('notice card should use RoundedRectangleBorder');
}

class _FakeNoticeService extends RemoteNoticeService {
  _FakeNoticeService({required this.notices, Set<String>? seenKeys})
    : _seenKeys = {...?seenKeys},
      super(noticeUrl: '');

  final List<RemoteNotice> notices;
  final Set<String> _seenKeys;
  final List<String> markedNoticeIds = [];
  int markSeenCalls = 0;

  @override
  Future<RemoteNoticeSyncResult> sync() async {
    final unseenActive = _unseenActive();
    RemoteNoticeService.unreadActiveCount.value = unseenActive.length;
    return RemoteNoticeSyncResult(notices: notices, unseenActive: unseenActive);
  }

  @override
  Future<Set<String>> loadSeenKeys() async {
    return {..._seenKeys};
  }

  @override
  Future<void> markSeen(Iterable<RemoteNotice> notices) async {
    markSeenCalls += 1;
    final next = notices.toList();
    markedNoticeIds.addAll(next.map((notice) => notice.id));
    _seenKeys.addAll(next.map(RemoteNoticeService.seenKeyFor));
  }

  @override
  Future<int> updateUnreadActiveCount(List<RemoteNotice> notices) async {
    final count = _unseenActive().length;
    RemoteNoticeService.unreadActiveCount.value = count;
    return count;
  }

  List<RemoteNotice> _unseenActive() {
    final now = DateTime.now();
    return notices
        .where((notice) => notice.isActive(now))
        .where(
          (notice) =>
              !_seenKeys.contains(RemoteNoticeService.seenKeyFor(notice)),
        )
        .toList();
  }
}
