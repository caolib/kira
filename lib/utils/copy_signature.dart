import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// 拷贝漫画 App 通道的请求签名（`X-Auth-Timestamp` / `X-Auth-Signature`）。
///
/// 服务端按此算法校验，缺失或错误时不会报错，只是静默返回空数据
/// （HTTP 200 + `total: 0`），所以签名不是可选装饰。
///
/// 算法（见 `docs/` 内的接口逆向结论，已实测复现）：
/// - 时间戳：秒级，两次整除 1000 得到；
/// - 签名：`HMAC-SHA256(key: 密钥, message: 时间戳字符串)` 的 hex；
/// - 密钥：拷贝官方 APK 签名证书 DER 的 MD5 hex（32 位小写十六进制）。
///
/// 密钥**不写入仓库**：它是官方证书的指纹，属于协议常量而非本项目机密，
/// 但公开仓库里散落一份可被搜索引擎索引的副本没有必要。取值顺序见
/// [authKey]。
class CopySignature {
  CopySignature._();

  /// 编译期注入的密钥，来自 `--dart-define=COPY_AUTH_KEY=…`。
  static const _compiledKey = String.fromEnvironment('COPY_AUTH_KEY');

  /// 桌面调试时可直接读同名环境变量，省得每次构建都带 `--dart-define`。
  /// Android / iOS 不提供环境变量，那里只能靠编译期注入。
  static const _envKeyName = 'COPY_AUTH_KEY';

  static String? _cached;
  static bool _warnedMissing = false;

  /// 测试注入的密钥；非 null 时优先于缓存、编译期与环境变量。
  /// 空白值显式模拟未配置，null 则恢复正常取值，不改写生产缓存。
  @visibleForTesting
  static String? debugKeyOverride;

  /// 当前可用的签名密钥；未配置时返回 null（调用方据此降级）。
  ///
  /// 优先测试注入，其次编译期 `--dart-define`，最后桌面环境变量。首次
  /// 调用时结果会被缓存 —— 环境变量不会在进程内变化，反复读没有意义。
  static String? get authKey {
    final override = debugKeyOverride?.trim();
    if (override != null) return override.isEmpty ? null : override;
    if (_cached != null) return _cached;
    final compiled = _compiledKey.trim();
    if (compiled.isNotEmpty) return _cached = compiled;
    if (!Platform.isAndroid && !Platform.isIOS) {
      final fromEnv = Platform.environment[_envKeyName]?.trim();
      if (fromEnv != null && fromEnv.isNotEmpty) return _cached = fromEnv;
    }
    return null;
  }

  /// 是否已配置密钥。未配置时接口签名无法通过校验，登录必然失败，
  /// 调用方应给出明确提示而不是让用户面对「账号密码都对却登不上」。
  static bool get isConfigured => authKey != null;

  /// 本次进程是否已经就「密钥缺失」提醒过一次，避免刷屏。
  static bool markMissingKeyReported() {
    if (_warnedMissing) return false;
    _warnedMissing = true;
    return true;
  }

  /// 签名头：`X-Auth-Timestamp` + `X-Auth-Signature`。
  ///
  /// 时间戳按秒取整，键缺失时抛 [StateError] —— 静默发送无效签名只会让
  /// 服务端返回空数据，比直接失败更难排查。
  static Map<String, String> headers({DateTime? now}) {
    final key = authKey;
    if (key == null) {
      throw StateError(
        'COPY auth key is not configured '
        '(pass --dart-define=$_envKeyName=… at build time)',
      );
    }
    final timestamp =
        ((now ?? DateTime.now()).microsecondsSinceEpoch ~/ 1000 ~/ 1000)
            .toString();
    return {
      'X-Auth-Timestamp': timestamp,
      'X-Auth-Signature': sign(timestamp, key: key),
    };
  }

  /// `HMAC-SHA256(key, message)` 的 hex 摘要。独立成公开函数便于测试。
  static String sign(String message, {required String key}) {
    return Hmac(
      sha256,
      utf8.encode(key),
    ).convert(utf8.encode(message)).toString();
  }

  /// `umstring` 头 = `MD5(密钥)` 的 hex（32 位）。
  ///
  /// 与签名同源但用途不同：签名逐请求校验，umstring 是稳定的来源指纹，
  /// 服务端不校验它（实测用假 umstring 配真签名仍能正常取数据）。密钥缺失
  /// 时为 null，调用方跳过该头。
  static String? get umString {
    final key = authKey;
    if (key == null) return null;
    return md5.convert(utf8.encode(key)).toString();
  }

  /// 16 位 `[0-9A-Za-z]` 伪设备标识（`pseudoid` 头），生成规则与官方 App
  /// 一致：进程启动时随机一次，之后所有请求复用同一个值。
  static String pseudoId() => _pseudoId ??= _randomPseudoId();

  static String? _pseudoId;

  static const _pseudoAlphabet =
      '0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  static String _randomPseudoId() {
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < 16; i++)
        _pseudoAlphabet.codeUnitAt(random.nextInt(_pseudoAlphabet.length)),
    ]);
  }
}
