part of '../user_manager.dart';

class SavedCredential {
  final String username;
  final String password;
  final String? token;
  final String? loginSource;
  final String? userId;
  final String? nickname;
  final String? avatar;
  final String? accountId;
  final Map<String, dynamic> _extraFields;

  static const _knownFields = {
    'username',
    'password',
    'token',
    'login_source',
    'user_id',
    'nickname',
    'avatar',
    'account_id',
  };

  const SavedCredential({
    required this.username,
    required this.password,
    this.token,
    this.loginSource,
    this.userId,
    this.nickname,
    this.avatar,
    this.accountId,
    Map<String, dynamic> extraFields = const {},
  }) : _extraFields = extraFields;

  factory SavedCredential.fromJson(Map<String, dynamic> json) =>
      SavedCredential(
        username: json['username']?.toString() ?? '',
        password: json['password']?.toString() ?? '',
        token: json['token'] is String ? json['token'] : null,
        loginSource: json['login_source']?.toString(),
        userId: json['user_id']?.toString(),
        nickname: json['nickname']?.toString(),
        avatar: json['avatar']?.toString(),
        accountId: switch (json['account_id']) {
          final String value when value.trim().isNotEmpty => value.trim(),
          _ => null,
        },
        extraFields: Map.unmodifiable({
          for (final entry in json.entries)
            if (!_knownFields.contains(entry.key)) entry.key: entry.value,
        }),
      );

  Map<String, dynamic> toJson() => {
    ..._extraFields,
    'username': username,
    'password': password,
    if (token != null) 'token': token,
    if (loginSource != null) 'login_source': loginSource,
    if (userId != null) 'user_id': userId,
    if (nickname != null) 'nickname': nickname,
    if (avatar != null) 'avatar': avatar,
    if (accountId != null) 'account_id': accountId,
  };

  String get source => loginSource == 'copy' ? 'copy' : 'hotmanga';

  bool get hasIdentity =>
      username.trim().isNotEmpty || userId?.trim().isNotEmpty == true;

  /// A local COPY handle supports token-only accounts without inventing a
  /// server identity. Password-only legacy credentials still need a name.
  bool get hasAccountKey =>
      hasIdentity ||
      (source == 'copy' &&
          accountId?.trim().isNotEmpty == true &&
          token?.trim().isNotEmpty == true);

  AccountIdentity get identity => AccountIdentity(
    source: source,
    username: username,
    userId: userId,
    token: token,
    accountId: accountId,
  );

  /// Same-source nonempty login names are authoritative; incomplete identities
  /// may use a trusted user id, token or existing binding, never display data.
  bool sameAccount(SavedCredential other) => identity.matches(other.identity);

  SavedCredential copyWith({
    String? username,
    String? password,
    String? token,
    String? loginSource,
    String? userId,
    String? nickname,
    String? avatar,
    String? accountId,
    Map<String, dynamic>? extraFields,
  }) => SavedCredential(
    username: username ?? this.username,
    password: password ?? this.password,
    token: token ?? this.token,
    loginSource: loginSource ?? this.loginSource,
    userId: userId ?? this.userId,
    nickname: nickname ?? this.nickname,
    avatar: avatar ?? this.avatar,
    accountId: accountId ?? this.accountId,
    extraFields: extraFields ?? _extraFields,
  );
}

