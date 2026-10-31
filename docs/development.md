# 开发指南

## 环境

- Flutter：版本见 [`.flutter-version`](../.flutter-version)，自带 Dart SDK
- Java 17

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

移动端首次调试或执行 `flutter clean` 后，先构建一次：

```sh
flutter build apk --debug
```

启动应用：

```sh
flutter run -d <设备ID>
```

## 发布

在 Claude Code 中使用项目 [`/release` skill](../.claude/skills/release/SKILL.md)，先确认版本与渠道、审查更新日志，再批准发布。
