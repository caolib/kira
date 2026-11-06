# kira 项目规范

## 维护范围

- 两个活跃产品域：**漫画（拷贝 + 热辣）**与**轻小说**。动漫已彻底移除，不保留其兼容代码。
- Android 是主维护目标，Windows 是开发/调试宿主；macOS/Linux 不手工维护，但仍有发布构建。不要添加 `pubspec.yaml` 的 `platforms:` 键，或仅为调试宿主引入平台原生依赖。
- `android/`、`ios/`、`linux/`、`macos/`、`web/`、`windows/` 只放平台集成；静态资源放 `assets/` 并登记到 `pubspec.yaml`。
- `ref/` 已被 gitignore 排除，仅作接口资料参考；不从中导入代码，不把它作为当前行为的证据。
- 横向滑切 tab 与 GNav 胶囊导航是产品功能，重构时保留。返回首页/搜索页时键盘不应重新弹出：见 `dismiss_keyboard_observer.dart` 与 `test/routing/main_shell_focus_test.dart`。

## 开发与验证

所有命令在仓库根目录执行。依赖源固定为 pub.dev，不设置 `PUB_HOSTED_URL`；用以下命令安装并确认锁文件未变：

```bash
flutter pub get --enforce-lockfile
git diff --exit-code -- pubspec.lock
```

| 操作 | 命令 / 入口 |
| --- | --- |
| 静态分析 | `flutter analyze --no-pub` |
| 相关测试 | `flutter test --no-pub test/xxx_test.dart --reporter compact` |
| 格式化 | `dart format <本次改动的 Dart 文件路径…>` |
| 模型生成 | `dart run build_runner build` |
| 本地化生成 | `flutter gen-l10n` |
| Android 发布构建 | `flutter build apk --release --target-platform android-arm64` |
| 运行管理 | 项目 `run-kira` skill；人工入口 `scripts/run.ps1 <win、mumu、emu>` |

- 发布构建前核对本地与对应 CI job 的 Flutter 版本，以 `.flutter-version` 为准，二者保持一致。
- 代码改动收尾跑静态分析（无 error/warning），仅格式化本次改动文件。纯 Markdown 改动只检查文档。
- 应用已运行且用户允许时，分析完成后用 `run-kira` 热重载并检查日志；未运行时，冷启动先征得同意。本机可能有自动热重载 hook，新克隆不假定存在。
- 测试失败、运行报错与跳过步骤如实报告；判定回归前在干净工作区复跑对应用例，以本次复跑结果作为基线。

## 代码地图

| 路径 | 职责 |
| --- | --- |
| `lib/api/` | `ApiTransport`、领域 API（manga/network/novel/user）、`ApiClient` facade；独立 `AiApi`、一言与拷贝配置更新 |
| `lib/models/` | 数据模型、偏好子 store、`CachedRepository` 基类与 `SecureCredentialStore` |
| `lib/repositories/` | 领域缓存仓库与 `novel_reader_source.dart` |
| `lib/providers/` | Riverpod：应用单例、偏好、仓库、小说与备份 providers |
| `lib/pages/` | 页面；大页面分片放宿主旁的子目录 |
| `lib/routing/` | `app_router.dart`、`AppRoutes`、typed extra、`MainShell`、键盘观察器 |
| `lib/theme/` | 设计令牌 spacing/radius/shadows/typography/icon-size/status-colors、`ReaderChrome` 与小说阅读主题 |
| `lib/widgets/` | 可复用组件；模式见 `docs/widgets.md` |
| `lib/backup/` | 分类、编解码、加密事务、本地/WebDAV、定时调度与日志 |
| `lib/utils/` | 存储、日志、服务定位器、下载、阅读历史/统计与应用更新 |
| `lib/l10n/` | 简繁 ARB 与生成的本地化文件 |
| `scripts/`、`.github/workflows/` | 本地运行/构建脚本与 CI/发布构建 |

## 架构约定

