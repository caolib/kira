# Platform Build Notes

Windows / Android / iOS 构建配置、故障排查与验收边界。`CLAUDE.md` 只保留指针与硬性禁令；构建或平台配置变更前先读本文。

## Windows

`windows/CMakeLists.txt` passes `/utf-8` to MSVC and silences the STL1011 experimental-coroutine assertion. Do not remove either: on non-UTF-8 system locales (Chinese code page 936) MSVC reads sources using the system code page, so UTF-8 bytes in third-party plugin sources raise C4819 — which `APPLY_STANDARD_SETTINGS`' `/WX` promotes to a hard error (`connectivity_plus` fails this way); STL1011 comes from `flutter_inappwebview_windows` and `permission_handler_windows` still using `<experimental/coroutine>` under MSVC 14.51+.

If `ephemeral/cpp_client_wrapper/*.cc` are reported missing (C1083), the Windows engine artifacts extracted incompletely: run `flutter clean` then `flutter precache --windows`.

Do not add media/video dependencies for Windows debugging: the player stack is gone, `pubspec.lock` has no `media_kit` entry, and nothing in `lib/` references it. A residual `C1041` PDB-lock error after `rm -rf build/windows/x64` is a transient MSVC parallel-compile race — just retry the build.

## Android

`scripts/build_apk.ps1` 与 `scripts/common.ps1` 的 JVM 枚举/清理仅用于非 CI 的 Windows 宿主；Ubuntu Actions 不可调用 Windows 专用 `Get-CimInstance`。正式版标签不可变：`.github/workflows/release.yml` 手动续发时仍检出目标标签的应用代码、版本和日志，仅从 `github.workflow_sha` 覆盖这两个构建脚本，并在任务摘要记录两份源码 SHA；标签推送构建不覆盖脚本。

`scripts/*.ps1` are UTF-8 **without BOM** and contain Chinese text. Windows PowerShell 5.1 (`powershell.exe`) parses them with the system ANSI codepage (GBK on zh-CN), producing mojibake and parser errors like `TerminatorExpectedAtEndOfString`. Run them with **PowerShell 7** (`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/build_apk.ps1`), which defaults to UTF-8. Adding a UTF-8 BOM to the scripts would fix 5.1 too.

After `flutter clean`, `flutter run -d <android>` fails with `package identifier or launch activity not found`. **Run `flutter build apk --debug` once first**, then `flutter run` works again.

Why: the launcher entry lives in `<activity-alias>` (`LauncherDefault` / `LauncherAlt1`, required by the switchable-logo feature) and `MainActivity` itself carries no LAUNCHER intent-filter. When a built APK exists Flutter reads it via `aapt dump badging`, which resolves aliases correctly; with no APK it falls back to parsing the source manifest, and `flutter_tools/lib/src/android/application_package.dart` only iterates `<activity>` — it does not recognise `<activity-alias>`.

Do **not** "fix" this by giving `MainActivity` a LAUNCHER intent-filter: that adds a second launcher icon and breaks logo switching. Disabling `MainActivity` is also wrong — an alias whose `targetActivity` is disabled stops working.

## iOS

### 工具链与原生启动

- Flutter 以 `.flutter-version` 为准；独立 Actions 使用 macOS 15 与 Xcode 26.3。Windows 只能跑 Dart/Widget 与脚本测试，不能代替 Xcode 编译或 iPhone 验收。
- 最低 iOS **14.0**，统一于 `ios/Podfile`、Runner/RunnerTests 和 Project 的三种配置。锁定的 `file_picker_darwin` 要求 14，不通过降低插件声明绕过。
- 项目在 `pubspec.yaml` 的 `flutter.config` 关闭 SwiftPM，使用 CocoaPods；Debug/Release/Profile 各自引用对应 Pods xcconfig，再引用 Generated 配置。首次 macOS 构建生成 `ios/Podfile.lock` 并保存为诊断 artifact；将真实生成的锁纳入版本控制后，后续构建按 deployment 模式检查，不在 Windows 伪造锁文件。
- 保留 `ios/Runner/AppDelegate.swift` 的 `FlutterImplicitEngineDelegate` 与 `ios/Runner/SceneDelegate.swift` 的 UIScene 集成，插件在隐式引擎初始化时注册。`flutter_foreground_task` 即使仅 Android 在 Dart 使用，也会注册 iOS 原生插件：其 BGTask 早注册必须在真正 `application(_:didFinishLaunchingWithOptions:)` 返回之前执行；与 plist 的 permitted identifier 和 `fetch` 配置一起维护。这不代表 iOS 支持持续后台下载。
- Bundle ID 为 `io.github.caolib.kira`。主图标与备用图标都需编译入包，发布 PNG 不带 alpha。`app_icon` 通道校验索引、平台切换能力与 UIKit 错误，不手改生成插件注册器。
- `ios/Runner/PrivacyInfo.xcprivacy` 声明应用实际使用的 UserDefaults（CA92.1）与沙盒文件时间戳（C617.1）。照片仅请求 add-only；局域网说明用于本地代理/服务，ATS 仅放行 local networking。清单存在不等于已通过 App Store 隐私审核。

