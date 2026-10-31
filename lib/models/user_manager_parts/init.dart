part of '../user_manager.dart';

extension UserManagerInitPart on UserManager {
  Future<void> init({bool persistMigrations = true}) async {
    final revision = ++_accountRevision;
    await _pendingAccountMutation;
    final prefs = await SharedPreferences.getInstance();
    if (revision != _accountRevision) return;
    _username = prefs.getString(UserManager._keyUsername);
    _nickname = prefs.getString(UserManager._keyNickname);
    _avatar = prefs.getString(UserManager._keyAvatar);
    _userId = prefs.getString(UserManager._keyUserId);
    final accountId = prefs.getString(UserManager._keyAccountId)?.trim();
    _accountId = accountId?.isNotEmpty == true ? accountId : null;
    // The credential store alone chooses current records versus legacy aliases.
    // A read-only reload must use the same values without migrating anything.
    try {
      await readAccountStorage(
        () => _loadCredentials(prefs, persistMigrations, revision),
      );
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'user_manager.init_credentials',
        ),
      );
    }
    if (revision != _accountRevision) return;
    _desktopFontFamily =
        prefs.getString(UserManager._keyDesktopFontFamily) ?? '';
    _bookshelfOrdering =
        prefs.getString(UserManager._keyBookshelfOrdering) ??
        ApiOrdering.datetimeUpdated;
    _readerHorizontalImageScale =
        (prefs.getDouble(UserManager._keyReaderHorizontalImageScale) ?? 1.0)
            .clamp(0.7, 1.0);
    _autoCheckUpdate = prefs.getBool(UserManager._keyAutoCheckUpdate) ?? true;
    _skippedUpdateVersion = prefs.getString(
      UserManager._keySkippedUpdateVersion,
    );
    _updateMirrorPrefix = UserManager.normalizeUpdateMirrorPrefix(
      prefs.getString(UserManager._keyUpdateMirrorPrefix),
    );
    _updateChannel = prefs.getString(UserManager._keyUpdateChannel) == 'beta'
        ? 'beta'
        : 'stable';
    _useUpdateMirror = prefs.getBool(UserManager._keyUseUpdateMirror) ?? true;
    {
      // 自定义镜像源：规范化后去重（与内置重复的一律丢弃），非法值会被
      // normalize 折成默认地址，同样落在内置项里而被过滤掉。
      final raw =
          prefs.getStringList(UserManager._keyUpdateMirrorCustomPrefixes) ??
          const <String>[];
      final custom = <String>[];
      for (final value in raw) {
        final prefix = UserManager.normalizeUpdateMirrorPrefix(value);
        if (custom.contains(prefix) ||
            UserManager.updateMirrorPrefixOptions.contains(prefix)) {
          continue;
        }
        custom.add(prefix);
      }
      // 旧版本把自定义镜像只写在 update_mirror_prefix 里，没有列表：并入
      // 后它才可见、可删除、可继续参与兜底，而不是一切换预设就消失。
      if (!UserManager.updateMirrorPrefixOptions.contains(
            _updateMirrorPrefix,
          ) &&
          !custom.contains(_updateMirrorPrefix)) {
        custom.add(_updateMirrorPrefix);
      }
      _customUpdateMirrorPrefixes = custom;
      // 规范化或并入改变了内容才回写，避免每次启动都写一次 prefs。
      var unchanged = custom.length == raw.length;
      for (var i = 0; unchanged && i < custom.length; i++) {
        unchanged = custom[i] == raw[i];
      }
      if (persistMigrations && !unchanged) {
        await prefs.setStringList(
          UserManager._keyUpdateMirrorCustomPrefixes,
          custom,
        );
      }
    }
    _disclaimerAccepted =
        prefs.getBool(UserManager._keyDisclaimerAccepted) ?? false;
    _loginSource = prefs.getString(UserManager._keyLoginSource) ?? 'hotmanga';
    _savedCredentials = [
      for (final credential in _savedCredentials)
        credential.loginSource == null
            ? credential.copyWith(
                loginSource: credential.username == _savedUsername
                    ? _loginSource
                    : 'hotmanga',
              )
            : credential,
    ];
    if (_loginSource == 'copy' &&
        isLoggedIn &&
        _accountId?.isNotEmpty != true) {
      final known = _savedCredentials
          .where((item) => item.source == 'copy' && item.token == _token)
          .firstOrNull;
      _accountId =
          known?.accountId ??
          CopyAccountSession.identityOf(
            userId: _userId ?? '',
            username: _username ?? '',
          );
    }
    _remoteNoticeEnabled =
        prefs.getBool(UserManager._keyRemoteNoticeEnabled) ?? true;
    _locale = prefs.getString(UserManager._keyLocale) ?? '';
    _mangaHomeSource =
        prefs.getString(UserManager._keyMangaHomeSource) ?? 'hot';
    _discoverSource = prefs.getString(UserManager._keyDiscoverSource) ?? 'hot';
    _searchTabIndex = (prefs.getInt(UserManager._keySearchTabIndex) ?? 0).clamp(
      0,
      1,
    );
    _copyApiHost = UserManager.normalizeCopyApiHost(
      prefs.getString(UserManager._keyCopyApiHost),
    );
    _copyLoginHost = UserManager.normalizeCopyLoginHost(
      prefs.getString(UserManager._keyCopyLoginHost),
    );
    {
      // 自定义登录域名：仅去空白、去重（含与内置重复），不校验合法性。
      final custom = <String>[];
      for (final raw
          in prefs.getStringList(UserManager._keyCustomCopyLoginHosts) ??
              const <String>[]) {
        final host = raw.trim();
        if (host.isEmpty ||
            custom.contains(host) ||
            copyLoginHostOptions.contains(host)) {
          continue;
        }
        custom.add(host);
      }
      _customCopyLoginHosts = custom;
      // 历史内置域名（如 www.mangacopy.com）曾被选为当前域名，内置列表
      // 收窄后不再包含它们——并入自定义列表，保持可见、可切换、可删除。
      // 仅内存合并即可：copyLoginHost 持久不变，下次 init 会重新推导。
      if (!copyLoginHostOptions.contains(_copyLoginHost) &&
          !_customCopyLoginHosts.contains(_copyLoginHost)) {
        _customCopyLoginHosts = [..._customCopyLoginHosts, _copyLoginHost];
      }
    }
    _copyAppVersion = UserManager.normalizeCopyAppVersion(
      prefs.getString(UserManager._keyCopyAppVersion),
    );
    _copyVersionCode = UserManager.normalizeCopyVersionCode(
      prefs.getString(UserManager._keyCopyVersionCode),
    );
    _copyAutoUpdate = prefs.getBool(UserManager._keyCopyAutoUpdate) ?? true;
    _copySettingsUpdatedAt = prefs.getInt(
      UserManager._keyCopySettingsUpdatedAt,
    );
    _copyHomeSectionCollapsed = UserManager._decodeBoolMap(
      prefs.getString(UserManager._keyCopyHomeSectionCollapsed),
    );
    _commentBlockedUsers =
        prefs.getStringList(UserManager._keyCommentBlockedUsers) ?? [];
    _commentBlockNoRemind =
        prefs.getBool(UserManager._keyCommentBlockNoRemind) ?? false;
    _commentBlockwords =
        prefs.getStringList(UserManager._keyCommentBlockwords) ?? [];
    _commentBlockGroupSpam =
        prefs.getBool(UserManager._keyCommentBlockGroupSpam) ?? false;
    // Initialize domain-specific sub-stores with the same prefs instance.
    await general.initFromPrefs(prefs);
    await reader.initFromPrefs(prefs);
    // 小说状态组件 store 依赖漫画侧已就绪（首启继承其现值）。
    await novelStatus.initFromPrefs(prefs);
    await comment.initFromPrefs(prefs);
    await theme.initFromPrefs(prefs, persistMigrations: persistMigrations);
    await network.initFromPrefs(prefs, persistMigrations: persistMigrations);
    // loginSource is loaded late above; never infer COPY from token presence.
    if (revision != _accountRevision) return;
    _beginCopyAccountSuppression();
    try {
      await readAccountStorage(
        () => _initCopyAccounts(
          persistMigrations: persistMigrations,
          revision: revision,
        ),
      );
    } catch (_) {
      unawaited(
        AppLogger.instance.recordWarning(
          const CopyAccountStorageException(),
          source: 'user_manager.init_accounts',
        ),
      );
    } finally {
      _endCopyAccountSuppression();
    }
    if (revision != _accountRevision) return;

    // Forward sub-store notifications so legacy listeners on UserManager
    // still rebuild when domain settings change. init() may run more than once
    // (导入备份 / 清除数据后重载),而 ChangeNotifier.addListener 会重复登记
    // 同一闭包,故先移除再添加,避免通知被放大。
    general.removeListener(_onSubStoreChanged);
    reader.removeListener(_onSubStoreChanged);
    novelStatus.removeListener(_onSubStoreChanged);
    comment.removeListener(_onSubStoreChanged);
    theme.removeListener(_onSubStoreChanged);
    network.removeListener(_onSubStoreChanged);
    copyAccount.removeListener(_onCopyAccountChanged);
    general.addListener(_onSubStoreChanged);
    reader.addListener(_onSubStoreChanged);
    novelStatus.addListener(_onSubStoreChanged);
    comment.addListener(_onSubStoreChanged);
    theme.addListener(_onSubStoreChanged);
    network.addListener(_onSubStoreChanged);
    copyAccount.addListener(_onCopyAccountChanged);

    _notifyListeners();
  }

  /// Migration copies raw legacy values; loading and normalization never write
  /// them back. A failed migration must not hide a current value or tombstone.
  /// Publish a complete snapshot only while this initialization is still current.
  Future<void> _loadCredentials(
    SharedPreferences prefs,
    bool persistMigrations,
    int revision,
  ) async {
    if (revision != _accountRevision) return;
    final secure = SecureCredentialStore();
    if (persistMigrations) {
      try {
        await secure.migrateFromSharedPreferences(
          {for (final key in prefs.getKeys()) key: prefs.get(key)},
          (key) async {
            try {
              await _requireAccountWrite(prefs.remove(key));
            } catch (error, stack) {
              await prefs.reload();
              Error.throwWithStackTrace(error, stack);
            }
          },
        );
      } catch (error, stack) {
        unawaited(
          AppLogger.instance.recordWarning(
            error,
            stackTrace: stack,
            source: 'user_manager.migrate_credentials',
          ),
        );
      }
    }
    if (revision != _accountRevision) return;
    final token = await secure.readToken();
    final username = await secure.readUsername();
    final password = await secure.readPassword();
    final credentials = await secure.readCredentials();
    final hasCredentialsRecord = await secure.hasCredentialsRecord();
    if (revision != _accountRevision) return;
    _token = token?.isNotEmpty == true ? token : null;
    _savedUsername = username;
    _savedPassword = password;
    _savedCredentials = credentials;
    if (!hasCredentialsRecord &&
        _savedCredentials.isEmpty &&
        username?.isNotEmpty == true &&
        password != null) {
      _savedCredentials = [
        SavedCredential(username: username!, password: password),
      ];
    }
  }
}
