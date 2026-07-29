# Kira 设计缺陷分析报告（已排除动漫功能）

基于代码知识图谱（233 文件 / 3608 节点）+ 逐条 file:line 复核。21 条结论中 18 条完全属实，3 条已就地修正（标注「⚠️ 修正」），另补 1 条原文漏记（第 22 条）。

**本文档同时作为进度台账**：每条标注当前状态，未完成项在文末「剩余工作」中给出接续建议。

## 进度总览

| 状态 | 条目 |
| --- | --- |
| ✅ 已修复 | 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 19, 20, 22 |
| 🔶 部分完成 | 12（仅 `readerMode`）、13（仅 2 个页面）、21（未合并发帖对话框，有意为之） |
| ⏸️ 未开始 | 1, 2, 3（凭据加密，用户自行处理）、10, 11, 18 |

相关提交：`b409278` `cf87f6f` `d6cea78` `c6725a6` `a0d7206` `33c588b` `121b503`

配套成果：测试从 13 个长期失败修到 **286 个全绿**（`121b503`），此前只能靠与基线逐条比对确认无回归。

## 一、安全问题（最严重）

> ⏸️ **本节三条均未开始** —— 用户已明确表示凭据/加密整块自行处理。
> 讨论结论见文末「关于备份加密的结论」。

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

**✅ 4. 核心 API transport 完全没设超时** —— 已修（`b409278`）
> 改在 `AppDio.create` 一处用 `??=` 补默认值（connect 15s / receive 30s），一次覆盖全部调用点。Dio 中 `null` 才表示无限等待，因此 AI 的 5 分钟、动漫下载的 2 小时等显式设置不受影响。图片走独立 `HttpClient`，不在此路径。

原问题：`lib/utils/app_dio.dart:16-28` 未设置 `connectTimeout`/`receiveTimeout`，Dio 默认无限等待。讽刺的是全 app 其他网络调用（AI、更新检查、远程通知）都设了超时，唯独最核心的漫画/用户/评论 transport 没有 —— 弱网环境下请求可永久挂起。

**✅ 5. 每次请求新建 Dio 实例且从不 close** —— 已修（`b409278`）
> `manga_api` 高频路径改为两个复用实例；headers 依赖用户可改的 `copyAppVersion`，故从 `BaseOptions` 挪进 `onRequest` 拦截器动态注入，行为不变但连接池得以复用。`user_api` 四处低频调用（登录/注册/清历史 ×2）补 `try/finally close()`。

原问题：`manga_api.dart:142-155` 的 `_copyDio()` 每次 `_copyGet` 调用都新建；`user_api.dart:41,162,250,292` 同样模式。每个实例独占 HttpClient 连接池 → socket 泄漏、零连接复用、每次请求都重新 TLS 握手。
- ⚠️ 修正：原文称「全项目只有 `network_api.dart:119-121` 正确 close」不准确 —— `anime_download_manager`（`:468,635-636,760,907`）与 `anime_player_page.dart:527` 也都 `close(force: true)` 了，只是属于本报告已声明排除的动漫代码。漫画/用户侧核心链路不 close 的结论成立

**✅ 6. 两套 Dio 错误语义不一致** —— 已修（`c6725a6`）
> 抽出 `ApiTransport.rejectIfBusinessError`，主 `dio` 与 `commentDio` 共用同一套语义。

原问题：主 `dio` 有业务码拦截器（`api_transport.dart:123-144`），`commentDio` 没有。导致 `getChapterComments`/`getComicComments` 对响应直接 cast。
- ⚠️ 修正：崩溃需要一个前提 —— 仅当 **HTTP 200 + 业务 code 非 200**（`results` 不是 Map）时才 cast 崩溃；HTTP 非 2xx 仍由 Dio 正常抛 `DioException`。触发面比原文描述窄，但确实会把可处理的业务错误变成 `TypeError`

**✅ 7. 违反项目自身规范的 `as` cast** —— 已修（`c6725a6`）
> `manga_api` 的 cast 全部换成安全 JSON helper，并新增 `_mapList` 收敛「取列表 → 逐项 fromJson」这一重复十余处的模式。残留的 3 处 cast 均有前置 `is Map` 守卫。

