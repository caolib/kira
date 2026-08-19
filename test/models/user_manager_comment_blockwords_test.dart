import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserManager user;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    user = UserManager();
    // 单例可能携带上次测试的内存态，先清空屏蔽词。
    await user.setCommentBlockwords([]);
  });

  group('isCommentBlockedByWord', () {
    test('空屏蔽词列表不过滤任何内容', () {
      expect(user.isCommentBlockedByWord('任意评论'), isFalse);
      expect(user.isCommentBlockedByWord(''), isFalse);
    });

    test('命中屏蔽词返回 true', () async {
      await user.setCommentBlockwords(['广告']);
      expect(user.isCommentBlockedByWord('这是广告内容'), isTrue);
      expect(user.isCommentBlockedByWord('正常评论'), isFalse);
    });

    test('大小写不敏感', () async {
      await user.setCommentBlockwords(['SPAM']);
      expect(user.isCommentBlockedByWord('this is spam'), isTrue);
      expect(user.isCommentBlockedByWord('THIS IS SPAM'), isTrue);
    });

    test('多个屏蔽词任一命中即过滤', () async {
      await user.setCommentBlockwords(['广告', '加微信']);
      expect(user.isCommentBlockedByWord('加微信送福利'), isTrue);
      expect(user.isCommentBlockedByWord('广告推广'), isTrue);
      expect(user.isCommentBlockedByWord('正常讨论'), isFalse);
    });

    test('空内容不过滤', () async {
      await user.setCommentBlockwords(['广告']);
      expect(user.isCommentBlockedByWord(''), isFalse);
    });
  });

  group('blockwords persistence', () {
    test('addCommentBlockword 去重且去空白', () async {
      await user.setCommentBlockwords([]);
      await user.addCommentBlockword('  垃圾  ');
      await user.addCommentBlockword('垃圾');
      expect(user.commentBlockwords, ['垃圾']);
    });

    test('removeCommentBlockword 移除指定词', () async {
      await user.setCommentBlockwords(['a', 'b', 'c']);
      await user.removeCommentBlockword('b');
      expect(user.commentBlockwords, ['a', 'c']);
    });

    test('clearCommentBlockwords 清空列表', () async {
      await user.setCommentBlockwords(['a', 'b']);
      await user.clearCommentBlockwords();
      expect(user.commentBlockwords, isEmpty);
    });
  });

  group('group spam preset', () {
    test('默认关闭，不匹配', () {
      expect(user.commentBlockGroupSpam, isFalse);
      expect(user.isCommentGroupSpam('加群1234567890领福利'), isFalse);
    });

    test('同时含「群」与 8~12 位数字命中', () async {
      await user.setCommentBlockGroupSpam(true);
      expect(user.isCommentGroupSpam('加群1234567890领福利'), isTrue);
      expect(user.isCommentGroupSpam('群聊 98765432109876'), isTrue);
      expect(user.isCommentGroupSpam('QQ群87654321'), isTrue);
    });

    test('仅含群但无足够位数数字不命中', () async {
      await user.setCommentBlockGroupSpam(true);
      expect(user.isCommentGroupSpam('群聊1234567只有7位'), isFalse);
      expect(user.isCommentGroupSpam('加群1234567'), isFalse);
    });

    test('仅含数字但无「群」不命中', () async {
      await user.setCommentBlockGroupSpam(true);
      expect(user.isCommentGroupSpam('电话13912345678'), isFalse);
    });

    test('数字超过12位仍按最长匹配命中', () async {
      await user.setCommentBlockGroupSpam(true);
      // 13 位连续数字含 8~12 位子串，命中。
      expect(user.isCommentGroupSpam('群号1234567890123'), isTrue);
    });
  });
}