- **状态管理**：新页面用 `ConsumerStatefulWidget` + `ref.read(provider)`；providers 放 `lib/providers/`。旧页面的 `UserManager()` / `ApiClient()` 单例模式仍可共存；`Services.api` / `Services.override<T>()` 目前只在测试中使用，生产代码尚未接入（且未覆盖 `GeneralSettings`、`NovelReaderStatusSettings`、`CopyAccountStore`）。
- **导航**：路由统一在 `lib/routing/app_router.dart` 声明，使用 `context.pushNamed(AppRoutes.xxx)`；额外参数用 `ComicDetailExtra`、`ReaderExtra`、`NovelReaderExtra`、`RankingExtra` 等类型，不另建 `MaterialPageRoute`。
- **API**：调用领域入口，如 `ApiClient().manga.getMangaHome()`。AI 调用走独立 `lib/api/ai_api.dart` 的 `AiApi`，使用自己的 `AppDio` 与 `AiSettings`，不挂到 `ApiClient`。
- **缓存仓库**：`repo.load()` 自动 cache-first，并发调用共用 in-flight future；`loadFromCache()` 只读缓存，`invalidateCache()` 用于刷新。缓存 I/O 走 `AppStorage.cache` / `AppStorage.preferences`。
- **偏好**：`UserManager` 是 facade，子 store 为 `general` / `reader` / `novelStatus` / `comment` / `theme` / `network` / `copyAccount`；新增/改动共有偏好只在所属子 store 定义字段、默认值与持久化，facade 对原先重复的键只做委托并单次转发通知，不再缓存第二份状态。其余非重复的账号/应用级键仍由 facade 自持。只关心单一域时监听对应子 store。
- **序列化**：手写与 `json_serializable` 共存；修改模型前查 `docs/architecture.md` 的序列化清单，改生成类后运行 build_runner。
- **分片**：沿用宿主旁 `*_parts/` 或页面名子目录；宿主 `part '子目录/yyy.dart';`，分片 `part of '../host.dart';`。宿主方法可用 extension 分片，辅助组件/函数可直接定义在分片中。
- **本地化**：`app_zh.arb` 为模板，`app_zh_Hant.arb` 为繁体镜像，配置在 `l10n.yaml`；ARB 修改后运行 gen-l10n。文案用 `AppLocalizations.of(context)!.keyName`，参数化文案调用生成方法。

## 编码与界面

- 2 空格缩进；适当使用尾逗号、`const` 构造与小组件。类/组件用 `PascalCase`，成员用 `camelCase`，文件用 `snake_case.dart`，私有成员用 `_` 前缀。
- dynamic JSON 使用 `jsonString` / `jsonInt` / `jsonList` / `jsonMap` / `jsonDouble` / `jsonBool` / `NullIfEmptyString` 等安全助手，不做 `as` 强转；类型问题直接修复，不用抑制规则绕过。
- catch 中保留原始异常与堆栈并用 `AppLogger.recordWarning` 记录，不留空 catch，不合成异常替换真实原因。
- 操作失败时向用户显示实际原因：网络用 `NetworkError.message(e, l10n: l10n)`，小说用 `novelErrorMessage(e, fallback: ...)`；固定文案仅用于无原因文本时的 fallback。例外仅为 IP 封禁指导与小说 code 210（展示完整响应体）。
- 导入 `comic.dart` 时使用 `hide Theme`，避免与 Flutter `Theme` 冲突。
- 尺寸优先用 `AppSpacing`（4/8/12/16/20/24）、`AppRadius`（xs–xl/full 与 `*R`）、`AppIconSize`（xs 12 / sm 16 / md 18 / lg 20 / xl 24 / placeholder 32 / empty 48 / display 64）；只有组件专属的一次性尺寸用字面值。
- 文字从 `Theme.of(context).textTheme` 派生；小型元信息用 `AppTypography.meta(tt)`，FAB 标签用 `AppTypography.fabLabel(tt)`，不另建页面级 TextTheme。
- 卡片用 lg(16)，对话框/弹层用 xl(20)，由 `main.dart` 主题统一控制，不逐页覆写 shape。
- 状态色用 `AppStatusColors`（success/warning/danger/neutral/fill/hotAccent），阅读器配色用 `ReaderChrome`，不手写语义颜色；`PlayerChrome` 无调用，属于已移除播放器的遗留类。
- 新建或抽取 `lib/widgets/` 组件前先读 `docs/widgets.md`，复用既定骨架、错误重试、sheet、section header、封面、本地列表、登录过期弹窗；网络封面用 `CoverImage`，封面飞行用 `AppHero`，保留其减少动画适配。

## 测试要求