**✅ 8. Host 轮换逻辑脆弱** —— 已修（`c6725a6`）
> 索引改用 `clamp` 防越界；探测失败改为降到 `minHostWeight = 0.01` 而非归零。归零意味着节点永久出局——代码中没有任何路径能把 0 权重调回来，一次瞬断就拉黑到进程结束。留极小值后它仍有极低概率被选中，恢复正常后下次测速即回升。

**✅ 9. 401 自动重登失败被静默吞掉** —— 已修（`c6725a6`）
> 重登失败与重试失败两处 `catch (_)` 均补 `AppLogger.recordWarning`。

**⏸️ 10. 大 payload JSON 解析全在 UI isolate** —— 未开始
全项目无 `compute`/`Isolate.run` 用于 JSON（如 `getComicTags` limit:500），大列表解析会掉帧。

## 三、架构问题

**⏸️ 11. 上帝对象 + 巨型 State 类** —— 未开始

| 类 | 行数 |
|---|---|
| `_ReaderPageState` (reader_page.dart:69) | 2470 |
| `_ChapterCommentsSheetState` | 2296 |
| `UserManager` (user_manager.dart:82) | 1539 |
| `_ComicDetailPageState` | 1504 |
| `_NetworkPageState` / `_ComicCommentsSheetState` / `_AiConfigPageState` | 1300+ |

`UserManager` 单类持有约 90 个 SharedPreferences key（`:116-204`），覆盖认证、主题、阅读器、评论、弹幕、代理、更新器……"facade + sub-stores" 拆分流于形式。

**🔶 12. 双数据源会发散** —— 部分完成（`c6725a6`）
> 已把 `readerMode` 改为委托 `ReaderSettings`，作为样板。**但核查发现范围远超原文描述**：重复键不是几个，而是 **48 个**（`UserManager` 共 81 个键）。抽查 5 个 setter，无一委托子 store，全部自己写 SharedPreferences —— 「facade + sub-stores」目前基本只是形式。
>
> 严重性需下调一档：子 store 被直接使用的地方（`reader.statusOverlay*`、`theme.appFontFamily`、`theme.defaultFontSize` 等）**全部是新设置，不在那 48 个重复键里**。两条路径访问的集合不相交，所以当前不会真的发散 —— 是埋着的雷，不是活 bug。下一个人用子 store 路径去改一个重复键就会踩到。
>
> 陷阱与正确做法已写入 `CLAUDE.md`。

**🔶 13. 广播式过度通知** —— 部分完成（`33c588b`）
> 新增 `SettingsRebuildGuard`：监听者用 Record 声明关心的设置快照，广播到达时先比对，无关变化直接短路。已应用于 `home_page` 与 `main_shell`。
>
> **未采用原文建议的「按域拆分监听」**，因为在当前架构下不成立：首页要的 `mangaHomeSource`、底栏要的 `autoCheckUpdate` / `disclaimerAccepted` / `remoteNoticeEnabled` 根本不在任何子 store 里；而 `bannerVisible` 这类重复键的值仍从 `UserManager` 副本读，改监听子 store 会直接漏更新。**那条路要等第 12 条的 48 个键全部委托之后才能走。**
>
> 实施中踩到一个真实陷阱：`main_shell` 的 `navOrder` 是 `List`，而 **Record 对 List 字段是引用相等而非内容相等**，直接放进快照会导致导航顺序变化被判定为「无变化」、底栏静默不更新。必须展平后比较，已有测试钉住。

**✅ 14. 文档与实现脱节** —— 已修（`c6725a6`）
> 删除 `CLAUDE.md` 中并不存在的 `testInstance` 说法，并补记「48 个重复键」与「facade 通知为全局广播」两个陷阱。

## 四、缓存/持久化问题

**✅ 15. `CachedRepository.load()` 无 in-flight 去重** —— 已修（`cf87f6f`）
> `load()` 共享 in-flight future，消除 initState 加载与下拉刷新并发触发时的缓存击穿。

**✅ 16. 漫画详情缓存永不过期、永不清理** —— 已修（`cf87f6f`）
> `ComicDetailRepository` 补 7 天 TTL；启动后台跑一次 `clearExpired`（此前零调用）。`clearExpired` 同时改为正则探测末尾过期戳，不再对每个条目全量 `jsonDecode` —— 否则清理本身就会在 UI isolate 上解析漫画详情这类大 payload。

