/// Network proxy enums, shared between UserManager and NetworkSettings.
///
/// Extracted from user_manager.dart to avoid circular dependencies
/// when domain stores need to reference these types.
library;

enum NetworkProxyMode { system, manual }

enum NetworkProxyType { http, socks }
