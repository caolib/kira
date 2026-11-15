# 开发指南

## 环境

- Flutter：版本见 [`.flutter-version`](../.flutter-version)，自带 Dart SDK
- Java 17（Android）
- iOS：macOS、Xcode 与 CocoaPods；最低系统和构建配置见 [平台构建](platform-build.md#ios)。Windows 无法进行 iOS 原生构建。

## 获取代码

```sh
git clone https://github.com/caolib/kira.git
cd kira
```

## 安装依赖

```sh
flutter pub get --enforce-lockfile
```

依赖固定从 pub.dev 下载，不要设置 `PUB_HOSTED_URL`。不要直接运行 `flutter pub get`，它会重新解析依赖并改写 `pubspec.lock`。

## 调试运行

Android 首次调试或执行 `flutter clean` 后，先构建一次：

```sh
flutter build apk --debug
```

启动应用：

```sh
flutter run -d <设备ID>
```

## iOS 构建

在 GitHub Actions 手动运行 `build-ios.yml`。默认执行全量 Flutter 测试及 iOS 模拟器烟测；仅主动勾选 `skip_tests` 才跳过 Flutter 测试，静态分析和原生构建校验始终执行。

未签名 IPA 与 SHA-256 上传到固定 `ios-build` 预发布，安装前须自行重签。工具链、CocoaPods 原生锁、功能边界与真机验收见 [平台构建](platform-build.md#ios)。这条工作流独立于正式发布，不生成 `release.json`。

## 发布

在 Claude Code 中使用项目 [`/release` skill](../.claude/skills/release/SKILL.md)，先确认版本与渠道、审查更新日志，再批准发布。

正式版 Actions 自动生成 [`release.json` 发布清单](release-manifest.md)，提供全部安装包的下载链接与发布元信息。