**✅ 17. 阅读历史写放大** —— 已修（`cf87f6f`）
> `ReadingHistory.save` 加 800ms 防抖，窗口内多次保存合并落盘。几个易错点：`_PendingSave` 累积 `readChapterUuids`（否则连续翻章会漏记中间章节）；`updatedAt` 取 save 调用时刻而非落盘时刻（否则同批写出的记录时间戳相同，`latestForComic` 无法分辨新旧）；`get`/`latestForComic` 先冲刷待写队列；离开阅读页、备份导入导出、清空偏好、缓存管理页均先 `flush`（否则重置应用后待写进度会被延迟写回，记录「复活」）。
- 补充（原文漏记）：`default` 分组每次保存会写**两个** key —— `_groupKey` 与 `_legacyKey`，实际写放大是原估计的 2 倍

**⏸️ 18. cache_ 前缀约定太脆弱** —— 未开始
业务缓存和偏好共用一个 SharedPreferences，仅靠前缀区分（`settings_backup.dart:157-158`）。任何忘加前缀的新 key 会混进备份、且无法作为缓存被批量清理。

## 五、生命周期/代码质量

**✅ 19. 3 处 async 后未检查 mounted 的 setState** —— 已修（`b409278`）
- `comic_detail_page.dart:574-576` — 收藏请求失败回滚状态时
- `profile_page.dart:1046-1049` — 登录 catch 分支（前面有 5 个连续 await）
- `profile_page.dart:1088-1091` — `_loginWithToken` catch 分支（`await UserManager().logout()` 之后）

**✅ 22. 收藏失败被静默吞掉**（原文漏记）—— 已修（`b409278`）
`comic_detail_page.dart:573` 的 `catch (_)` 回滚了 UI 状态却不记日志，与第 9 条同类。

**✅ 20. ReaderPage 不监听 `UserManager`** —— 已修（`c6725a6`）
> 补 addListener/removeListener，并在回调中重新套用依赖设置的副作用（音量键拦截）。

原问题：全项目 17 个页面都正确配对 listener，唯独最重要的阅读页没有 —— 只靠设置面板手动回调 `onChanged()` 续命，从其他路由改设置阅读页不会刷新。

**🔶 21. 两个评论 sheet 大面积重复代码** —— 部分完成（`a0d7206`）
> 已提取三块：
> - `CommentScrollBehavior` mixin —— 两版滚动方向追踪原本逐字相同，但**只有 chapter 版有「滚到底恢复显示按钮」分支**，comic 版一路下滑到底后按钮再也回不来。统一取正确的那版，这是本次唯一用户可感知的修复
> - `appendDedupedById` —— 三处分页去重都是 `where(...any(...))`，O(n×m) 改为线性；并去掉 incoming 自身的重复（服务端在分页边界重复返回同一条评论时旧写法会放进去）
> - `CommentText` —— 长度 3/200 此前硬编码在 10 处、跨 3 个文件（含 API 层校验）。计数用 `runes`，否则 emoji 按 UTF-16 算成 2 个字符，显示字数与校验结果对不上
>
> **发帖对话框有意未合并**：两版骨架相似，但 comic 需要回复目标、chapter 有错误日志展开面板，提交后一个改本地列表一个刷首页。强行统一会得到参数爆炸的「万能对话框」，是转移复杂度而非消除。真正同构的部分（长度校验）已经提出来了。

## 做得不错的方面

- 45 个测试文件 vs 155 个源码文件，覆盖意识尚可；dispose 纪律整体良好（17/17 listener 配对正确）
- 无空 catch 块（但见第 9、22 条：有非空却不记日志的吞错误，均已修）；源码无硬编码密钥（dandanplay 凭据走 `--dart-define`）；书签有 500 上限
- 令牌刷新并发用 `_autoLoginCompleter` 处理正确
- `SecureCredentialStore` 虽是死代码，但实现质量不错：`migrateFromSharedPreferences`（`:108-134`）已经是「先写 secure → 再删 prefs → 最后打迁移标记」的安全顺序，且 `InMemorySecureCredentialStore` 便于测试注入 —— 启用它只差调用点