/// 登录与凭据域。
///
/// 这里的成员是 extension 成员，不是 [UserManager] 自身的成员：`implements
/// UserManager` 的测试替身无法覆盖它们，调用会落到宿主实现去读私有字段并抛
/// NoSuchMethodError。所以替身测试只能测页面读到的设置类接口（[isLoggedIn]、
/// copyToken 等），凭据 API 只允许对真实例调用。同理，本文件也不能调用其它
/// part 里的成员——共用的（[readAccountStorage]、[_persistProfile] 等）留在宿主。
extension UserManagerCredentialsPart on UserManager {
  /// All explicit logins share one commit path: COPY adds to both domains;
  /// HOT adds to comics only. A login never takes over an already selected
  /// domain (see [_commitLogin]). Reserve revisions before network work so an
  /// old response cannot undo a newer login, logout or manual selection.
  Future<bool> authenticateAndLogin({
    required String source,
    required Future<Map<String, dynamic>> Function() authenticate,
    String? password,
    bool syncCopyAccount = true,
    bool fillOnlyIfEmpty = true,
  }) async {
    final revision = ++_accountRevision;
    final copyRevision = source == 'copy' && syncCopyAccount
        ? copyAccount.beginLogin()
        : null;
    final result = await authenticate();
    if (revision != _accountRevision ||
        (copyRevision != null && copyRevision != copyAccount.revision)) {
      return false;
    }
    final token = result['token'];
    if (token is! String || token.trim().isEmpty) {
      throw const FormatException('Login response lacks a valid token');
    }
    final account = SavedCredential(
      username: result['username']?.toString().trim() ?? '',
      password: '',
      token: token.trim(),
      loginSource: source,
      userId: result['user_id']?.toString().trim(),
      nickname: result['nickname']?.toString(),
      avatar: result['avatar']?.toString(),
      accountId: result['account_id'] is String ? result['account_id'] : null,
    );
    return _serializeAccounts(
      () => _commitLogin(
        account,
        revision: revision,
        copyRevision: copyRevision,
        password: password,
        fillOnlyIfEmpty: fillOnlyIfEmpty,
      ),
    );
  }

  Future<void> saveLogin({
    required String token,
    required String userId,
    required String username,
    required String nickname,
    required String avatar,
    bool syncCopyAccount = false,
    int? copyAccountRevision,
    String? loginSource,
    bool fillOnlyIfEmpty = true,
  }) async {
    final revision = ++_accountRevision;
    final source = loginSource ?? _loginSource;
    final copyRevision = syncCopyAccount && source == 'copy'
        ? (copyAccountRevision ?? copyAccount.beginLogin())
        : null;
    await _serializeAccounts(
      () => _commitLogin(
        SavedCredential(
          username: username,
          password: '',
          token: token,
          loginSource: source,
          userId: userId,
          nickname: nickname,
          avatar: avatar,
        ),
        revision: revision,
        copyRevision: copyRevision,
        fillOnlyIfEmpty: fillOnlyIfEmpty,
      ),
    );
  }

  SavedCredential _resolveCopyCredential(SavedCredential account) {
    final merged = _mergeCredentials([
      account,
      ?_currentWithPassword,
      ..._savedCredentials,
    ], incoming: account);
    final known = merged.forAccount(account)!;
    // Resolve before either domain writes: existing COPY handles win over an
    // incoming token-only handle. A new unknown token borrows no current user.
    final session = copyAccount.resolveSession(_copySession(known));
    return _copyCredential(
      session,
    ).copyWith(password: known.password, extraFields: known._extraFields);
  }

