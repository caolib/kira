/// Network proxy enums, shared between UserManager and NetworkSettings.
///
/// Extracted from user_manager.dart to avoid circular dependencies
/// when domain stores need to reference these types.
library;

/// 代理模式。
/// - [system]: 跟随系统代理（Wi-Fi 代理 / 注册表 / 环境变量）。
/// - [manual]: 使用用户手动填写的代理地址。
/// - [direct]: 直连，忽略系统代理。
///
/// 枚举索引会持久化到 SharedPreferences（键 `network_proxy_mode`），
/// 新增模式只能追加在末尾，否则旧数据会读成别的模式。
enum NetworkProxyMode { system, manual, direct }

enum NetworkProxyType { http, socks }
