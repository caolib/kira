import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/copy_web_login.dart';

void main() {
  group('parseCopyWebCookies', () {
    test('解析拷贝官网完整 cookie', () {
      final credentials = parseCopyWebCookies({
        'webp': '1',
        '_ga': 'GA1.1.445406201.1784888392',
        'name': '%E5%87%89%E6%A1%91%E8%BF%98%E9%92%B1',
        'token': '2b2400288e24cbfe8ff775fb7595c0618f2fb8f1',
        'user_id': '85ea57c7-fe01-11ed-83ce-0678401a7187',
        'avatar':
            '"user/cover/85ea57c7fe0111ed83ce0678401a7187/1704125272.jpg"',
        'email': '""',
        'csrftoken': 'qZbfclNU2Tqb8vRsruigBzao78tw4Txe',
        'sessionid': '1iumpxmossmvk7wf0mto88i6n75md8bz',
      });

      expect(credentials, isNotNull);
      expect(credentials!.token, '2b2400288e24cbfe8ff775fb7595c0618f2fb8f1');
      expect(credentials.userId, '85ea57c7-fe01-11ed-83ce-0678401a7187');
      expect(credentials.nickname, '凉桑还钱');
      expect(
        credentials.avatar,
        'user/cover/85ea57c7fe0111ed83ce0678401a7187/1704125272.jpg',
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
