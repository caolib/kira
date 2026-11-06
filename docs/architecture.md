# Architecture Deep-Dive

`CLAUDE.md` 保留日常规则与约定；本文收录按需查阅的架构细节：API 分层结构、CachedRepository 解剖、模型序列化清单、UserManager 偏好归属与通知、拷贝接口登录的密钥注入。

## 拷贝登录：三条通道与签名密钥

拷贝账号有三条登录通道，由 `CopyLoginChannel` 区分。选择器按枚举声明顺序展示，默认选中 `webApi`：

| 通道 | 打哪里 | 请求头 |
| --- | --- | --- |
| `webApi`（默认） | `copyLoginHost` + `/api/kb/web/login`（与 `web` 同一个接口，客户端直发） | 浏览器头（1:1 复刻抓包，见下） |
| `app` | `copyApiHost` + `/api/v3/login` | `CopyAppHeaders`（15 项业务头 + 签名） |
| `web` | `copyLoginHost` 官网页面，WebView 自动填表 → 抓 cookie token | 浏览器头（由 WebView 自己发） |

`webApi` 与 `web` 打同一个接口，区别只是省掉 WebView；`webApi` 不需要签名密钥，任何构建都提供。

**`app` 通道当前由 `LoginPage._appLoginEnabled` 整体关闭**（功能仍有问题），修好后置回 true；恢复后仍要求签名密钥就绪。

**两条接口通道（`webApi` / `app`）先直连、失败再用代理重试一次**：直连通常更快，被墙/被风控时再退回代理。重试对用户静默（只报最后那次失败）。用户显式选了「直连」代理模式时没有可退回的代理，不重试。实现见 `UserApi._createLoginDio` 的 `useProxy` 与 `LoginPage._authenticateCopyInterface`。

**`webApi` 请求头**按抓包 1:1 复刻（UA / `sec-ch-ua` / `accept-language` 集中在 `user_api.dart` 顶部三个常量里，改版本号要三个一起改）。Dio 自己计算 `content-length` 并接管 `host`/`accept-encoding`，代码里不声明；抓包里的 `_ga` / `_ga_SS4LL7K6CL` 是站点统计 cookie，与本请求无关，故意不带。

**签名密钥**（`CopySignature.authKey`）= 拷贝官方 APK 签名证书 DER 的 MD5 hex。它不入库，取值顺序：测试注入（`debugKeyOverride`）→ 编译期 `--dart-define=COPY_AUTH_KEY=…` → 桌面运行时的同名环境变量。Android/iOS 没有运行时环境变量，只能走编译期注入。

未配置时 `CopySignature.isConfigured` 为 false，登录页选择器里不出现 App 接口通道——签名无效时服务端**不报错**，只返回 `code 200` + 空数据，任其展示会变成「密码正确却登不上」。

注入方式：

```powershell
# 桌面调试：run.ps1 会把环境变量传给 flutter run 启动的进程
$env:COPY_AUTH_KEY = "<官方证书 MD5>"
.\scripts\run.ps1 win

# 打包 / Android：脚本读同名环境变量并转成 --dart-define
$env:COPY_AUTH_KEY = "<官方证书 MD5>"
.\scripts\build_apk.ps1
```

CI 从 `secrets.COPY_AUTH_KEY` 注入（四个 workflow 均已接好）。

**设备指纹**（`CopyAppHeaders`）：`device` / `deviceinfo` 首次生成后持久化到 `AppStorage.preferences` 的 `copy_device_id` / `copy_device_info`，跨会话保持稳定；`pseudoid` 是进程内随机一次。三者跳变会被服务端当作新设备。

## API Layer: Transport + Domain Classes

- `ApiTransport` holds shared Dio instance, auth tokens, cache headers, host rotation logic.
- Domain API classes (`MangaApi`, `NovelApi`, `NetworkApi`, `UserApi`) receive `ApiTransport` via constructor injection.
- `ApiClient` is a facade that creates the transport and exposes domain API objects as `.manga/.novel/.network/.user` fields; `ApiClient.setTestInstance()` swaps the singleton for tests. `ApiClient()` is always the same instance — calling it in a hot path is fine, but it does perform `UserManager()` + `DataCache()` lookups.

## Data Layer: CachedRepository 解剖

- `CachedRepository<T>` in `lib/models/cached_repository.dart` (the only `DualCachedRepository<A,B>` user is `MangaHomeRepository`, holding manga + copy-manga homes).
- Each repository defines: `cacheKey`, `ttl`, `skipApiIfCacheFresh`, `deserialize`/`serialize`, `fetchFromApi()`.
- Strategies: parallel (default), sequential, TTL-gate (`skipApiIfCacheFresh`) and API-transparent — configured via constructor params.

## Model Serialization

- **Generated models**: `Author`, `MangaTopic`, `Theme`, `ComicGroup` (in `comic.dart`), `ComicComment`, `ChapterComment` use `json_serializable` with `@JsonSerializable(fieldRename: FieldRename.snake)`. Run `dart run build_runner build` after changes. Only three `.g.dart` files exist — most models are not generated.
- **Hand-written models** (Comic, MangaHome, CopyMangaHome, MangaBanner, BookshelfItem, Chapter, novel models, etc.): hand-written `fromJson`/`toJson` — too many custom coercions for generated code. `comic.dart` deliberately mixes both styles; check per class before assuming a generator change is needed.

## UserManager: Facade + Sub-stores 偏好归属与通知

- `UserManager` is a singleton facade. Internally delegates to `GeneralSettings`, `ReaderSettings`, `CommentSettings`, `ThemeSettings`, `NetworkSettings`, `NovelReaderStatusSettings` and `CopyAccountStore` — all singletons too, so `Services.reader` and `UserManager().reader` are the same object. `NovelReaderStatusSettings`（小说状态组件独立配置，键前缀 `novel_status_overlay*`）首启继承漫画侧 `ReaderSettings` 现值后两侧独立演化。
- Sub-stores are independent `ChangeNotifier`s. Sub-store changes are forwarded through the facade's single `notifyListeners()`, so a listener on `UserManager` rebuilds on *any* settings change, not just the domain it cares about. Listen to the sub-store directly when that matters.
- **Shared preference ownership is consolidated**: no preference key is declared in both `UserManager` and `ReaderSettings` / `CommentSettings` / `ThemeSettings` / `NetworkSettings`. The facade retains compatibility getters/setters for these formerly duplicated keys as pure delegates, including derived theme options. Its remaining own keys (e.g. `desktop_font_family`, `reader_horizontal_image_scale`) are not duplicates.
- Keep each preference's state, defaults, normalization and persistence in its owning sub-store; a facade wrapper adds neither a field nor another notification. `ThemeSettings` owns the floating-nav label downgrade, custom-color activation and native logo switching. On mobile, logo initialization reads the actual launcher icon without rewriting prefs; a logo change saves and notifies before invoking the native switch, and native failures retain the saved preference and original warning.
- Sub-stores bind their prefs cache through `syncPrefs` during `initFromPrefs`, so reloading settings also rebinds subsequent writes to the loaded backend.
