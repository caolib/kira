import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_codec.dart';
import 'package:kira/backup/backup_controller.dart';
import 'package:kira/backup/webdav_client.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:kira/utils/settings_backup.dart';

import 'fake_webdav_adapter.dart';
import 'webdav_listing_test.dart' show davMultistatus, davResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final config = WebDavConfig(serverUrl: 'https://dav.example/dav/');
  const credentials = WebDavCredentials(username: '', password: '');
  final payload = EncodedBackup(
    bytes: Uint8List.fromList([1, 2]),
    encrypted: true,
  );
  late FakeWebDavAdapter adapter;
  late BackupController controller;
  late int connections;
  setUp(() {
    adapter = FakeWebDavAdapter();
    connections = 0;
    controller = BackupController(
      service: SettingsBackupService(),
      codec: BackupCodec(),
      createClient: ({required config, required credentials}) {
        connections++;
        return WebDavClient(
          config: config,
          credentials: credentials,
          adapter: adapter,
        );
      },
    );
  });
  tearDown(() => controller.dispose());

  String seed(String name) {
    adapter.files[config.fileUri(name).path] = Uint8List(1);
    return name;
  }

  String generated(DateTime date, {String extension = '.json.gz'}) =>
      BackupCodec.uniqueFileName(extension, now: date);
  List<String> remaining() => adapter.files.keys
      .map((path) => Uri.parse(path).pathSegments.last)
      .toList();
  List<String> deletes() => adapter.requests
      .where((r) => r.method == 'DELETE' && !r.uri.path.endsWith('.uploading'))
      .map((r) => r.uri.pathSegments.last)
      .toList();
  Future<WebDavBackupEntry> upload(int limit) =>
      controller.upload(config, credentials, payload, retentionLimit: limit);

  test(
    'no retention request by default; a failed MOVE never prunes existing backups',
    () async {
      final old = seed(generated(DateTime.utc(2001)));
      final saved = await controller.upload(config, credentials, payload);
      adapter.moveSupported = false;
      await expectLater(
        upload(1),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.code,
            'code',
            WebDavErrorCode.moveUnsupported,
          ),
        ),
      );
      expect(adapter.requests.where((r) => r.method == 'PROPFIND'), isEmpty);
      expect(deletes(), isEmpty);
      expect(remaining(), unorderedEquals([old, saved.name]));
    },
  );

  test(
    'retention uses the embedded UTC time, not HTTP dates, and counts only confirmed generated files',
    () async {
      final oldest = seed(generated(DateTime.utc(2001, 2, 3, 4, 5, 6, 123)));
      final next = seed(
        generated(
          DateTime.utc(2001, 2, 3, 4, 5, 6, 123, 1),
          extension: '.kirabak',
        ),
      );
      final newest = seed(generated(DateTime.utc(2002)));
      final directory = generated(DateTime.utc(2098));
      final unknown = generated(DateTime.utc(2099));
      final ignored = [
        seed('notes.json'),
        seed('my.kirabak'),
        seed('renamed.json.gz'),
        seed(oldest.replaceAll('.json.gz', '.json')),
        seed('.$oldest.uploading'),
        seed(oldest.replaceFirst('20010203', '20010231')),
        seed(oldest.replaceFirst('123Z', '123000Z')),
        seed(oldest.replaceFirst(RegExp(r'Z-[a-f0-9]{24}'), 'Z-abcd')),
        seed(oldest.toUpperCase()),
      ];
      // Deliberately stale listing omits the newly committed file. Metadata order
      // is the reverse of the embedded timestamps.
      adapter.listingOverride = davMultistatus([
        davResponse(oldest).replaceFirst('2026', '2040'),
        davResponse(next),
        davResponse(newest).replaceFirst('2026', '2010'),
        davResponse(directory, collection: true),
        davResponse(
          unknown,
        ).replaceFirst('<d:resourcetype></d:resourcetype>', ''),
        ...ignored.map((name) => davResponse(name)),
      ]);
      final saved = await upload(2);
      expect(deletes(), [oldest, next]);
      expect(remaining(), unorderedEquals([newest, saved.name, ...ignored]));
      expect(adapter.requests.where((r) => r.method == 'GET'), isEmpty);
      expect(connections, 1);
    },
  );

  test(
    'clock rollback protects exactly this upload and the other device’s newer backup',
    () async {
      final old = seed(generated(DateTime.utc(2001)));
      final future = seed(generated(DateTime.utc(9999)));
      // Create a distinct sibling with the same embedded time as today's upload.
      String? sibling;
      adapter.beforeResponse = (r) async {
        if (r.method == 'MOVE') {
          final target = Uri.parse(
            r.headers['Destination'].toString(),
          ).pathSegments.last;
          final other = target.replaceFirst('.kirabak', '.json.gz');
          sibling = seed(other);
        }
      };
      final saved = await upload(1);
      expect(deletes(), [old, sibling]);
      expect(remaining(), unorderedEquals([future, saved.name]));
    },
  );

  test(
    'listing failure carries committed entry, original reason and throwing stack',
    () async {
      adapter.responseOverride = (r) =>
          r.method == 'PROPFIND' ? ResponseBody.fromString('', 403) : null;
      await expectLater(
        upload(1),
        throwsA(
          isA<BackupRetentionException>()
              .having(
                (e) => e.error,
                'error',
                isA<WebDavException>().having((e) => e.status, 'status', 403),
              )
              .having(
                (e) => e.stackTrace.toString(),
                'original stack',
                contains('WebDavClient._request'),
              )
              .having(
                (e) => e.entry.name,
                'committed',
                predicate<String>((name) => remaining().single == name),
              ),
        ),
      );
      expect(deletes(), isEmpty);
      expect(controller.busy, isFalse);
    },
  );

  test(
    'partial retention delete does not undo the upload or continue deleting',
    () async {
      final old = seed(generated(DateTime.utc(2001)));
      final denied = seed(generated(DateTime.utc(2002)));
      final next = seed(generated(DateTime.utc(2003)));
      adapter.responseOverride = (r) =>
          r.method == 'DELETE' && r.uri.pathSegments.last == denied
          ? ResponseBody.fromString('', 423)
          : null;
      await expectLater(
        upload(1),
        throwsA(
          isA<BackupRetentionException>()
              .having(
                (e) => e.error,
                'error',
                isA<WebDavException>().having((e) => e.status, 'status', 423),
              )
              .having(
                (e) => remaining().contains(e.entry.name),
                'new file exists',
                isTrue,
              ),
        ),
      );
      expect(deletes(), [old, denied]);
      expect(remaining(), containsAll([next, denied]));
    },
  );

  test(
    'cancel during listing or at the final _run check retains upload success',
    () async {
      for (final atClose in [false, true]) {
        adapter.beforeResponse = (r) async {
          if (!atClose && r.method == 'PROPFIND') controller.cancel();
        };
        adapter.onClose = atClose ? controller.cancel : null;
        await expectLater(
          upload(5),
          throwsA(
            isA<BackupRetentionException>()
                .having(
                  (e) => e.error,
                  'error',
                  isA<SettingsBackupException>().having(
                    (e) => e.code,
                    'code',
                    SettingsBackupErrorCode.cancelled,
                  ),
                )
                .having(
                  (e) => remaining().contains(e.entry.name),
                  'new file exists',
                  isTrue,
                ),
          ),
        );
        expect(controller.operation, BackupOperation.idle);
      }
      expect(deletes(), isEmpty);
    },
  );

  test(
    'batch uses one client/token, reports each completed delete, stops on failure or cancellation',
    () async {
      final entries = [
        for (final name in ['one.json', 'two.json', 'three.json'])
          WebDavBackupEntry(name: seed(name)),
      ];
      final done = <WebDavBackupEntry>[];
      adapter.responseOverride = (r) =>
          r.method == 'DELETE' && r.uri.pathSegments.last == 'two.json'
          ? ResponseBody.fromString('', 403)
          : null;
      await expectLater(
        controller.deleteMany(
          config,
          credentials,
          entries,
          onDeleted: done.add,
        ),
        throwsA(isA<WebDavException>().having((e) => e.status, 'status', 403)),
      );
      expect(done, [entries[0]]);
      expect(deletes(), ['one.json', 'two.json']);
      expect(adapter.requests.map((r) => r.cancelToken).toSet(), hasLength(1));
      expect(connections, 1);

      adapter.requests.clear();
      adapter.responseOverride = null;
      await expectLater(
        controller.deleteMany(
          config,
          credentials,
          entries.sublist(1),
          onDeleted: (e) {
            done.add(e);
            controller.cancel();
          },
        ),
        throwsA(
          isA<SettingsBackupException>().having(
            (e) => e.code,
            'code',
            SettingsBackupErrorCode.cancelled,
          ),
        ),
      );
      expect(done, entries.sublist(0, 2));
      expect(deletes(), ['two.json']);
      expect(remaining(), ['three.json']);
      expect(controller.operation, BackupOperation.idle);
    },
  );
}
