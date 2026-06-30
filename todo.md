# Kira 项目设计问题清单

> 审查日期: 2026-06-30
> 最后更新: 2026-06-30

---

## P0 — 严重问题

### 1. `UserManager` 上帝对象（1341行，60+字段）— ✅ 已修复

- **文件**: `lib/models/user_manager.dart`
- **原问题**: 单一类承担了至少 4 种职责
- **修复**: 拆分为 5 个独立 ChangeNotifier 子存储 + `PrefsStore` 基类
  - `ReaderSettings`（18 字段）、`DanmakuSettings`（8 字段）、`CommentSettings`（7 字段）、`ThemeSettings`（12 字段）、`NetworkSettings`（5 字段）
  - `NetworkProxyMode`/`NetworkProxyType` 枚举提取到 `network_proxy_types.dart`
  - UserManager 保持 facade，转发通知以兼容现有代码
  - `PrefsStore` 基类提供 typed helpers 自动调 `notifyListeners()`

### 2. 全局单例泛滥，无依赖注入 — ✅ 已修复

- **原问题**: 所有服务通过工厂构造函数暴露全局单例，不可测试
- **修复**: 创建 `Services` 服务定位器（`lib/utils/services.dart`）
  - `Services.override<T>()` 支持测试注入
  - `Services.reset()` 清理测试状态
  - `UserManager.testInstance` / `ApiClient.testInstance` 使工厂构造函数自动返回测试实例
  - 现有 `UserManager()` / `ApiClient()` 调用无需改动即可获得注入能力

### 3. 空 catch 块静默吞掉错误（11处）— ✅ 已修复

- **修复**: 全部替换为 `catch (e, stack) { AppLogger.instance.recordWarning(...) }`
- 涉及 8 个文件

---

## P1 — 中等问题

### 4. 无状态管理框架 — 未开始
- **建议**: 引入 Riverpod

### 5. 巨型 Widget 文件 — ✅ 部分修复
- **已完成**: profile_page.dart 从 2207→608 行（拆出 LoginPage/RegisterPage/DisclaimerPage/AboutPage）
- **已完成**: home_page.dart 减少 ~130 行（ComicCard 提取到 widgets/）
- **已完成**: copy_manga_list_page.dart 减少 ~140 行（提取到共享 widgets）
- **已评估**: reader_page.dart 已有 part 文件结构，进一步拆分收益有限

### 6. 业务逻辑嵌入 Widget — 未开始
- **建议**: 抽象 Repository 层，统一缓存-请求模式

### 7. `lib/widgets/` 目录为空 — ✅ 已修复
- 创建共享组件：
  - `ComicCoverCard` — 漫画封面卡片，替换 9 个页面的重复实现
  - `ShimmerShell` + `ShimmerBox` + `ComicCoverSkeletonGrid` + `ComicRowSkeletonList` — 加载骨架屏
  - `ErrorRetryView` + `SliverErrorRetryView` — 错误重试状态
  - `NullIfEmptyString` 扩展 — 空字符串转 null
  - `showLoginExpiredDialog()` — 登录过期对话框（P2-16）

### 8. 不安全 `as` 类型转换 — ✅ 已修复（API 层和模型层）
- 创建 `lib/utils/json_helpers.dart`（`jsonList`/`jsonInt`/`jsonString`/`jsonDouble`/`jsonBool`/`jsonMap`）
- 已替换: manga_api.dart、anime_api.dart、dandanplay_api.dart、settings_backup.dart、comic.dart
- **待完成**: 全面采用 `json_serializable` + `freezed`（P2-10）

### 9. 密码明文存储在 SharedPreferences — ✅ 已修复
- 引入 `flutter_secure_storage`，创建 `SecureCredentialStore`
- `InMemorySecureCredentialStore` 用于测试注入
- `migrateFromSharedPreferences()` 一次性迁移
- 创建 `test/test_helpers.dart` 统一测试 setUp/tearDown

---

## P2 — 轻度问题

### 10. 手写 JSON 解析 — 未开始
### 11. API 层 part/mixin 紧耦合 — 未开始
### 12. 无路由框架 — 未开始
### 13. 无国际化 — 未开始
### 14. 缓存-请求模式重复 — 未开始

### 15. 免责声明文本重复定义 — ✅ 已修复
- 提取 `appDisclaimerItems` + `appDisclaimerFooter` 到 `lib/pages/disclaimer_page.dart`
- 删除 `main.dart` 中的重复常量，改为导入共享模块

### 16. 登录过期对话框重复 — ✅ 已修复
- 提取 `showLoginExpiredDialog()` 到 `lib/widgets/login_expired_dialog.dart`
- 迁移 `browse_history_page.dart` 和 `bookshelf_page.dart`

### 17. `local_comics_page` 和 `local_anime_page` 结构高度相似 — 未开始

---

## P3 — 改进建议

### 18. `analysis_options.yaml` 过于宽松 — 未开始
### 19. `utils/` 目录混入 UI 组件 — 未开始
### 20. 测试覆盖稀疏 — 未开始
### 21. `Comic` 模型有两种 JSON 构造器 — 未开始

---

## 新增文件清单

| 文件 | 用途 |
|------|------|
| `lib/models/prefs_store.dart` | PrefsStore 基类 |
| `lib/models/reader_settings.dart` | 阅读器设置子存储 |
| `lib/models/danmaku_settings.dart` | 弹幕设置子存储 |
| `lib/models/comment_settings.dart` | 评论区设置子存储 |
| `lib/models/theme_settings.dart` | 主题/外观子存储 |
| `lib/models/network_settings.dart` | 网络配置子存储 |
| `lib/models/network_proxy_types.dart` | 代理枚举 |
| `lib/models/secure_credential_store.dart` | 安全凭证存储 |
| `lib/utils/services.dart` | 服务定位器 |
| `lib/utils/json_helpers.dart` | 安全 JSON 提取器 |
| `lib/widgets/comic_cover_card.dart` | 漫画封面卡片 |
| `lib/widgets/shimmer_skeleton.dart` | 加载骨架屏 |
| `lib/widgets/error_retry_view.dart` | 错误重试状态 |
| `lib/widgets/login_expired_dialog.dart` | 登录过期对话框 |
| `lib/pages/login_page.dart` | 登录页（从 profile_page 拆出） |
| `lib/pages/register_page.dart` | 注册页（从 profile_page 拆出） |
| `lib/pages/disclaimer_page.dart` | 免责声明页（从 profile_page 拆出） |
| `lib/pages/about_page.dart` | 关于页（从 profile_page 拆出） |
| `test/test_helpers.dart` | 测试辅助（安全存储注入） |