  Future<bool> _commitLogin(
    SavedCredential account, {
    required int revision,
    int? copyRevision,
    String? password,
    bool fillOnlyIfEmpty = false,
    bool preserveSelection = false,
    List<SavedCredential>? retainedCredentials,
  }) async {
    final copyGuard = account.source == 'copy'
        ? (copyRevision ?? copyAccount.revision)
        : null;
    bool isCurrent() =>
        revision == _accountRevision &&
        (copyGuard == null || copyGuard == copyAccount.revision);
    if (!isCurrent()) return false;
    if (account.token?.trim().isNotEmpty != true ||
        (account.source != 'copy' && !account.hasIdentity)) {
      throw const FormatException('Invalid login account');
    }
    if (account.source == 'copy') account = _resolveCopyCredential(account);
    final current = currentCredential;
    final currentWithPassword = _currentWithPassword;
    final selectNovel =
        !preserveSelection &&
        (!fillOnlyIfEmpty || copyAccount.activeId == null);
    final incoming = account.copyWith(password: password ?? account.password);
    final projectedCopy = account.source == 'copy'
        ? copyAccount.previewSession(
            _copySession(incoming),
            select: selectNovel,
          )
        : null;
    final primaryMerge = _mergeCredentials(
      [
        incoming,
        ?currentWithPassword,
        ...(retainedCredentials ?? _savedCredentials),
      ],
      incoming: incoming,
      overwriteIncomingPassword: password != null,
      preferred: currentWithPassword,
      // Only this explicitly synchronized COPY identity may project a token.
      // Unrelated/HOT operations must preserve a read-only restored domain.
      copyAccounts: projectedCopy?.incoming == null
          ? const []
          : [projectedCopy!.incoming!],
    );
    final next = primaryMerge.accounts;
    final updated = primaryMerge.forAccount(incoming)!;
    final mergedCurrent = primaryMerge.forAccount(currentWithPassword);
    // Compare actual groups, not a possibly ambiguous fallback-id match.
    final sameAsCurrent = identical(mergedCurrent, updated);
    final selectPrimary = preserveSelection
        ? sameAsCurrent
        : !fillOnlyIfEmpty || current == null || sameAsCurrent;
    final primary = selectPrimary ? updated : mergedCurrent;
    final writePrimary =
        selectPrimary ||
        (current?.source == 'copy' &&
            primary != null &&
            jsonEncode(current!.toJson()) !=
                jsonEncode(primary.copyWith(password: '').toJson()));
    final secure = SecureCredentialStore();
    final prefs = await SharedPreferences.getInstance();
    // Read the actual stored snapshot: a read-only reload may have normalized
    // the in-memory list while intentionally leaving historical rows on disk.
    final previousRecord = await secure.readCredentialsRecord();
    final previousUsername = await secure.readUsername();
    final previousPassword = await secure.readPassword();
    final previousToken = await secure.readToken();
    final previousProfile = {
      for (final key in [
        ...UserManager._profileKeys,
        UserManager._keyToken,
        UserManager._keySavedCredentials,
        UserManager._keySavedUsername,
        UserManager._keySavedPassword,
      ])
        key: prefs.getString(key),
    };

    Future<void> restorePrimary() async {
      await secure.writeCredentialsRecord(previousRecord);
      await secure.writeUsername(previousUsername);
      await secure.writePassword(previousPassword);
      await secure.writeToken(previousToken);
      for (final entry in previousProfile.entries) {
        final value = entry.value;
        await _requireAccountWrite(
          value == null
              ? prefs.remove(entry.key)
              : prefs.setString(entry.key, value),
        );
      }
    }

    void publishPrimary() {
      _savedCredentials = next;
      // 已登录的漫画账号不被新登录顶掉：新账号只入库，保持当前选择。
      if (!writePrimary || primary == null) return;
      _savedUsername = primary.username;
      _savedPassword = primary.password;
      _token = primary.token;
      _userId = primary.userId;
      _accountId = primary.accountId;
      _username = primary.username;
      _nickname = primary.nickname;
      _avatar = primary.avatar;
      _loginSource = primary.source;
      ApiClient().user.clearAuthState();
    }

    _beginCopyAccountSuppression();
    try {
      await secure.writeCredentials(next);
      // 只入库不切换时，主账号的令牌与资料槽位保持原样；同身份归并则同步
      // 其稳定绑定和令牌，不改变当前漫画账号所属的人或来源。
      if (writePrimary && primary != null) {
        await secure.writeUsername(primary.username);
        await secure.writePassword(primary.password);
        await secure.writeToken(primary.token);
        await _persistProfile(primary);
      }
      for (final key in [
        UserManager._keyToken,
        UserManager._keySavedCredentials,
        UserManager._keySavedUsername,
        UserManager._keySavedPassword,
      ]) {
        await _requireAccountWrite(prefs.remove(key));
      }
      if (!isCurrent()) {
        await restorePrimary();
        return false;
      }
      if (copyRevision != null) {
        final saved = await copyAccount.saveSession(
          CopyAccountSession(
            token: updated.token!,
            userId: updated.userId ?? '',
            username: updated.username,
            nickname: updated.nickname ?? '',
            avatar: updated.avatar ?? '',
            accountId: updated.accountId,
          ),
          expectedRevision: copyRevision,
          isCurrent: isCurrent,
          select: selectNovel,
          onCommitted: publishPrimary,
        );
        if (!saved) {
          await restorePrimary();
          return false;
        }
      } else {
        // No COPY revision: auto-relogin and manual comic selection must not
        // switch the novel account. But an already stored identity has to
        // follow its rotated token, or the independent list keeps the
        // invalidated token while the primary moves on — 账号中心 then
        // renders the same account twice and novel requests keep failing.
        final copyId = updated.accountId;
        if (updated.source == 'copy' &&
            copyId != null &&
            copyAccount.byId(copyId) != null) {
          final synced = await copyAccount.syncSessionToken(
            id: copyId,
            session: CopyAccountSession(
              token: updated.token!,
              userId: updated.userId ?? '',
              username: updated.username,
              nickname: updated.nickname ?? '',
              avatar: updated.avatar ?? '',
            ),
            expectedRevision: copyGuard,
            isCurrent: () => revision == _accountRevision,
            onCommitted: (_) => publishPrimary(),
          );
          if (!synced) {
            await restorePrimary();
            return false;
          }
        } else {
          publishPrimary();
        }
      }
      _notifySuppressedCommit();
      return true;
    } catch (_) {
      try {
        await restorePrimary();
      } catch (_) {
        unawaited(
          AppLogger.instance.recordWarning(
            const CopyAccountStorageException(),
            source: 'user_manager.restore_login',
          ),
        );
      }
      // Storage failure cannot masquerade as a completed COPY login while the
      // novel account is still empty (the original partial-success bug).
      throw const CopyAccountStorageException();
    } finally {
      _endCopyAccountSuppression();
    }
  }