---

## 剩余工作

按建议顺序排列。

### 1. 凭据安全（第 1、2、3 条）— 用户自行处理

启用 `SecureCredentialStore` 时的三点加固（现有 `migrateFromSharedPreferences` 顺序正确，但不够健壮）：

1. 写入后**立即回读校验**，通过才删 SharedPreferences
2. 任何一步失败 → 不删、不打迁移标记，静默降级继续用 SharedPreferences，下次启动重试。否则在无 keyring 的 Linux、精简 Windows 环境下 `doWrite` 抛异常会直接崩启动，更糟的是可能已删掉一部分
3. 读取走**双路 fallback**：secure 读不到就回落 prefs

现有 store 只覆盖 username/password/credentials，**未覆盖 `user_token`**，需补。

连锁影响：凭据迁走后 `settings_backup` 的 `_sensitivePreferenceKeys` 就扫不到它们，`includeSensitive` 导出将不再包含账号 —— 需同步调整 UI 文案，否则用户以为备份了账号、换机后才发现没有。顺带的好处是第 3 条「导入后掉登录」会自动消失，因为导入只删 SharedPreferences，不再动 secure storage。

#### 关于备份加密的结论

备份文件要跨设备传输，OS keystore 帮不上忙。**密钥不能放在产物里**：`--dart-define` 注入的值是编译期常量，会明文进入 `libapp.so` / `app.so`，`strings` 即可提取。全体用户共用一个内置密钥意味着一旦有人提取出来，所有备份文件同时失守，且无法补救（换密钥会让老备份解不开）。开源项目还有额外矛盾：自行编译的版本没有该密钥，无法导入官方版导出的备份。

正确形态只有两条：本地存储交给 OS keystore（密钥由系统保管），跨设备文件用**用户口令派生**（PBKDF2/Argon2 + AES-GCM，算法公开、密钥在用户脑中）。折中方案是备份只带 token 不带密码 —— token 有时效、可服务端吊销，泄露损失比密码低一个数量级，且换机导入后仍是登录态，用户无感知。

### 2. 第 12 条完整版：48 个重复键全部委托

约 200 处机械改动（每个键含字段、getter、setter、init 读取各一处）。调用点（85+）无需改动，facade 接口保持不变。做完之后第 13 条才能升级成真正的按域监听。

样板见 `readerMode`：删掉 `UserManager` 的键常量、字段与 init 读取，getter/setter 改为委托子 store。子 store 的 `notifyListeners` 会经 `_onSubStoreChanged` 转发到 facade 监听者，通知链不受影响。

注意 `user_manager_test.dart` 覆盖有限，改动量大而回归保护弱 —— 建议分批（按子 store 逐个迁）并每批跑全量测试。

### 3. 第 13 条推广：其余 13 个监听者

`SettingsRebuildGuard` 目前只用于 `home_page` 与 `main_shell`。其余监听者（`bookshelf_page`、`search_page`、`profile_page` 等）需逐个核对 build 及其 helper 读到的全部设置，收益比前两个小得多。

**维护约束**：`watchedSettings()` 必须列全依赖，漏一个就是静默不更新的 bug；`List`/`Map` 字段必须展平。已写入 mixin 文档。

### 4. 第 10 条：大 payload JSON 移出 UI isolate

**建议先实测掉帧再动手**，否则是凭空优化。可用 DevTools 的 timeline 观察 `getComicTags`（limit 500）与漫画详情解析。真要做的话 `compute` 有 payload 拷贝开销，小 payload 反而更慢，需要按阈值分流。

### 5. 第 18 条：cache_ 前缀

涉及存储布局，改动面广。可考虑迁到独立的 SharedPreferences 实例或换 key-value 存储后端，届时先读 `docs/persistence-and-cache.md`。

### 6. 第 11 条：巨型 State 拆分

风险最高，建议最后做。`_ReaderPageState` 2470 行，且刚加了 `UserManager` 监听（第 20 条），拆分时注意生命周期配对。可从抽取独立职责入手（图片预载、音量键、书签同步），而非一次性重构。
