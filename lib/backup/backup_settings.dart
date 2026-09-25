import 'dart:convert';

import '../models/secure_credential_store.dart';
import 'backup_preferences.dart';
import 'backup_schedule.dart';
import 'webdav_config.dart';

class BackupSettingsData {
  final WebDavConfig? connection;
  final WebDavCredentials credentials;

  /// WebDAV 总开关。关闭时整条远端链路停摆，也不展示任何连接配置。
  /// 从未动过开关时按「是否已保存过服务器」推断：老配置仍按开启对待。
  final bool webDavEnabled;
  final bool encrypted;
  final String? rememberedPassword;
  final BackupSchedule schedule;
  final DateTime? lastAutoBackupAt;

  const BackupSettingsData({
    this.connection,
    this.credentials = const WebDavCredentials(username: '', password: ''),
    this.webDavEnabled = false,
    this.encrypted = true,
    this.rememberedPassword,
    this.schedule = const BackupSchedule(),
    this.lastAutoBackupAt,
  });
}

/// backup_* is local-only user configuration, not business cache.
/// New secrets never enter SharedPreferences (existing account migration is
/// deliberately outside the scope of this feature).
class BackupSettings {
  static const configKey = 'backup_webdav_config_v1';
  static const enabledKey = 'backup_webdav_enabled';
  static const encryptionKey = 'backup_encryption_enabled';
  static const scheduleEnabledKey = 'backup_auto_enabled';
  static const scheduleValueKey = 'backup_auto_interval_value';
  static const scheduleUnitKey = 'backup_auto_interval_unit';
  static const lastAutoBackupKey = 'backup_auto_last_at';
  final BackupPreferences _preferences;
  final SecureCredentialStore _secrets;

  /// 本次运行内确认过的密码。未勾选「记住密码」时不落盘，只在内存里供
  /// 定时备份复用。
  String? _sessionPassword;
  String? get sessionPassword => _sessionPassword;

  BackupSettings({
    BackupPreferences? preferences,
    SecureCredentialStore? secrets,
  }) : _preferences = preferences ?? SharedBackupPreferences(),
       _secrets = secrets ?? SecureCredentialStore();

  Future<BackupSettingsData> load() async {
    final prefs = await _preferences.readAll();
    final raw = prefs[configKey];
    WebDavConfig? config;
    if (raw is String) {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic> && data['server'] is String) {
        final server = data['server'];
        final directory = data['directory'];
        config = WebDavConfig(
          serverUrl: server is String ? server : '',
          directory: directory is String ? directory : '',
          allowHttp: data['allowHttp'] == true,
        );
      }
    }
    var credentials = const WebDavCredentials(username: '', password: '');
    final secret = await _secrets.readWebDavCredentials();
    if (secret != null && config != null) {
      final data = jsonDecode(secret);
      // Bind credentials to the server address. Even an interrupted config
      // save cannot pair a previous password with a different destination.
      if (data is Map<String, dynamic> &&
          data['server'] == config.server.toString()) {
        final username = data['username'];
        final password = data['password'];
        credentials = WebDavCredentials(
          username: username is String ? username : '',
          password: password is String ? password : '',
        );
      }
    }
    // 写过的开关值说了算；从没动过时，已保存过服务器的老配置视为开启，
    // 全新用户（没有配置）才是关闭。
    final rawEnabled = prefs[enabledKey];
    final rawValue = prefs[scheduleValueKey];
    final rawLast = prefs[lastAutoBackupKey];
    // 单位不再被当前版本认识时，数值也一并回到默认，避免出现「10 天」这类
    // 从已删除单位直接换算出来的怪间隔。
    final unit = BackupSchedule.tryFromName(prefs[scheduleUnitKey]);
    return BackupSettingsData(
      connection: config,
      credentials: credentials,
      webDavEnabled: rawEnabled is bool ? rawEnabled : config != null,
      encrypted: prefs[encryptionKey] != false,
      rememberedPassword: await _secrets.readBackupPassword(),
      schedule: BackupSchedule(
        enabled: prefs[scheduleEnabledKey] == true,
        value: unit == null || rawValue is! int
            ? BackupSchedule.defaultValue
            : BackupSchedule.clampValue(rawValue),
        unit: unit ?? BackupIntervalUnit.days,
      ),
      lastAutoBackupAt: rawLast is int
          ? DateTime.fromMillisecondsSinceEpoch(rawLast)
          : null,
    );
  }

  /// 保存连接设置。凭据写在服务器地址之前：中途失败时，地址一变就认不出旧
  /// 密码（见 [load] 的绑定规则），不会出现密码配上新服务器的情况。
  Future<void> saveConnection(
    WebDavConfig config,
    WebDavCredentials credentials,
  ) async {
    if (credentials.username.contains(':') ||
        credentials.username.contains(RegExp(r'[\r\n]'))) {
      throw const WebDavException(WebDavErrorCode.invalidConfiguration);
    }
    await _secrets.writeWebDavCredentials(
      jsonEncode({
        'server': config.server.toString(),
        'username': credentials.username,
        'password': credentials.password,
      }),
    );
    await _preferences.write(
      configKey,
      jsonEncode({
        'server': config.server.toString(),
        'directory': config.directory,
        'allowHttp': config.allowHttp,
      }),
    );
    await saveEnabled(true);
  }

  Future<void> saveEnabled(bool enabled) =>
      _preferences.write(enabledKey, enabled);

  /// 清除连接设置：地址、账号密码，以及指向它的定时备份与上次运行时刻。
  /// 先删凭据再删地址：中途失败最坏只剩一个没有密码的地址，重填即可。
  ///
  /// 总开关显式写回开启：清空后停在「未设置服务器」的配置流程里（页面不用跳回
  /// 收起状态），也避免显式值缺失时按「没有配置」推断成关闭。
  Future<void> clearConnection() async {
    await _secrets.writeWebDavCredentials(null);
    final prefs = await _preferences.readAll();
    for (final key in [configKey, scheduleEnabledKey, lastAutoBackupKey]) {
      if (prefs.containsKey(key)) await _preferences.remove(key);
    }
    await _preferences.write(enabledKey, true);
  }

  Future<void> saveEncryption({
    required bool encrypted,
    required bool remember,
    required String password,
  }) async {
    _sessionPassword = password.isEmpty ? null : password;
    await _secrets.writeBackupPassword(remember ? password : null);
    await _preferences.write(encryptionKey, encrypted);
  }

  Future<void> saveSchedule(BackupSchedule schedule) async {
    await _preferences.write(
      scheduleValueKey,
      BackupSchedule.clampValue(schedule.value),
    );
    await _preferences.write(scheduleUnitKey, schedule.unit.name);
    await _preferences.write(scheduleEnabledKey, schedule.enabled);
  }

  /// 记下最近一次成功的定时备份时刻，跨进程重启后据此判断是否已到期。
  Future<void> markAutoBackup(DateTime at) =>
      _preferences.write(lastAutoBackupKey, at.millisecondsSinceEpoch);

  /// 可用的备份密码：记在安全存储里的优先，其次是本次运行内输入过的。
  Future<String?> activePassword() async =>
      (await _secrets.readBackupPassword()) ?? _sessionPassword;
}
