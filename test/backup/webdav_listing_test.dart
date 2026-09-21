import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:kira/backup/webdav_listing.dart';

String davResponse(
  String href, {
  String status = 'HTTP/1.1 200 OK',
  bool collection = false,
  String size = '1024',
}) =>
    '''
<d:response><d:href>$href</d:href><d:propstat>
<d:prop><d:resourcetype>${collection ? '<d:collection/>' : ''}</d:resourcetype>
<d:getcontentlength>$size</d:getcontentlength>
<d:getlastmodified>Mon, 14 Sep 2026 08:00:00 GMT</d:getlastmodified></d:prop>
<d:status>$status</d:status></d:propstat></d:response>''';

String davMultistatus(Iterable<String> responses) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<d:multistatus xmlns:d="DAV:">${responses.join()}</d:multistatus>';

void main() {
  final config = WebDavConfig(
    serverUrl: 'https://dav.example/dav/',
    directory: '漫画/备份/',
  );

  test('UTF-8/encoded hrefs, namespace and 207 propstat status are parsed', () {
    final xml = davMultistatus([
      davResponse(config.root.toString(), collection: true),
      davResponse(config.fileUri('阅读记录.kirabak').toString()),
      davResponse('${config.root.path}旧设置.json'),
      davResponse('relative.json.gz'),
      davResponse('gone.kirabak', status: 'HTTP/1.1 404 Not Found'),
      davResponse('directory.json', collection: true),
      davResponse('bad-size.json', size: '-1'),
      davResponse('not-a-backup.tmp'),
    ]);
    final entries = parseWebDavListing(xml, config);
    expect(
      entries.map((e) => e.name),
      unorderedEquals(['阅读记录.kirabak', '旧设置.json', 'relative.json.gz']),
    );
    expect(entries.first.size, 1024);
    expect(entries.first.modified, DateTime.utc(2026, 9, 14, 8));
    expect(webDavCollectionExists(xml, config.root, config), isTrue);
  });

  test('malicious hrefs cannot escape the exact origin and directory', () {
    final root = config.root.toString();
    final entries = parseWebDavListing(
      davMultistatus([
        davResponse('https://evil.example/dav/漫画/备份/stolen.json'),
        davResponse('https://dav.example:444/dav/漫画/备份/stolen.json'),
        davResponse('http://dav.example/dav/漫画/备份/stolen.json'),
        davResponse('https://user:password@dav.example/dav/漫画/备份/stolen.json'),
        davResponse('/outside.json'),
        davResponse('../outside.json'),
        davResponse('${root}sub/nested.json'),
        davResponse('$root%2e%2e/outside.json'),
        davResponse('$root%252e%252e%252fsecret.json'),
        davResponse('${root}embedded%2fpath.json'),
        davResponse('${root}embedded%5cpath.json'),
        davResponse('${root}backup.json?token=leak'),
        davResponse('${root}backup.json#fragment'),
        davResponse('${root}good.json'),
      ]),
      config,
    );
    expect(entries.map((e) => e.name), ['good.json']);
  });

  test('rejects entity declarations, wrong roots and malformed XML', () {
    for (final xml in [
      '<!DOCTYPE d [<!ENTITY x SYSTEM "file:///private">]><d/>',
      '<html>login required</html>',
      '<multistatus xmlns="not-DAV:"/>',
      '<d:multistatus xmlns:d="DAV:">',
    ]) {
      expect(
        () => parseWebDavListing(xml, config),
        throwsA(isA<WebDavException>()),
      );
    }
  });

  test(
    'URL defaults HTTPS and plaintext HTTP requires explicit acceptance',
    () {
      expect(WebDavConfig(serverUrl: 'example.com/dav').server.scheme, 'https');
      expect(
        () => WebDavConfig(serverUrl: 'http://example.com/dav'),
        throwsA(isA<WebDavException>()),
      );
      expect(
        WebDavConfig(
          serverUrl: 'http://example.com/dav',
          allowHttp: true,
        ).allowHttp,
        isTrue,
      );
      for (final url in [
        'https://user:pass@example.com/dav',
        'https://example.com/dav?token=secret',
        'file:///tmp',
        '',
      ]) {
        expect(
          () => WebDavConfig(serverUrl: url),
          throwsA(isA<WebDavException>()),
        );
      }
      for (final directory in [
        '../backups',
        'root/../backup',
        r'root\backup',
        'root/%2e%2e',
        'root/%252fsecret',
      ]) {
        expect(
          () => WebDavConfig(
            serverUrl: 'https://example.com',
            directory: directory,
          ),
          throwsA(isA<WebDavException>()),
        );
      }
    },
  );

  test('an empty directory stores backups in the server root', () {
    for (final directory in ['', '  ', '/']) {
      final rootConfig = WebDavConfig(
        serverUrl: 'https://example.com/dav/',
        directory: directory,
      );
      expect(rootConfig.directory, '');
      expect(rootConfig.directorySegments, isEmpty);
      expect(rootConfig.root.toString(), 'https://example.com/dav/');
      expect(
        rootConfig.fileUri('阅读记录.kirabak').toString(),
        'https://example.com/dav/${Uri.encodeComponent('阅读记录.kirabak')}',
      );
    }
    final rootConfig = WebDavConfig(serverUrl: 'https://example.com/dav/');
    final entries = parseWebDavListing(
      davMultistatus([
        davResponse(rootConfig.root.toString(), collection: true),
        davResponse('${rootConfig.root}good.json'),
        davResponse('${rootConfig.root}sub/nested.json'),
      ]),
      rootConfig,
    );
    expect(entries.map((e) => e.name), ['good.json']);
  });
}
