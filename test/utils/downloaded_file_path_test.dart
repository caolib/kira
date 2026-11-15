import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/downloaded_file_path.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory container;
  late Directory root;
  late Directory chapter;

  setUp(() async {
    container = await Directory.systemTemp.createTemp('kira_container_move_');
    root = Directory(p.join(container.path, 'Documents', 'comic_downloads'));
    chapter = Directory(p.join(root.path, 'book', 'chapter'));
    await chapter.create(recursive: true);
    await File(p.join(chapter.path, '000.jpg')).writeAsBytes([1, 2, 3]);
  });
  tearDown(() => container.delete(recursive: true));

  String? resolve(String path, {bool ios = true}) => DownloadedFilePath.resolve(
    path,
    rootPath: root.path,
    directoryPath: chapter.path,
    relocateIOSContainer: ios,
  );

  test('same-directory paths remain unchanged on all platforms', () {
    final path = p.join(chapter.path, '000.jpg');
    expect(resolve(path, ios: false), path);
    expect(resolve('000.jpg', ios: false), path);
  });

  test('old iOS application container maps only its complete owned suffix', () {
    const old =
        '/var/mobile/Containers/Data/Application/OLD/Documents/comic_downloads/book/chapter/000.jpg';
    expect(resolve(old), p.join(chapter.path, '000.jpg'));
    expect(resolve(old, ios: false), isNull);
  });

  test('relocation cannot use another book or chapter by matching filename', () {
    const prefix =
        '/var/mobile/Containers/Data/Application/OLD/Documents/comic_downloads';
    expect(resolve('$prefix/other/chapter/000.jpg'), isNull);
    expect(resolve('$prefix/book/other/000.jpg'), isNull);
    expect(resolve('$prefix/book/chapter/missing.jpg'), isNull);
  });

  test('URLs, arbitrary external paths and traversal are never relocated', () {
    expect(resolve('https://example.com/000.jpg'), isNull);
    expect(
      resolve('/external/Documents/comic_downloads/book/chapter/000.jpg'),
      isNull,
    );
    expect(resolve('../000.jpg'), isNull);
    expect(resolve('${chapter.path}/../chapter/000.jpg'), isNull);
    expect(resolve(''), isNull);
  });
}
