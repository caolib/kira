import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_transport.dart';
import 'package:kira/models/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserManager user;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    user = UserManager();
    // 单例可能携带上次测试的内存态；清掉登录域名相关键后再 init 复位。
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('copy_login_custom_hosts');
    await prefs.setString('copy_login_host', defaultCopyLoginHost);
    await user.init();
  });

  group('addCustomCopyLoginHost', () {
    test('原样保留（不校验合法性）并持久化', () async {
      expect(
        await user.addCustomCopyLoginHost(' https://Copy5000.COM '),
        isTrue,
      );
      expect(await user.addCustomCopyLoginHost('copy6000.com:8443'), isTrue);
      expect(user.customCopyLoginHosts, [
        'https://Copy5000.COM',
        'copy6000.com:8443',
      ]);
      expect(user.copyLoginHostChoices, [
        ...copyLoginHostOptions,
        'https://Copy5000.COM',
        'copy6000.com:8443',
      ]);

      await user.init();
      expect(user.customCopyLoginHosts, [
        'https://Copy5000.COM',
        'copy6000.com:8443',
      ]);
    });

    test('空输入返回 false 且不入列表', () async {
      expect(await user.addCustomCopyLoginHost(''), isFalse);
      expect(await user.addCustomCopyLoginHost('   '), isFalse);
      expect(user.customCopyLoginHosts, isEmpty);
    });

    test('与内置或已有自定义域名重复返回 false', () async {
      expect(await user.addCustomCopyLoginHost('copy3000.com'), isFalse);
      expect(await user.addCustomCopyLoginHost('copy4000.com'), isFalse);
      expect(await user.addCustomCopyLoginHost('copy5000.com'), isTrue);
      expect(await user.addCustomCopyLoginHost('copy5000.com'), isFalse);
      expect(user.customCopyLoginHosts, ['copy5000.com']);
    });
  });

  group('removeCustomCopyLoginHost', () {
    test('删除指定域名并持久化', () async {
      await user.addCustomCopyLoginHost('copy5000.com');
      await user.addCustomCopyLoginHost('copy6000.com');

      await user.removeCustomCopyLoginHost('copy5000.com');
      expect(user.customCopyLoginHosts, ['copy6000.com']);

      await user.init();
      expect(user.customCopyLoginHosts, ['copy6000.com']);
    });

    test('删除当前启用的域名时回落到内置默认', () async {
      await user.addCustomCopyLoginHost('copy5000.com');
      await user.setCopyLoginHost('copy5000.com');

      await user.removeCustomCopyLoginHost('copy5000.com');
      expect(user.copyLoginHost, defaultCopyLoginHost);

      await user.init();
      expect(user.copyLoginHost, defaultCopyLoginHost);
      expect(user.customCopyLoginHosts, isEmpty);
    });
  });

  group('updateCustomCopyLoginHost', () {
    test('重命名并持久化；旧值为当前域名时同步切换', () async {
      await user.addCustomCopyLoginHost('copy5000.com');
      await user.setCopyLoginHost('copy5000.com');

      expect(
        await user.updateCustomCopyLoginHost('copy5000.com', ' copy6000.com '),
        isTrue,
      );
      expect(user.customCopyLoginHosts, ['copy6000.com']);
      expect(user.copyLoginHost, 'copy6000.com');

      await user.init();
      expect(user.customCopyLoginHosts, ['copy6000.com']);
      expect(user.copyLoginHost, 'copy6000.com');
    });

    test('新值为空或重复返回 false 且保持原状', () async {
      await user.addCustomCopyLoginHost('copy5000.com');
      await user.addCustomCopyLoginHost('copy6000.com');

      expect(
        await user.updateCustomCopyLoginHost('copy5000.com', '  '),
        isFalse,
      );
      expect(
        await user.updateCustomCopyLoginHost('copy5000.com', 'copy6000.com'),
        isFalse,
      );
      expect(
        await user.updateCustomCopyLoginHost('copy5000.com', 'copy3000.com'),
        isFalse,
      );
      expect(user.customCopyLoginHosts, ['copy5000.com', 'copy6000.com']);
      expect(user.copyLoginHost, defaultCopyLoginHost);
    });
  });

  group('init 清洗与迁移', () {
    test('持久化数据仅做去空白与去重，不做合法性过滤', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('copy_login_custom_hosts', [
        'copy5000.com',
        ' copy5000.com ', // 去空白后重复
        'copy3000.com', // 与内置重复
        'not a domain', // 不校验，原样保留
      ]);
      await user.init();

      expect(user.customCopyLoginHosts, ['copy5000.com', 'not a domain']);
    });

    test('曾被选中的旧内置域名并入自定义列表，保持可切换', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('copy_login_host', 'www.mangacopy.com');
      await user.init();

      expect(user.copyLoginHost, 'www.mangacopy.com');
      expect(user.customCopyLoginHosts, contains('www.mangacopy.com'));
      expect(user.copyLoginHostChoices, contains('www.mangacopy.com'));

      // 删除后回落默认，且重启不再复活。
      await user.removeCustomCopyLoginHost('www.mangacopy.com');
      expect(user.copyLoginHost, defaultCopyLoginHost);
      await user.init();
      expect(user.customCopyLoginHosts, isEmpty);
      expect(user.copyLoginHost, defaultCopyLoginHost);
    });
  });

  group('setCopyLoginHost', () {
    test('原样保存任意输入，仅空值回落默认', () async {
      await user.setCopyLoginHost(' My.Host:8443 ');
      expect(user.copyLoginHost, 'My.Host:8443');

      await user.setCopyLoginHost('   ');
      expect(user.copyLoginHost, defaultCopyLoginHost);
    });
  });
}
