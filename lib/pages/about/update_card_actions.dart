part of '../about_page.dart';

extension _UpdateCardActions on _UpdateCardState {
  void _onStateChanged() {
    if (mounted) _setState(() {});
  }

  void _onInstallStateChanged() {
    final s = InAppInstaller.instance.state.value;
    // Surface a toast exactly once when entering the error/done states.
    if (_lastSurfacedInstallStatus != s.status) {
      _lastSurfacedInstallStatus = s.status;
      if (s.status == InstallStatus.error && mounted) {
        final l10n = AppLocalizations.of(context)!;
        showToast(
          context,
          s.needsPermission
              ? l10n.updateInstallPermissionNeeded
              : (s.assetName != null && s.assetName!.isNotEmpty
                    ? l10n.updateInstallFailed
                    : l10n.updateDownloadFailed),
          isError: true,
        );
      }
    }
    if (mounted) _setState(() {});
  }

  bool get _isInstalling => InAppInstaller.instance.state.value.isBusy;

  Future<void> _openUrl(String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (!launched) {
      showToast(
        context,
        AppLocalizations.of(context)!.updateOpenDownloadFailed,
        isError: true,
      );
    }
  }

  Future<void> _installInApp(ReleaseAsset asset) async {
    if (_isInstalling) return;
    _lastSurfacedInstallStatus = null;
    await InAppInstaller.instance.downloadAndInstall(
      asset,
      useMirror: _useMirror,
    );
  }

  /// In-app download+install is wired for Android APKs only; every other
  /// platform falls back to the asset tile's browser download links.
  bool _canInstallInApp(ReleaseAsset asset) =>
      Platform.isAndroid && asset.platform == AssetPlatform.android;

  /// 当前设备 ABI 对应的 Android 安装包；读不到 ABI 或没有匹配时为
  /// null，调用方回退为全量展开展示。
  ReleaseAsset? _deviceAsset(List<ReleaseAsset> assets) {
    final abi = deviceAndroidAbi();
    if (abi == null) return null;
    for (final a in assets) {
      if (a.platform == AssetPlatform.android && a.matchesAbi(abi)) return a;
    }
    return null;
  }

  /// Beta / single-asset releases render their newest (or only) asset inline:
  /// install buttons for an Android APK, the regular asset tile (with
  /// GitHub/mirror browser-download buttons) otherwise.
  Widget _buildInlineAsset(ReleaseAsset asset, ColorScheme cs, TextTheme tt) {
    return _canInstallInApp(asset)
        ? _buildInstallButtons(asset, cs, tt)
        : _buildAssetTile(asset, cs, tt);
  }

  Future<void> _skipVersion() async {
    final info = AppUpdateService.state.value.info;
    if (info == null) return;
    await UserManager().setSkippedUpdateVersion(info.latestVersion);
    // Clear so the card disappears and any entry dots stay off.
    AppUpdateService.state.value = const AppUpdateState.latest();
    AppUpdateService.markUpdateBadgeSeen();
  }

  void _setMirror(bool value) {
    if (_useMirror == value) return;
    _setState(() => _useMirror = value);
    UserManager().setUseUpdateMirror(value);
  }

  /// 内层安装包列表滚动到顶/到底后，把剩余拖动量转给外层页面滚动，
  /// 否则内层会"吃掉"拖动，到边缘后无法继续滚动页面。
  bool _handOffOverscroll(OverscrollNotification n) {
    final outer = Scrollable.maybeOf(context);
    if (outer == null) return false;
    final pos = outer.position;
    pos.jumpTo(
      (pos.pixels + n.overscroll).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      ),
    );
    return true;
  }

  /// 全屏弹窗查看完整更新说明（不设内层限高，整页滚动）。
  void _showNotesFullscreen(ColorScheme cs, String notes) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        child: Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.of(context)!.updateViewNotes),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildReleaseNotes(notes, cs),
            ),
          ),
        ),
      ),
    );
  }

}
