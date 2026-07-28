# Kira 设计缺陷分析报告（已排除动漫功能）

基于代码知识图谱（233 文件 / 3608 节点）+ 逐条 file:line 复核。21 条结论中 18 条完全属实，3 条已在下文就地修正（标注「⚠️ 修正」）。

## 一、安全问题（最严重）

**1. 账号 token、密码明文存储，`SecureCredentialStore` 是死代码**
- token 写入 `lib/models/user_manager.dart:695`，密码写入 `:746`，多账号列表（**含全部密码和 token**）整体 JSON 化存进 `saved_credentials`（`:711-714`、`:747-750`）
- 包装了 flutter_secure_storage 的 `SecureCredentialStore`（`lib/models/secure_credential_store.dart:16`）及其迁移方法 `migrateFromSharedPreferences`（`:108`）在 `lib/` 内**零调用**，依赖已引入却从未启用
- 项目自己的 AGENTS.md 安全条款明确要求凭据必须用 secure storage —— 代码违反了自身规范

**2. AI API key 同样明文存两份**：`lib/api/ai_api.dart:146`（`zhipu_api_key`）+ `ai_providers` JSON blob（`:415-417`）。

**3. 设置备份功能是个凭据泄露/丢失陷阱**
- 导出时勾选 `includeSensitive` 会把 token、密码、AI key 全部写进明文 JSON 文件（`lib/utils/settings_backup.dart:84-115`）。密码是**原始明文**，`SavedCredential.toJson`（`user_manager.dart:55-63`）不做任何编码或加密
- 导入时先**删除全部现有 key** 再写入（`:126-144`）：恢复一份不含敏感 key 的备份会清空已存凭据、注销用户
- ⚠️ 修正：原文称「无任何提示」不属实。`general_page.dart:125-147` 有确认对话框，文案明确写着"将覆盖当前 {count} 项持久化配置，**包含账号**、主题、阅读器设置和本地阅读记录……当前配置会被替换。是否继续？"，导入后还主动 `clearAuthState()` + 重新 `init()`。真实缺口要弱一档：`inspectPlainText` 已算出 `sensitivePreferenceCount`，却没用来区分"这份备份不含凭据，导入后你会掉登录"这一具体后果

## 二、网络层问题

**4. 核心 API transport 完全没设超时**：`lib/utils/app_dio.dart:16-28` 未设置 `connectTimeout`/`receiveTimeout`，Dio 默认无限等待。讽刺的是全 app 其他网络调用（AI、更新检查、远程通知）都设了超时，唯独最核心的漫画/用户/评论 transport 没有 —— 弱网环境下请求可永久挂起。

**5. 每次请求新建 Dio 实例且从不 close**：`lib/api/manga/manga_api.dart:142-155` 的 `_copyDio()` 每次 `_copyGet` 调用都新建；`user_api.dart:41,162,250,292` 同样模式。每个实例独占 HttpClient 连接池 → socket 泄漏、零连接复用、每次请求都重新 TLS 握手。
- ⚠️ 修正：原文称「全项目只有 `network_api.dart:119-121` 正确 close」不准确 —— `anime_download_manager`（`:468,635-636,760,907`）与 `anime_player_page.dart:527` 也都 `close(force: true)` 了，只是属于本报告已声明排除的动漫代码。漫画/用户侧核心链路不 close 的结论成立

**6. 两套 Dio 错误语义不一致**：主 `dio` 有业务码拦截器（`api_transport.dart:123-144`），`commentDio` 没有（构造函数只给 `dio` 装了 `InterceptorsWrapper`）。导致 `getChapterComments`/`getComicComments`（`manga_api.dart:437,549`）对响应直接 `as Map<String, dynamic>` cast。
- ⚠️ 修正：崩溃需要一个前提 —— 仅当 **HTTP 200 + 业务 code 非 200**（`results` 不是 Map）时才 cast 崩溃；HTTP 非 2xx 仍由 Dio 正常抛 `DioException`。触发面比原文描述窄，但确实会把可处理的业务错误变成 `TypeError`

**7. 违反项目自身规范的 `as` cast**：AGENTS.md 明令禁止对 dynamic JSON 用 `as`，但 `manga_api.dart:276,322,353,437-441,549-553` 等处直接 cast。

**8. Host 轮换逻辑脆弱**：`api_transport.dart:205` 索引不检越界（脏配置 → 每次请求 RangeError）；探针失败把权重置 0 且**永不自动恢复**（`:282-288`）—— 一次瞬断就永久拉黑一个节点。

**9. 401 自动重登失败被静默吞掉**：`api_transport.dart:174-178` 的 `catch (_)` 无日志，违反项目"不吞错误"规则。

**10. 大 payload JSON 解析全在 UI isolate**：全项目无 `compute`/`Isolate.run` 用于 JSON（如 `getComicTags` limit:500），大列表解析会掉帧。

## 三、架构问题

**11. 上帝对象 + 巨型 State 类**：

| 类 | 行数 |
|---|---|
| `_ReaderPageState` (reader_page.dart:69) | 2470 |
| `_ChapterCommentsSheetState` | 2296 |
| `UserManager` (user_manager.dart:82) | 1539 |
| `_ComicDetailPageState` | 1504 |
| `_NetworkPageState` / `_ComicCommentsSheetState` / `_AiConfigPageState` | 1300+ |

`UserManager` 单类持有约 90 个 SharedPreferences key（`:116-204`），覆盖认证、主题、阅读器、评论、弹幕、代理、更新器……"facade + sub-stores" 拆分流于形式。

