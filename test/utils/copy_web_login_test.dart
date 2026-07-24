import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/copy_web_login.dart';

void main() {
  group('parseCopyWebCookies', () {
    test('解析拷贝官网完整 cookie', () {
      final credentials = parseCopyWebCookies({
        'webp': '1',
        '_ga': 'GA1.1.000000000.0000000000',
        'name': '%E5%87%89%E6%A1%91%E8%BF%98%E9%92%B1',
        'token': 'test_token_0123456789abcdef0123456789ab',
        'user_id': '00000000-0000-0000-0000-000000000001',
        'avatar':
            '"user/cover/00000000000000000000000000000001/1704125272.jpg"',
        'email': '""',
        'csrftoken': 'test_csrf_token_0000000000000000',
        'sessionid': 'test_session_id_000000000000000000',
      });

      expect(credentials, isNotNull);
      expect(credentials!.token, 'test_token_0123456789abcdef0123456789ab');
      expect(credentials.userId, '00000000-0000-0000-0000-000000000001');
      expect(credentials.nickname, '凉桑还钱');
      expect(
        credentials.avatar,
        'user/cover/00000000000000000000000000000001/1704125272.jpg',
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
