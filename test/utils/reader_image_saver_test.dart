import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';
import 'package:kira/utils/reader_image_saver.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../test_helpers.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');
  final calls = <MethodCall>[];
  late PathProviderPlatform originalPaths;
  late Directory directory;
  bool granted = true;
  bool requestGranted = true;
  Object? saveError;
  String? temporaryImage;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    granted = true;
    requestGranted = true;
    saveError = null;
    temporaryImage = null;
    directory = await Directory.systemTemp.createTemp('kira_image_saver_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'hasAccess') return granted;
          if (call.method == 'requestAccess') return requestGranted;
          if (call.method == 'putImage') {
            final args = call.arguments as Map<Object?, Object?>;
            temporaryImage = args['path']! as String;
            expect(File(temporaryImage!).existsSync(), isTrue);
          }
          if (saveError case final error?) throw error;
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PathProviderPlatform.instance = originalPaths;
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
    teardownSecureCredentialStoreForTest();
  });

  Uint8List png() =>
      Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  Uint8List webpHeader() => Uint8List.fromList([
    0x52,
    0x49,
    0x46,
    0x46,
    0,
    0,
    0,
    0,
    0x57,
    0x45,
    0x42,
    0x50,
  ]);

  test(
    'iOS requests add-only access and does not ask again when granted',
    () async {
      expect(await ReaderImageSaver.requestAccess(), isTrue);
      expect(calls.single.method, 'hasAccess');
      expect(calls.single.arguments, {'toAlbum': false});
    },
  );

  test('iOS permission denial is returned without saving', () async {
    granted = false;
    requestGranted = false;
    expect(await ReaderImageSaver.requestAccess(), isFalse);
    expect(calls.map((call) => call.method), ['hasAccess', 'requestAccess']);
    expect(calls.last.arguments, {'toAlbum': false});
  });

  test('iOS PNG saves bytes without creating a named album', () async {
    await ReaderImageSaver.save(png());
    expect(calls.map((call) => call.method), [
      'requestAccess',
      'putImageBytes',
    ]);
    final args = calls.last.arguments as Map<Object?, Object?>;
    expect(args['album'], isNull);
    expect(args['name'], 'kira.png');
    expect(args['bytes'], png());
  });

  test('native save failure retains its platform error', () async {
    saveError = PlatformException(
      code: 'UNEXPECTED',
      message: 'PhotoKit write failed',
    );
    await expectLater(
      ReaderImageSaver.save(png()),
      throwsA(
        isA<GalException>().having(
          (error) => error.platformException.message,
          'native reason',
          'PhotoKit write failed',
        ),
      ),
    );
  });

  test(
    'valid iOS WebP is decoded into PNG bytes before native saving',
    () async {
      final webp = base64Decode(
        'UklGRh4AAABXRUJQVlA4TBEAAAAvAUAAAAdQ1XpUq/+BiOh/AAA=',
      );
      await ReaderImageSaver.save(webp);
      expect(calls.map((call) => call.method), [
        'requestAccess',
        'putImageBytes',
      ]);
      final arguments = calls.last.arguments;
      if (arguments is! Map<Object?, Object?>) fail('Missing image arguments');
      final bytes = arguments['bytes'];
      if (bytes is! Uint8List) fail('Missing converted image bytes');
      expect(arguments['album'], isNull);
      expect(arguments['name'], 'kira.png');
      expect(ReaderImageSaver.imageExtension(bytes), '.png');
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 2);
          expect(frame.image.height, 2);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      expect(directory.listSync(), isEmpty);
    },
  );

  test(
    'invalid iOS WebP never reaches the force-unwrapping native file API',
    () async {
      await expectLater(ReaderImageSaver.save(webpHeader()), throwsA(anything));
      expect(calls, isEmpty);
    },
  );

  test('Android preserves album permission and WebP file workaround', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await ReaderImageSaver.requestAccess(), isTrue);
    expect(calls.single.arguments, {'toAlbum': true});
    calls.clear();
    await ReaderImageSaver.save(webpHeader());
    expect(calls.map((call) => call.method), ['requestAccess', 'putImage']);
    expect((calls.last.arguments as Map<Object?, Object?>)['album'], 'kira');
    expect(temporaryImage, isNotNull);
    expect(File(temporaryImage!).existsSync(), isFalse);
    expect(directory.listSync(), isEmpty);
  });

  test('Android temporary files are removed even after a save error', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    saveError = PlatformException(code: 'UNEXPECTED', message: 'Disk full');
    await expectLater(
      ReaderImageSaver.save(webpHeader()),
      throwsA(isA<GalException>()),
    );
    expect(directory.listSync(), isEmpty);
  });
}