**12. 双数据源会发散**：`UserManager._keyReaderMode='reader_mode'`（`:136`）与 `ReaderSettings._keyMode='reader_mode'`（`reader_settings.dart:16`）两个 ChangeNotifier 各自缓存同一个 key，`UserManager.setReaderMode`（`:960-965`）只更新自己这份 —— 弹幕/评论/主题 key 同样模式（`:193-203`）。

**13. 广播式过度通知**：`UserManager` 把每个子 store 的变化都通过单一 `notifyListeners()` 转发（`:656-669`，约 80 处调用点）。home_page 等监听者无法按域过滤，拖一下阅读器亮度滑条都会触发首页整树 rebuild（`home_page.dart:101`）。

**14. 文档与实现脱节**：AGENTS.md 声称 `UserManager.testInstance` 支持测试注入，但代码中**不存在**（grep 全 lib/ 无匹配）；测试只能污染真实全局单例。另外 `dispose()`（`:671-679`）暴露在一个 app 级单例上，任何误调用会静默中断全局设置传播。

## 四、缓存/持久化问题

**15. `CachedRepository.load()` 无 in-flight 去重**（`cached_repository.dart:79-90`）：initState 加载 + 下拉刷新并发触发时各发一次 API 请求，缓存击穿。且只有书架仓库用了 TTL 门控。

**16. 漫画详情缓存永不过期、永不清理**：`ComicDetailRepository` 未设 `ttl`（`comic_detail_repository.dart:52-57`），每打开过一部漫画就永久留一条含完整章节列表的缓存（app 内最大的缓存 payload），无限增长；`AppPersistentCache.clearExpired()`（`app_storage.dart:162`）**零调用**，过期条目只有被再次读到时才删。

**17. 阅读历史写放大**：每翻一页都触发 `_saveReadingHistory()`（`reader_page.dart:612,1025,1071,1090,1857,1892,2344` 共 7 处），无防抖；每次都重新 `getInstance()` + 解码 + 把不断累积的 `readChapterUuids` 集合整体重新序列化写回（`utils/reading_history.dart:29-59`）。翻页越勤、读得越多，每页写入越大。
- 补充（原文漏记）：`default` 分组每次保存会写**两个** key —— `_groupKey` 与 `_legacyKey`（`reading_history.dart:56-59`），实际写放大是原估计的 2 倍

**18. cache_ 前缀约定太脆弱**：业务缓存和偏好共用一个 SharedPreferences，仅靠前缀区分（`settings_backup.dart:157-158`）。任何忘加前缀的新 key 会混进备份、且无法作为缓存被批量清理。

## 五、生命周期/代码质量

**19. 3 处 async 后未检查 mounted 的 setState**（有崩溃风险）：
- `comic_detail_page.dart:574-576` — 收藏请求失败回滚状态时
- `profile_page.dart:1046-1049` — 登录 catch 分支（前面有 5 个连续 await）
- `profile_page.dart:1088-1091` — `_loginWithToken` catch 分支（`await UserManager().logout()` 之后）

**22. 收藏失败被静默吞掉**（原文漏记）：`comic_detail_page.dart:573` 的 `catch (_)` 回滚了 UI 状态却不记日志，与第 9 条同类 —— AGENTS.md 要求 `AppLogger.recordWarning(error, stackTrace)`。原文只点了 transport 那一处。

**20. ReaderPage 不监听 `UserManager`**（`reader_page.dart:93`）：全项目 17 个页面都正确 addListener/removeListener，唯独最重要的阅读页没有 —— 只靠设置面板手动回调 `onChanged()` 续命，从其他路由改设置阅读页不会刷新。

**21. 两个评论 sheet 大面积重复代码**：分页合并去重（comic 77-133 vs chapter 380-441）、滚动方向追踪、发帖对话框（含相同的 controller dispose 变通写法）近乎逐字重复，且已出现行为分叉（只有 chapter 版在滚到底时重新显示浮动按钮）—— 典型 copy-paste 腐化。

## 做得不错的方面

- 45 个测试文件 vs 155 个源码文件，覆盖意识尚可；dispose 纪律整体良好（17/17 listener 配对正确）
- 无空 catch 块（但见第 9、22 条：有非空却不记日志的吞错误）；源码无硬编码密钥（dandanplay 凭据走 `--dart-define`）；书签有 500 上限
- 令牌刷新并发用 `_autoLoginCompleter` 处理正确
- `SecureCredentialStore` 虽是死代码，但实现质量不错：`migrateFromSharedPreferences`（`:108-134`）已经是「先写 secure → 再删 prefs → 最后打迁移标记」的安全顺序，且 `InMemorySecureCredentialStore` 便于测试注入 —— 启用它只差调用点

## 修复优先级建议

1. **P0 安全**：启用 `SecureCredentialStore` 并跑迁移（基建已存在，只差调用）；修备份导入的"先删后写"逻辑
2. **P0 稳定**：主 transport 加超时；Dio 实例复用或确保 close；3 处 setState 加 mounted 检查
3. **P1 缓存**：给 `ComicDetailRepository` 加 TTL、启动时跑一次 `clearExpired`；阅读历史保存加防抖
4. **P1 架构**：`UserManager` 按域拆分通知（或迁移到 Riverpod 细粒度 provider）；消除 reader_mode 双数据源
5. **P2 质量**：评论 sheet 去重；统一 `as` cast 为安全 JSON helper；补 AGENTS.md 与代码的出入