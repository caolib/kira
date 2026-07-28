import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/copy_web_login.dart';

void main() {
  group('parseCopyWebCookies', () {
    test('解析拷贝官网完整 cookie', () {
      final credentials = parseCopyWebCookies({
        'webp': '1',
        '_ga': 'GA1.1.000000000.0000000000',
        'name': '%E6%B5%8B%E8%AF%95%E7%94%A8%E6%88%B7',
        'token': 'test_token_0123456789abcdef0123456789ab',
        'user_id': '00000000-0000-0000-0000-000000000001',
        'avatar':
            '"user/cover/00000000000000000000000000000001/0000000000.jpg"',
        'email': '""',
        'csrftoken': 'test_csrf_token_0000000000000000',
        'sessionid': 'test_session_id_000000000000000000',
      });

      expect(credentials, isNotNull);
      expect(credentials!.token, 'test_token_0123456789abcdef0123456789ab');
      expect(credentials.userId, '00000000-0000-0000-0000-000000000001');
      expect(credentials.nickname, '测试用户');
      expect(
        credentials.avatar,
        'user/cover/00000000000000000000000000000001/0000000000.jpg',
      );
    });

    test('缺少 token 时返回 null（未登录）', () {
      expect(parseCopyWebCookies({'webp': '1', '_ga': 'x'}), isNull);
      expect(parseCopyWebCookies({}), isNull);
    });

    test('token 为空字符串时返回 null', () {
      expect(parseCopyWebCookies({'token': ''}), isNull);
      expect(parseCopyWebCookies({'token': '""'}), isNull);
    });

    test('可选字段缺失时回退为空字符串', () {
      final credentials = parseCopyWebCookies({'token': 'abc'});

      expect(credentials, isNotNull);
      expect(credentials!.token, 'abc');
      expect(credentials.userId, '');
      expect(credentials.nickname, '');
      expect(credentials.avatar, '');
    });

    test('name 非法编码时不影响 token 解析', () {
      final credentials = parseCopyWebCookies({
        'token': 'abc',
        'name': '%E4%B8%AD%', // 截断的编码
      });

      expect(credentials, isNotNull);
      expect(credentials!.token, 'abc');
      expect(credentials.nickname, '');
    });

    test('带引号的 token 会去引号', () {
      final credentials = parseCopyWebCookies({'token': '"abc123"'});

      expect(credentials, isNotNull);
      expect(credentials!.token, 'abc123');
    });
  });
}
