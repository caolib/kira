import 'dart:ui' show Locale;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/utils/download_foreground_controller.dart';
import 'package:kira/utils/download_manager.dart';

class _RecordingGateway implements DownloadForegroundGateway {
  _RecordingGateway({this.running = false});

  bool running;
  final List<({String title, String text, String channelName})> starts = [];
  final List<({String title, String text})> updates = [];
  final List<void> stops = [];
  int permissionRequests = 0;

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<void> ensureNotificationPermission() async {
    permissionRequests++;
  }

  @override
  Future<void> start({
    required String title,
    required String text,
    required String channelName,
  }) async {
    starts.add((title: title, text: text, channelName: channelName));
    running = true;
  }

  @override
  Future<void> update({required String title, required String text}) async {
    updates.add((title: title, text: text));
  }

  @override
  Future<void> stop() async {
    stops.add(null);
    running = false;
  }
}

ComicDownloadTaskInfo _task({
  ComicDownloadTaskStatus status = ComicDownloadTaskStatus.pending,
  int? done,
  int? total,
}) {
  return ComicDownloadTaskInfo(
    pathWord: 'p',
    chapterUuid: 'c',
    chapterName: 'n',
    comicName: '漫画',
    status: status,
    progress: (done != null && total != null)
        ? ChapterDownloadProgress(completed: done, total: total)
        : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('serviceShouldRun', () {
    test('空队列不启动', () {
      expect(DownloadForegroundController.serviceShouldRun([]), isFalse);
    });

    test('仅暂停任务不启动', () {
      expect(
        DownloadForegroundController.serviceShouldRun([
          _task(status: ComicDownloadTaskStatus.paused),
        ]),
        isFalse,
      );
    });

    test('存在等待任务启动', () {
      expect(DownloadForegroundController.serviceShouldRun([_task()]), isTrue);
    });

    test('存在下载中任务启动', () {
      expect(
        DownloadForegroundController.serviceShouldRun([
          _task(status: ComicDownloadTaskStatus.downloading),
        ]),
        isTrue,
      );
    });

    test('暂停与等待混合时启动', () {
      expect(
        DownloadForegroundController.serviceShouldRun([
          _task(status: ComicDownloadTaskStatus.paused),
          _task(),
        ]),
        isTrue,
      );
    });
  });

  group('composeText', () {
    final l10n = lookupAppLocalizations(const Locale('zh'));

    test('聚合在飞章节数与图片进度', () {
      final text = DownloadForegroundController.composeText(l10n, [
        _task(status: ComicDownloadTaskStatus.downloading, done: 5, total: 10),
        _task(status: ComicDownloadTaskStatus.downloading, done: 3, total: 6),
        _task(),
        _task(status: ComicDownloadTaskStatus.paused),
      ]);
      expect(text, contains('下载中 2 章'));
      expect(text, contains('等待 1 章'));
      expect(text, contains('图片 8/16'));
    });

    test('在飞章节无进度时不附加图片行', () {
      final text = DownloadForegroundController.composeText(l10n, [
        _task(status: ComicDownloadTaskStatus.downloading),
      ]);
      expect(text, contains('下载中 1 章'));
      expect(text, isNot(contains('图片')));
    });

    test('繁体镜像文案', () {
      final hant = lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      final text = DownloadForegroundController.composeText(hant, [
        _task(status: ComicDownloadTaskStatus.downloading, done: 1, total: 4),
      ]);
      expect(text, contains('下載中 1 章'));
      expect(text, contains('圖片 1/4'));
    });
  });

  group('服务状态机', () {
    test('队列有任务则启动服务并请求通知权限', () async {
      final gateway = _RecordingGateway();
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      final tasks = [_task()];
      final controller = DownloadForegroundController(
        listenable: notifier,
        tasks: () => tasks,
        gateway: gateway,
        supported: true,
      );
      controller.attach();
      addTearDown(controller.detach);
      await controller.flush();

      expect(gateway.starts, hasLength(1));
      expect(gateway.permissionRequests, 1);
      expect(gateway.starts.first.title, '正在下载漫画');
      expect(gateway.starts.first.text, contains('等待 1 章'));
      expect(gateway.stops, isEmpty);
    });

    test('队列排空则停止服务', () async {
      final gateway = _RecordingGateway(running: true);
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      var tasks = [_task(status: ComicDownloadTaskStatus.downloading)];
      final controller = DownloadForegroundController(
        listenable: notifier,
        tasks: () => tasks,
        gateway: gateway,
        supported: true,
      );
      controller.attach();
      addTearDown(controller.detach);
      await controller.flush();
      expect(gateway.updates, hasLength(1));

      tasks = [];
      notifier.notifyListeners();
      await controller.flush();

      expect(gateway.stops, hasLength(1));
    });

    test('全部暂停则停止服务', () async {
      final gateway = _RecordingGateway(running: true);
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      var tasks = [_task(status: ComicDownloadTaskStatus.downloading)];
      final controller = DownloadForegroundController(
        listenable: notifier,
        tasks: () => tasks,
        gateway: gateway,
        supported: true,
      );
      controller.attach();
      addTearDown(controller.detach);
      await controller.flush();

      tasks = [_task(status: ComicDownloadTaskStatus.paused)];
      notifier.notifyListeners();
      await controller.flush();

      expect(gateway.stops, hasLength(1));
    });

    test('冷启动发现残留服务则清理', () async {
      final gateway = _RecordingGateway(running: true);
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      final controller = DownloadForegroundController(
        listenable: notifier,
        tasks: () => <ComicDownloadTaskInfo>[],
        gateway: gateway,
        supported: true,
      );
      controller.attach();
      addTearDown(controller.detach);
      await controller.flush();

      expect(gateway.stops, hasLength(1));
      expect(gateway.starts, isEmpty);
    });

    test('相邻进度更新被节流合并', () {
      final gateway = _RecordingGateway();
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      var tasks = [
        _task(status: ComicDownloadTaskStatus.downloading, done: 1, total: 10),
      ];

      fakeAsync((async) {
        final controller = DownloadForegroundController(
          listenable: notifier,
          tasks: () => tasks,
          gateway: gateway,
          supported: true,
        );
        addTearDown(controller.detach);
        controller.attach();
        async.flushMicrotasks();
        // 启动路径：服务已 start（含权限请求），尚无 update。
        expect(gateway.starts, hasLength(1));
        expect(gateway.updates, isEmpty);

        tasks = [
          _task(
            status: ComicDownloadTaskStatus.downloading,
            done: 2,
            total: 10,
          ),
        ];
        notifier.notifyListeners();
        async.flushMicrotasks();
        // 启动时刻 _lastUpdateAt 已置为当前假时间，后续更新进入节流窗口。
        expect(gateway.updates, isEmpty);

        async.elapse(const Duration(milliseconds: 800));
        async.flushMicrotasks();
        expect(gateway.updates, hasLength(1));
        expect(gateway.updates.last.text, contains('图片 2/10'));
      });
    });
    test('非 Android 平台为空操作', () async {
      final gateway = _RecordingGateway();
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      final controller = DownloadForegroundController(
        listenable: notifier,
        tasks: () => [_task()],
        gateway: gateway,
        supported: false,
      );
      controller.attach();
      addTearDown(controller.detach);
      await controller.flush();

      expect(gateway.starts, isEmpty);
      expect(gateway.stops, isEmpty);
    });
  });
}
