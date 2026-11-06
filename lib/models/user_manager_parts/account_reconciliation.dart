part of '../user_manager.dart';

CopyAccountSession _copySession(SavedCredential credential) =>
    CopyAccountSession(
      token: credential.token!,
      accountId: credential.accountId,
      userId: credential.userId ?? '',
      username: credential.username,
      nickname: credential.nickname ?? '',
      avatar: credential.avatar ?? '',
    );

SavedCredential _copyCredential(CopyAccountSession session) => SavedCredential(
  username: session.username,
  password: '',
  token: session.token,
  loginSource: 'copy',
  userId: session.userId,
  nickname: session.nickname,
  avatar: session.avatar,
  accountId: session.id,
);

class _CredentialMerge {
  final List<SavedCredential> accounts;
  final Map<SavedCredential, SavedCredential> _byOriginal;

  _CredentialMerge(this.accounts, this._byOriginal);

  SavedCredential? forAccount(SavedCredential? original) =>
      _byOriginal[original];
}

/// Reconcile all saved identities, not just the one being logged in. COPY's
/// projected snapshot supplies the canonical binding and token for both domains.
_CredentialMerge _mergeCredentials(
  List<SavedCredential> credentials, {
  SavedCredential? preferred,
  SavedCredential? incoming,
  bool overwriteIncomingPassword = false,
  List<CopyAccountSession> copyAccounts = const [],
}) {
  final groups = groupAccounts(credentials, (account) => account.identity);
  final exactPreferredGroups = groups
      .where((group) => group.any((item) => identical(item, preferred)))
      .toList();
  final preferredGroups = exactPreferredGroups.isNotEmpty
      ? exactPreferredGroups
      : preferred == null
      ? <List<SavedCredential>>[]
      : groups
            .where((group) => group.any((item) => item.sameAccount(preferred)))
            .toList();
  final copyOwners = Map<CopyAccountSession, List<SavedCredential>>.identity();
  for (final copy in copyAccounts) {
    final matches = groups
        .where(
          (group) => group.any((item) => item.identity.matches(copy.identity)),
        )
        .toList();
    // A projection must be unique in both directions: an anonymous COPY row
    // with a shared fallback id must not overwrite several known login names.
    if (matches.length == 1) copyOwners[copy] = matches.single;
  }
  final result = <SavedCredential>[];
  final byOriginal = Map<SavedCredential, SavedCredential>.identity();
  for (final group in groups) {
    final sorted = [...group]
      ..sort((a, b) {
        if (a.hasIdentity != b.hasIdentity) return a.hasIdentity ? -1 : 1;
        final aKey = a.accountId ?? a.userId ?? a.username;
        final bKey = b.accountId ?? b.userId ?? b.username;
        return aKey.compareTo(bKey);
      });
    final selected =
        incoming != null && group.any((item) => identical(item, incoming))
        ? incoming
        : preferredGroups.length == 1 &&
              identical(preferredGroups.single, group)
        ? preferred
        : null;
    final copies = copyAccounts
        .where((copy) => identical(copyOwners[copy], group))
        .toList();
    final copy = copies.length == 1 ? _copyCredential(copies.single) : null;
    final fields = [?copy, ?selected, ...sorted];
    String? value(String? Function(SavedCredential) read) => fields
        .map(read)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .firstOrNull;
    final base = copy ?? selected ?? sorted.first;
    final existingId = sorted
        .where((item) => !identical(item, incoming))
        .map((item) => item.accountId)
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .firstOrNull;
    final merged = base.copyWith(
      username: value((item) => item.username) ?? '',
      password:
          overwriteIncomingPassword &&
              incoming != null &&
              group.any((item) => identical(item, incoming))
          ? incoming.password
          : value((item) => item.password) ?? '',
      token: value((item) => item.token),
      userId: value((item) => item.userId),
      nickname: value((item) => item.nickname),
      avatar: value((item) => item.avatar),
      accountId:
          copy?.accountId ?? existingId ?? value((item) => item.accountId),
      extraFields: Map.unmodifiable({
        for (final item in fields.reversed) ...item._extraFields,
      }),
    );
    result.add(merged);
    for (final original in group) {
      byOriginal[original] = merged;
    }
  }
  int position(SavedCredential account) => credentials.indexWhere(
    (original) => identical(byOriginal[original], account),
  );
  result.sort((a, b) => position(a).compareTo(position(b)));
  return _CredentialMerge(result, byOriginal);
}