### 独立 Actions 与产物

在 GitHub Actions 手动运行 `.github/workflows/build-ios.yml`：

- `note` 为可选说明；`skip_tests` 默认 **false**。默认跑全量 Flutter 单元/Widget 测试和 iOS 模拟器 `integration_test/ios_startup_test.dart`；勾选后跳过这两类 Flutter 测试，构建说明明确标记跳过。
- 配置/脚本校验、静态分析、真机 Release 构建与 IPA 校验始终执行；任一门禁失败不进入发布。模拟器测试调用实际插件、离线 HTML WebView 与 `lib/main.dart` 的生产共用 `startKira` 初始化流程，断言首帧、并发小说初始化与启动错误日志；为离线验证通过正常偏好关闭自动网络任务，并保留测试绑定的错误处理。它不代替真机验收。
- 真机构建明确使用 `lib/main.dart`。当前 Flutter 的 `flutter build ipa --no-codesign` 只生成 xcarchive，不导出 IPA；`scripts/package_ios.py` 在 macOS 将完整 app 放入 `Payload/Runner.app` 后封包，检查 device iOS arm64、版本、资源和解包结构，并生成 SHA-256。
- 产物名为 `kira-<pubspec完整版本>-ios-unsigned.ipa`，同时保存 Actions artifact。iOS bundle 使用数字短版本和构建号；模拟器测试临时规范化 pubspec 版本后精确恢复，恢复失败阻止发布。固定预发布 tag 为 **`ios-build`**，不会变更 Android 的 `CI` 或正式版发布清单；同版本资产覆盖，不同版本保留。全部资产上传成功后才更新说明。
- 无 Apple 证书签名的 IPA **不能直接安装**，需使用者自行重签/侧载；不接入 TestFlight。linker 的纯 ad-hoc 签名不等于 Apple 身份签名，不可把模拟器 app 或 xcarchive 改名后当 IPA 发布。
- `COPY_AUTH_KEY` 仍是业务编译配置，不是 Apple 签名证书。日志上传须脱敏原值及编码后的 define，不上传 `Generated.xcconfig`；模拟器诊断在引入生产密钥前保存。

### 功能与验收边界

- iOS 两类下载固定使用私有目录，仅保证前台下载与持久队列重启续传；容器路径移动的离线读取策略见 [存储指南](persistence-and-cache.md)。系统挂起、强杀期间不保证下载或定时备份运行；回前台重新触发备份调度检查。
- 阅读器保留触摸翻页、常亮与安全区，不展示 Android 音量拦截或 Monet 设置。WebP 保存先转 PNG，普通图片保存系统照片库而非命名相册；iPad 分享传有效 popover 锚点。
- 注册 `kira` URL scheme，使用 Flutter/GoRouter 默认深链处理。HTTPS 落地页是否直接拉起应用还取决于网站；未配置 AASA/Associated Domains，不承诺 Universal Links。
- iOS 保留检查更新、更新卡片、红点、检查频率与镜像设置：稳定版检查 GitHub 最新正式 Release（`releases/latest`），beta 检查固定 `ios-build`（`releases/tags/ios-build`）。更新判断与卡片列表仅接受 `.ipa`，排除 APK 和校验文件，并提供手动下载；不显示自动下载并安装的「更新」按钮，下载后自行重签安装。Android beta 仍检查 `CI`，自动安装行为不变。

首轮交付前至少检查 Actions 默认测试路径；重签后依次验收：冷启动和离线重启、COPY/WebView 登录、首次照片允许/拒绝与 WebP 保存、iPad 分享、图标切换、漫画/小说下载暂停续传、阅读位置恢复和 `kira://open/comic/...` 深链。模拟器新系统的通过不能代替 iOS 14 真机验证。