- 默认只跑与改动相关的测试文件；**全量测试须用户明确要求**。可在非平台代码中验证的新功能/修复应补测试。
- 新测试按 `lib/` 路径镜像到 `test/`，文件名 `*_test.dart`；根目录的既有用例不强制搬迁。
- Widget 测试必须用 `test/test_helpers.dart` 的 `wrapWithApp(child)` 注入本地化；在 setUp/tearDown 调用 `setupSecureCredentialStoreForTest()` / `teardownSecureCredentialStoreForTest()` 隔离账号。
- `CachedRepository` 测试覆写 `loadFromCache` / `saveToCache`，使用内存映射隔离真实 SharedPreferences。
- 持久化回归额外覆盖默认 prefs 后端、重建实例与写入失败；仅测 `InMemorySecureCredentialStore` 不足以证明冷启动会话能恢复。

## 持久化、备份与安全

- 涉及用户偏好、缓存、凭据、阅读历史等存储改动，先读 `docs/persistence-and-cache.md`，按 `AppStorage.memory/cache/preferences`、键名前缀与排除边界选择后端。
- 新增/修改可备份偏好或 `BackupSchema` 时，逐项核对所属 store 的实际 `get*/set*` 类型与备份分类；ARGB 颜色登记为 `int`，单项类型错配会阻断整个备份。
- 备份回归通过真实 store setter 写入非默认值，再验证导出→解析→恢复→重载；可空字段同时覆盖未设置/清除，避免默认值未落盘掩盖类型错配。
- 凭据统一经 `SecureCredentialStore` 存入应用私有 SharedPreferences **明文**；类名与 `secure_mirror_*` 是兼容名称，不代表加密。已不使用运行时 Keystore/Keychain 或 `flutter_secure_storage`。
- 保留旧明文迁移、退出标记、写入失败处理、备份加密与普通备份/缓存清理的凭据排除；升级时可能需要一次重新登录，保存后的会话须跨冷启动保留。
- 签名材料（`android/key.properties`、keystore）不提交；隔离测试用内存凭据 store，持久化回归用默认 prefs 后端。

## 按需查阅

| 触发条件 | 必读文档 |
| --- | --- |
| 修改 API、缓存仓库、模型序列化或 UserManager 偏好归属/通知 | `docs/architecture.md` |
| 修改轻小说功能、阅读/鉴权/下载交互 | `docs/novel.md` |
| 新建/抽取复用组件 | `docs/widgets.md` |
| 修改存储、备份或恢复 | `docs/persistence-and-cache.md` |
| Windows/Android 构建报错、改 `windows/CMakeLists.txt`、添加媒体依赖 | `docs/platform-build.md` |

- 文档引用代码用「文件路径 + 符号名」，不写行号；行号随重构漂移，过期后反而误导。
- Windows 的 C4819/STL1011/C1083/C1041 按平台文档排查；保留 `/utf-8`，否则中文系统构建会失败。
- Android clean 后若报 `package identifier or launch activity not found`，先跑一次 `flutter build apk --debug`；不给 MainActivity 加 LAUNCHER intent-filter、不禁用它，避免破坏切换 logo。

## 提交与发布

- 仅在用户要求时提交/推送；提交用 emoji + Conventional Commit + 简洁中文，如 `✨ feat: 添加检查更新功能`、`🐛 fix: 登录过期后提醒用户登录`。
- `scripts/git-hooks/pre-commit` 自动运行 `scripts/update_version_code.ps1`，将 versionCode 设为「HEAD 提交数 + 1」并暂存 `pubspec.yaml`，属于预期改动，不回退。新克隆需 `git config core.hooksPath scripts/git-hooks` 启用。
- 普通开发不更新 `docs/CHANGELOG.md`。发版、续发、发布日志修正走项目 `/release` skill；自然语言请求先读 `.claude/skills/release/SKILL.md`，执行**信息确认 → 完整日志审查 → 发布批准**，批准后才提交、打标签和推送。
- CI：`build-ci.yml` 为 `v*-beta*` tag/手动 Android 构建；`build-test.yml` 仅手动构建测试 APK artifact（不创建 Release）；`release.yml` 为非 beta 的 `v*` tag/手动正式版构建（arm/arm64/x64 APK 与 Windows 安装包）；`release-all.yaml` 手动构建 Android arm64、Windows ZIP+Setup、macOS、Linux（不含 iOS/web）。