extension UserManagerAccountReconciliation on UserManager {
  /// Called inside the primary queue; COPY init holds its own queue until both
  /// writes finish. A read-only backup reload reconciles each domain in memory
  /// only, without importing/rotating the independent COPY record.
  Future<void> _initCopyAccounts({
    required bool persistMigrations,
    required int revision,
  }) async {
    final secure = SecureCredentialStore();
    final prefs = await SharedPreferences.getInstance();
    final previousRecord = await secure.readCredentialsRecord();
    final previousCredentials = await secure.readCredentials();
    final credentialsCleared =
        previousCredentials.isEmpty && await secure.hasCredentialsRecord();
    final previousProfile = {
      for (final key in UserManager._profileKeys) key: prefs.getString(key),
    };
    final active = currentCredential;
    final currentWithPassword = _currentWithPassword;
    final candidates = [
      if (!credentialsCleared) ?currentWithPassword,
      ..._savedCredentials,
    ];
    var next = _savedCredentials;
    SavedCredential? selected;
    var credentialsTouched = false;
    var selectionTouched = false;
    var published = false;
    Future<void> rollback() async {
      if (credentialsTouched) {
        await secure.writeCredentialsRecord(previousRecord);
      }
      if (selectionTouched) {
        await secure.writeToken(_token);
        await secure.writeUsername(_savedUsername);
        await secure.writePassword(_savedPassword);
        for (final entry in previousProfile.entries) {
          await _requireAccountWrite(
            entry.value == null
                ? prefs.remove(entry.key)
                : prefs.setString(entry.key, entry.value!),
          );
        }
      }
    }

    await copyAccount.init(
      legacySession: active?.source == 'copy' ? _copySession(active!) : null,
      persistMigrations: persistMigrations,
      isCurrent: () => revision == _accountRevision,
      prepareCommit: (merge) async {
        final primaryMerge = _mergeCredentials(
          candidates,
          preferred: currentWithPassword,
          copyAccounts: persistMigrations ? merge.accounts : const [],
        );
        next = primaryMerge.accounts;
        selected = primaryMerge.forAccount(currentWithPassword);
        if (currentWithPassword != null && selected == null) {
          selected = _mergeCredentials(
            [currentWithPassword, ...next],
            preferred: currentWithPassword,
            copyAccounts: persistMigrations ? merge.accounts : const [],
          ).forAccount(currentWithPassword);
        }
        if (!persistMigrations) return;
        // Startup enrichment is memory-only. Persist saved identities only
        // when deduplication actually merges rows or remaps a COPY binding.
        final savedMerge = _mergeCredentials(
          _savedCredentials,
          preferred: currentWithPassword,
          copyAccounts: merge.accounts,
        );
        final deduplicated =
            savedMerge.accounts.length < _savedCredentials.length ||
            merge.idRemap.entries.any(
              (entry) =>
                  entry.key != entry.value &&
                  _savedCredentials.any(
                    (credential) =>
                        credential.source == 'copy' &&
                        credential.accountId == entry.key,
                  ),
            );
        if (deduplicated &&
            jsonEncode(previousCredentials.map((c) => c.toJson()).toList()) !=
                jsonEncode(
                  savedMerge.accounts.map((c) => c.toJson()).toList(),
                )) {
          credentialsTouched = true;
          await secure.writeCredentials(savedMerge.accounts);
        }
        final target = selected;
        if (deduplicated &&
            target != null &&
            active?.source == 'copy' &&
            jsonEncode(target.copyWith(password: '').toJson()) !=
                jsonEncode(active!.toJson())) {
          selectionTouched = true;
          await secure.writeToken(target.token);
          if (!credentialsCleared) {
            await secure.writeUsername(target.username);
            await secure.writePassword(target.password);
          }
          await _persistProfile(target);
        }
      },
      rollback: rollback,
      onCommitted: (_) {
        published = true;
        _savedCredentials = next;
        final target = selected;
        if (target == null || active?.source != 'copy') return;
        _token = target.token;
        _accountId = target.accountId;
        _username = target.username;
        _userId = target.userId;
        _nickname = target.nickname;
        _avatar = target.avatar;
        if (persistMigrations && selectionTouched && !credentialsCleared) {
          _savedUsername = target.username;
          _savedPassword = target.password;
        }
      },
    );
    if (!published && revision == _accountRevision) {
      // A failed independent COPY migration must not discard the readable
      // primary profile. Enrich only in memory, without publishing COPY ids.
      _savedCredentials = _mergeCredentials(
        candidates,
        preferred: currentWithPassword,
      ).accounts;
    }
  }
}