  Future<void> logout() {
    ++_accountRevision;
    return _serializeAccounts(() async {
      await SecureCredentialStore().writeToken(null);
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        UserManager._keyToken,
        UserManager._keyAccountId,
        UserManager._keyUserId,
        UserManager._keyUsername,
        UserManager._keyNickname,
        UserManager._keyAvatar,
      ]) {
        await prefs.remove(key);
      }
      ApiClient().user.clearAuthState();
      _token = null;
      _userId = null;
      _accountId = null;
      _username = null;
      _nickname = null;
      _avatar = null;
      _notifyListeners();
    });
  }

  /// 把官网登录表单里抓到的用户名/密码并回本机凭据。
  ///
  /// 官网 cookie 常常没有登录名，所以只对「用户名匹配、或用户名尚为空」的
  /// 账号写入；写入失败只记日志，不影响已经完成的登录。
  ///
  /// [anchorToken] 用于自动填表登录：kira 侧明确知道提交的账号密码，登录
  /// 成功后该 token 对应的账号就是本次登录的账号，直接按 token 锚定写入，
  /// 不再要求用户名对得上（新落库的 token-only 账号用户名是空的）。
  Future<void> saveLoginFormPasswords(
    Map<String, String> passwords, {
    String? anchorToken,
  }) async {
    if (passwords.isEmpty) return;
    try {
      await _serializeAccounts(() async {
        var changed = false;
        SavedCredential? anchoredUpdate;
        final next = <SavedCredential>[];
        for (final credential in _savedCredentials) {
          CopyWebLoginForm? match;
          var anchored = false;
          if (credential.source == 'copy') {
            if (anchorToken != null && credential.token == anchorToken) {
              anchored = true;
              for (final entry in passwords.entries) {
                if (entry.value.isNotEmpty) {
                  match = CopyWebLoginForm(
                    username: entry.key,
                    password: entry.value,
                  );
                  break;
                }
              }
            } else {
              for (final entry in passwords.entries) {
                final form = CopyWebLoginForm(
                  username: entry.key,
                  password: entry.value,
                );
                if (canApplyLoginForm(
                  accountUsername: credential.username,
                  accountNickname: credential.nickname ?? '',
                  formUsername: form.username,
                  password: form.password,
                )) {
                  match = form;
                  break;
                }
              }
            }
          }
          final form = match;
          if (form == null) {
            next.add(credential);
            continue;
          }
          // 自动填表登录时表单里的账号名就是登录名，顺手补上，登录页与账号
          // 中心才能按名字回填；已有登录名不覆盖，身份仍以 token 为准。
          final fillsLoginName =
              anchored &&
              credential.username.isEmpty &&
              form.username.isNotEmpty;
          if (credential.password == form.password && !fillsLoginName) {
            next.add(credential);
            continue;
          }
          changed = true;
          final updated = credential.copyWith(
            username: fillsLoginName ? form.username : null,
            password: form.password,
          );
          next.add(updated);
          if (anchored) anchoredUpdate = updated;
        }
        if (!changed) return;
        final anchored = anchoredUpdate;
        if (anchored != null) {
          final stored = copyAccount.accounts.any(
            (item) => item.identity.matches(anchored.identity),
          );
          await _commitLogin(
            anchored,
            revision: _accountRevision,
            copyRevision: stored ? copyAccount.beginLogin() : null,
            password: anchored.password,
            preserveSelection: true,
            retainedCredentials: next,
          );
          return;
        }
        final reconciled = _mergeCredentials(
          next,
          preferred: currentCredential,
        ).accounts;
        await SecureCredentialStore().writeCredentials(reconciled);
        _savedCredentials = reconciled;
        final active = currentCredential;
        if (active != null) {
          for (final credential in reconciled) {
            if (credential.sameAccount(active) &&
                credential.password.isNotEmpty) {
              _savedPassword = credential.password;
              // 自动重登读的是这个槽位，不写的话重启后就丢了。
              await SecureCredentialStore().writePassword(credential.password);
              break;
            }
          }
        }
        _notifyListeners();
      });
    } catch (_, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          StateError('Unable to save COPY web login password'),
          stackTrace: st,
          source: 'user_manager.save_login_form',
        ),
      );
    }
  }

  Future<void> saveCredentials(
    String username,
    String password, {
    String? loginSource,
  }) {
    ++_accountRevision;
    final source = loginSource ?? _loginSource;
    return _serializeAccounts(() async {
      final identity = SavedCredential(
        username: username,
        password: password,
        loginSource: source,
      );
      final merged = _mergeCredentials(
        [identity, ..._savedCredentials],
        incoming: identity,
        overwriteIncomingPassword: true,
      );
      final next = merged.accounts;
      final saved = merged.forAccount(identity)!;
      await SecureCredentialStore().writeCredentials(next);
      await SecureCredentialStore().writeUsername(username);
      await SecureCredentialStore().writePassword(saved.password);
      _savedUsername = username;
      _savedPassword = saved.password;
      _savedCredentials = next;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(UserManager._keySavedUsername);
      await prefs.remove(UserManager._keySavedPassword);
      await prefs.remove(UserManager._keySavedCredentials);
      _notifyListeners();
    });
  }

  Future<void> clearCredentials() {
    ++_accountRevision;
    return _serializeAccounts(() async {
      await SecureCredentialStore().writeCredentials([]);
      await SecureCredentialStore().writeUsername(null);
      await SecureCredentialStore().writePassword(null);
      _savedUsername = null;
      _savedPassword = null;
      _savedCredentials = [];
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(UserManager._keySavedUsername);
      await prefs.remove(UserManager._keySavedPassword);
      await prefs.remove(UserManager._keySavedCredentials);
      _notifyListeners();
    });
  }

  // Kept for legacy callers; account-center UI no longer creates notes.
  void setCopyAccountLabel(String? label) {
    _copyAccountLabel = label?.trim() ?? '';
  }

  String? consumeCopyAccountLabel() {
    final label = _copyAccountLabel;
    _copyAccountLabel = '';
    return label.isEmpty ? null : label;
  }

  Future<bool> switchToCredential(SavedCredential credential) {
    if (credential.token?.isNotEmpty != true || !credential.hasAccountKey) {
      return Future.value(false);
    }
    final revision = ++_accountRevision;
    // Local comic selection must not switch the independent novel account.
    return _serializeAccounts(
      () => _commitLogin(
        credential,
        revision: revision,
        password: credential.password.isEmpty ? null : credential.password,
      ),
    );
  }

  Future<void> removeSavedCredential(
    String username, {
    String? loginSource,
    String? userId,
    String? accountId,
    String? token,
  }) {
    ++_accountRevision;
    final source = loginSource ?? _loginSource;
    final identity = SavedCredential(
      username: username,
      password: '',
      loginSource: source,
      userId: userId,
      accountId: accountId,
      token: token,
    );
    bool matches(SavedCredential item) {
      if (source != item.source) return false;
      if (item.sameAccount(identity)) return true;
      if (item.username.trim().isNotEmpty && username.trim().isNotEmpty) {
        return false;
      }
      if (source == 'copy' && accountId?.isNotEmpty == true) {
        final key =
            item.accountId ??
            CopyAccountSession.identityOf(
              userId: item.userId ?? '',
              username: item.username,
            );
        return key == accountId ||
            (token?.isNotEmpty == true && item.token == token);
      }
      return item.sameAccount(identity);
    }

    return _serializeAccounts(() async {
      final next = _savedCredentials.where((item) => !matches(item)).toList();
      await SecureCredentialStore().writeCredentials(next);
      final selected = next.where(
        (item) => currentCredential?.sameAccount(item) == true,
      );
      final replacement = selected.isNotEmpty
          ? selected.first
          : (next.isNotEmpty ? next.first : null);
      await SecureCredentialStore().writeUsername(replacement?.username);
      await SecureCredentialStore().writePassword(replacement?.password);
      _savedCredentials = next;
      _savedUsername = replacement?.username;
      _savedPassword = replacement?.password;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(UserManager._keySavedCredentials);
      await prefs.remove(UserManager._keySavedUsername);
      await prefs.remove(UserManager._keySavedPassword);
      _notifyListeners();
    });
  }

  /// Fetch and apply profile data for the exact stored COPY account. The
  /// request does not change selection; late responses are discarded if either
  /// account domain changes while it is in flight.
  Future<bool> refreshCopyCredential(
    CopyAccountSession credential, {
    required UserApi api,
  }) async {
    final token = credential.token;
    final id = credential.id;
    if (token.isEmpty || id == null) return false;
    final revision = _accountRevision;
    final copyRevision = copyAccount.revision;
    final info = await api.getCopyCredentialInfo(token);

    return _serializeAccounts(() async {
      if (revision != _accountRevision ||
          copyRevision != copyAccount.revision) {
        return false;
      }
      final stored = copyAccount.byId(id);
      if (stored == null || stored.token != token) return false;
      String field(String key) => info[key]?.toString().trim() ?? '';
      if ([
        'user_id',
        'username',
        'nickname',
        'avatar',
      ].every((key) => field(key).isEmpty)) {
        return false;
      }
      if (!stored.acceptsProfile(
        userId: field('user_id'),
        username: field('username'),
      )) {
        return false;
      }
      String filled(String key, String previous) =>
          field(key).isEmpty ? previous : field(key);
      final updated = stored.copyWith(
        userId: filled('user_id', stored.userId),
        username: filled('username', stored.username),
        nickname: filled('nickname', stored.nickname),
        avatar: filled('avatar', stored.avatar),
      );
      final belongsToPrimary = [?currentCredential, ..._savedCredentials].any(
        (item) =>
            item.identity.matches(stored.identity) ||
            item.identity.matches(updated.identity),
      );
      if (belongsToPrimary) {
        // A trusted profile may prove that a token-only login and an old saved
        // entry are the same person. Reuse the dual-domain transaction so all
        // aliases, tokens and selection pointers commit (or roll back) together.
        return _commitLogin(
          _copyCredential(updated),
          revision: revision,
          copyRevision: copyAccount.beginLogin(),
          preserveSelection: true,
        );
      }
      // A genuinely independent legacy COPY account stays independent.
      _beginCopyAccountSuppression();
      try {
        final saved = await copyAccount.updateProfile(
          id: id,
          token: token,
          profile: info,
          expectedRevision: copyRevision,
          isCurrent: () => revision == _accountRevision,
        );
        if (saved) _notifySuppressedCommit();
        return saved;
      } finally {
        _endCopyAccountSuppression();
      }
    });
  }

  /// Profile refresh after successful login is best-effort and never delays or
  /// reverses authentication. Errors are logged without request details.
  void refreshCopyCredentialInBackground(
    CopyAccountSession credential, {
    required UserApi api,
  }) {
    unawaited(
      refreshCopyCredential(credential, api: api).then<void>(
        (_) {},
        onError: (Object _, StackTrace stackTrace) {
          unawaited(
            AppLogger.instance.recordWarning(
              StateError('Background COPY profile refresh failed'),
              stackTrace: stackTrace,
              source: 'user_manager.copy_profile_refresh',
            ),
          );
        },
      ),
    );
  }

  /// Refresh the clicked identity without changing any selection. A response
  /// is discarded if auth/credentials changed while its request was in flight.
  Future<bool> refreshCredential(SavedCredential credential) async {
    final token = credential.token;
    if (token == null || token.isEmpty) return false;
    if (credential.source == 'copy') {
      final stored = copyAccount.accounts
          .where(
            (item) =>
                item.token == token &&
                credential.identity.matches(item.identity),
          )
          .firstOrNull;
      if (stored != null) {
        return refreshCopyCredential(stored, api: ApiClient().user);
      }
    }
    final revision = _accountRevision;
    final copyRevision = copyAccount.revision;
    final info = await ApiClient().user.getCredentialInfo(
      token: token,
      source: credential.source,
    );
    return _serializeAccounts(() async {
      if (revision != _accountRevision) return false;
      final idx = _savedCredentials.indexWhere(
        (item) => item.sameAccount(credential) && item.token == token,
      );
      final active = currentCredential;
      final isActive =
          active?.sameAccount(credential) == true && active?.token == token;
      if (idx < 0 && !isActive) return false;
      final returnedId = info['user_id']?.toString() ?? '';
      final returnedName = info['username']?.toString() ?? '';
      if (returnedId.isEmpty && returnedName.isEmpty) return false;
      if (credential.source == 'copy') {
        if (copyRevision != copyAccount.revision ||
            !_copySession(
              credential,
            ).acceptsProfile(userId: returnedId, username: returnedName)) {
          return false;
        }
        final updated = credential.copyWith(
          username: returnedName.isEmpty ? credential.username : returnedName,
          userId: returnedId.isEmpty ? credential.userId : returnedId,
          nickname: info['nickname']?.toString(),
          avatar: info['avatar']?.toString(),
        );
        return _commitLogin(
          updated,
          revision: revision,
          preserveSelection: true,
        );
      }
      if (credential.userId?.isNotEmpty == true &&
          returnedId.isNotEmpty &&
          credential.userId != returnedId) {
        return false;
      }
      if (returnedName.isNotEmpty && returnedName != credential.username) {
        return false;
      }
      final updated = (idx < 0 ? credential : _savedCredentials[idx]).copyWith(
        userId: returnedId.isEmpty ? credential.userId : returnedId,
        nickname: info['nickname']?.toString(),
        avatar: info['avatar']?.toString(),
      );
      final next = [..._savedCredentials];
      if (idx >= 0) next[idx] = updated;
      // Identity-changing operations reserve a revision before they queue.
      await SecureCredentialStore().writeCredentials(next);
      if (revision != _accountRevision) {
        await SecureCredentialStore().writeCredentials(_savedCredentials);
        return false;
      }
      if (isActive) await _persistProfile(updated);
      if (revision != _accountRevision) {
        await SecureCredentialStore().writeCredentials(_savedCredentials);
        if (isActive && active != null) await _persistProfile(active);
        return false;
      }
      _savedCredentials = next;
      if (isActive) {
        _userId = updated.userId;
        _nickname = updated.nickname;
        _avatar = updated.avatar;
      }
      _notifyListeners();
      return true;
    });
  }

  Future<void> refreshUserInfo() async {
    final credential = currentCredential;
    if (credential != null) await refreshCredential(credential);
  }

  Future<void> setLoginSource(String source) {
    ++_accountRevision;
    return _serializeAccounts(() async {
      final prefs = await SharedPreferences.getInstance();
      await _requireAccountWrite(
        prefs.setString(UserManager._keyLoginSource, source),
      );
      _loginSource = source;
    });
  }
}
