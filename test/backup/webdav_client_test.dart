import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_codec.dart';
import 'package:kira/backup/backup_error.dart';
import 'package:kira/backup/webdav_client.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_webdav_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final config = WebDavConfig(
    serverUrl: 'https://dav.example/dav/',
    directory: '漫画/备份/',
  );
  const credentials = WebDavCredentials(
    username: '用户',
    password: ' dav-secret ',
  );
  late FakeWebDavAdapter adapter;
  late WebDavClient client;
  EncodedBackup payload() =>
      EncodedBackup(bytes: Uint8List.fromList([1, 2, 3]), encrypted: true);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    adapter = FakeWebDavAdapter();
    client = WebDavClient(
      config: config,
      credentials: credentials,
      adapter: adapter,
    );
  });
  tearDown(() => client.close());

  test(
    'connection test exercises MKCOL, PROPFIND, PUT, GET, MOVE and DELETE',
    () async {
      await client.testConnection(cancel: CancelToken());
      expect(
        adapter.requests.map((r) => r.method).toSet(),
        containsAll(['MKCOL', 'PROPFIND', 'PUT', 'GET', 'MOVE', 'DELETE']),
      );
      expect(adapter.files, isEmpty);
    },
  );

  test('atomic upload, list, download and delete roundtrip', () async {
    final first = await client.upload(payload(), cancel: CancelToken());
    final second = await client.upload(payload(), cancel: CancelToken());
    expect(first.name, isNot(second.name));
    expect(first.name, endsWith('.kirabak'));
    expect(first.name, contains('Z-'));
    expect(adapter.files.length, 2);
    final put = adapter.requests.firstWhere((r) => r.method == 'PUT');
    expect(put.uri.path, endsWith('.uploading'));
    expect(put.headers['If-None-Match'], '*');
    final move = adapter.requests.firstWhere((r) => r.method == 'MOVE');
    expect(move.headers['Overwrite'], 'F');
    final destination = move.headers['Destination'];
    expect(destination, isA<String>());
    expect(destination.toString(), startsWith(config.root.toString()));
    final files = await client.list(cancel: CancelToken());
    expect(
      files.map((e) => e.name),
      unorderedEquals([first.name, second.name]),
    );
    expect(await client.download(first, cancel: CancelToken()), [1, 2, 3]);
    await client.delete(first, cancel: CancelToken());
    expect(adapter.files.length, 1);
    expect(adapter.files.containsKey(config.fileUri(second.name).path), isTrue);
  });

  test(
    'independent transport does not send business tokens or cookies, redirects disabled',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_token', 'manga-token-must-not-leak');
      await client.list(cancel: CancelToken());
      final request = adapter.requests.single;
      expect(request.followRedirects, isFalse);
      expect(request.maxRedirects, 0);
      expect(
        request.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('用户: dav-secret '))}',
      );
      expect(
        request.headers.keys.map((s) => s.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(
        request.headers.toString(),
        isNot(contains('manga-token-must-not-leak')),
      );
    },
  );

  test(
    'authentication failures and read-only directories are explicit',
    () async {
      adapter.forcedStatus = 401;
      await expectLater(
        client.list(cancel: CancelToken()),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.code,
            'code',
            WebDavErrorCode.authentication,
          ),
        ),
      );
      adapter.forcedStatus = null;
      adapter.writable = false;
      await expectLater(
        client.upload(payload(), cancel: CancelToken()),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.code,
            'code',
            WebDavErrorCode.forbidden,
          ),
        ),
      );
    },
  );

  test(
    'unsupported MOVE never leaves a visible completed backup and cleans temp',
    () async {
      adapter.moveSupported = false;
      await expectLater(
        client.upload(payload(), cancel: CancelToken()),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.code,
            'code',
            WebDavErrorCode.moveUnsupported,
          ),
        ),
      );
      expect(adapter.files, isEmpty);
      expect(adapter.requests.last.method, 'DELETE');
    },
  );

  test('server redirects are refused without forwarding credentials', () async {
    adapter.forcedStatus = 302;
    await expectLater(
      client.list(cancel: CancelToken()),
      throwsA(
        isA<WebDavException>().having(
          (e) => e.code,
          'code',
          WebDavErrorCode.redirectRefused,
        ),
      ),
    );
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.host, 'dav.example');
  });

  test('timeouts and pre-cancelled requests are reported safely', () async {
    adapter.timeout = true;
    await expectLater(
      client.list(cancel: CancelToken()),
      throwsA(
        isA<WebDavException>().having(
          (e) => e.code,
          'code',
          WebDavErrorCode.timeout,
        ),
      ),
    );
    adapter.requests.clear();
    final cancelled = CancelToken()..cancel();
    await expectLater(
      client.list(cancel: cancelled),
      throwsA(
        isA<SettingsBackupException>().having(
          (e) => e.code,
          'code',
          SettingsBackupErrorCode.cancelled,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    'cancellation after PUT uses a fresh token to clean up the temporary file',
    () async {
      final cancel = CancelToken();
      adapter.beforeResponse = (request) async {
        if (request.method == 'MOVE') cancel.cancel();
      };
      await expectLater(
        client.upload(payload(), cancel: cancel),
        throwsA(isA<SettingsBackupException>()),
      );
      expect(adapter.requests.last.method, 'DELETE');
      expect(adapter.requests.last.cancelToken?.isCancelled, isFalse);
    },
  );

  test(
    'download bounds actual stream and declared length; unsafe names never reach transport',
    () async {
      for (final name in [
        '../other.json',
        '/outside.json',
        'sub/file.json',
        'x%2fsecret.json',
      ]) {
        await expectLater(
          client.delete(WebDavBackupEntry(name: name), cancel: CancelToken()),
          throwsA(isA<WebDavException>()),
        );
      }
      expect(adapter.requests, isEmpty);
      adapter.responseOverride = (_) => ResponseBody.fromBytes(
        [],
        200,
        headers: {
          'content-length': ['${BackupCodec.maxFileBytes + 1}'],
        },
      );
      await expectLater(
        client.download(
          const WebDavBackupEntry(name: 'large.json'),
          cancel: CancelToken(),
        ),
        throwsA(isA<SettingsBackupException>()),
      );
      adapter.responseOverride = (_) => ResponseBody(
        Stream.fromIterable(List.generate(17, (_) => Uint8List(1024 * 1024))),
        200,
      );
      await expectLater(
        client.download(
          const WebDavBackupEntry(name: 'large.json'),
          cancel: CancelToken(),
        ),
        throwsA(
          isA<SettingsBackupException>().having(
            (e) => e.code,
            'code',
            SettingsBackupErrorCode.tooLarge,
          ),
        ),
      );
    },
  );
}
