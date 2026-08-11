part of '../reader_page.dart';

class _ReaderImageViewer extends StatefulWidget {
  final String imageSource;
  final bool isDownloaded;
  final BaseCacheManager cacheManager;
  final int pageNumber;
  final int pageCount;

  const _ReaderImageViewer({
    required this.imageSource,
    required this.isDownloaded,
    required this.cacheManager,
    required this.pageNumber,
    required this.pageCount,
  });

  @override
  State<_ReaderImageViewer> createState() => _ReaderImageViewerState();
}

class _ReaderImageViewerState extends State<_ReaderImageViewer> {
  static const _doubleTapScale = 2.5;
  static const _zoomedScaleThreshold = 1.01;

  final _user = UserManager();
  final TransformationController _transformationController =
      TransformationController();
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  Size? _imageSize;
  Offset? _lastDoubleTapLocalPosition;
  int _quarterTurns = 0;
  bool _hasManualRotation = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageSize();
  }

  @override
  void dispose() {
    final listener = _imageStreamListener;
    if (listener != null) {
      _imageStream?.removeListener(listener);
    }
    _transformationController.dispose();
    super.dispose();
  }

  void _resolveImageSize() {
    if (_imageStreamListener != null) return;

    final ImageProvider imageProvider = widget.isDownloaded
        ? FileImage(File(widget.imageSource))
        : CachedNetworkImageProvider(
            widget.imageSource,
            cacheManager: widget.cacheManager,
          );
    final stream = imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    final listener = ImageStreamListener((imageInfo, _) {
      final nextSize = Size(
        imageInfo.image.width.toDouble(),
        imageInfo.image.height.toDouble(),
      );
      imageInfo.dispose();
      if (!mounted || _imageSize == nextSize) return;
      setState(() {
        _imageSize = nextSize;
        _applyAutoRotateForCurrentImage();
      });
    });
    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  bool get _isLandscapeImage {
    final imageSize = _imageSize;
    if (imageSize == null) return false;
    return imageSize.width > imageSize.height;
  }

  int get _autoRotationQuarterTurns {
    if (!_user.imageViewerAutoRotateLandscape || !_isLandscapeImage) return 0;
    return _normalizeQuarterTurns(_user.imageViewerLandscapeRotation);
  }

  int _normalizeQuarterTurns(int turns) {
    final normalized = turns % 4;
    return normalized < 0 ? normalized + 4 : normalized;
  }

  void _applyAutoRotateForCurrentImage({bool force = false}) {
    if (_hasManualRotation && !force) return;
    _quarterTurns = _autoRotationQuarterTurns;
    _transformationController.value = Matrix4.identity();
  }

  void _resetView() {
    setState(() {
      _hasManualRotation = false;
      _applyAutoRotateForCurrentImage(force: true);
      _transformationController.value = Matrix4.identity();
    });
  }

  void _rotate(int delta) {
    setState(() {
      _hasManualRotation = true;
      _quarterTurns = (_quarterTurns + delta) % 4;
      if (_quarterTurns < 0) _quarterTurns += 4;
      _transformationController.value = Matrix4.identity();
    });
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapLocalPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > _zoomedScaleThreshold) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    final tapPosition = _lastDoubleTapLocalPosition ?? Offset.zero;
    final scenePoint = _transformationController.toScene(tapPosition);
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(
        tapPosition.dx - scenePoint.dx * _doubleTapScale,
        tapPosition.dy - scenePoint.dy * _doubleTapScale,
        0,
        1,
      )
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, _doubleTapScale, 1);
  }

  Size _fittedImageSize(BoxConstraints constraints) {
    final imageSize = _imageSize;
    final isSideways = _quarterTurns.isOdd;
    final availableSize = Size(
      isSideways ? constraints.maxHeight : constraints.maxWidth,
      isSideways ? constraints.maxWidth : constraints.maxHeight,
    );

    if (imageSize == null ||
        imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        availableSize.width <= 0 ||
        availableSize.height <= 0) {
      return availableSize;
    }

    return applyBoxFit(BoxFit.contain, imageSize, availableSize).destination;
  }

  Rect _imageTapRect(BoxConstraints constraints) {
    final fittedSize = _fittedImageSize(constraints);
    final displayedSize = _quarterTurns.isOdd
        ? Size(fittedSize.height, fittedSize.width)
        : fittedSize;
    final left = (constraints.maxWidth - displayedSize.width) / 2;
    final top = (constraints.maxHeight - displayedSize.height) / 2;
    return Offset(left, top) & displayedSize;
  }

  Future<void> _copyImageSource() async {
    await Clipboard.setData(ClipboardData(text: widget.imageSource));
    if (!mounted) return;
    showToast(
      context,
      widget.isDownloaded
          ? AppLocalizations.of(context)!.readerImagePathCopied
          : AppLocalizations.of(context)!.readerImageUrlCopied,
    );
  }

  Future<void> _saveImage() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess && !await Gal.requestAccess()) {
        if (mounted) {
          showToast(
            context,
            l10n.readerSaveImagePermissionDenied,
            isError: true,
          );
        }
        return;
      }
      final Uint8List bytes;
      if (widget.isDownloaded) {
        bytes = await File(widget.imageSource).readAsBytes();
      } else {
        final fileInfo = await widget.cacheManager.getFileFromCache(
          widget.imageSource,
        );
        if (fileInfo != null) {
          bytes = await fileInfo.file.readAsBytes();
        } else {
          bytes = await _downloadImageBytes();
        }
      }
      final ext = _detectImageExtension(bytes);
      if (ext == '.webp') {
        // gal 原生端用 Apache Imaging 猜测格式，对部分 webp 字节识别不稳定，
        // 先写临时文件走 putImage 路径让系统解码器处理。
        final dir = await getTemporaryDirectory();
        final tempFile = File(
          '${dir.path}/kira_save_${DateTime.now().millisecondsSinceEpoch}.webp',
        );
        try {
          await tempFile.writeAsBytes(bytes, flush: true);
          await Gal.putImage(tempFile.path, album: 'kira');
        } finally {
          if (tempFile.existsSync()) {
            unawaited(
              tempFile.delete().catchError(
                (_) => tempFile,
              ),
            );
          }
        }
      } else {
        await Gal.putImageBytes(bytes, album: 'kira');
      }
      if (mounted) showToast(context, l10n.readerImageSaved);
    } catch (error, stackTrace) {
      unawaited(
        AppLogger().recordWarning(
          '保存图片失败: $error',
          stackTrace: stackTrace,
          source: 'reader_image_viewer',
        ),
      );
      if (mounted) showToast(context, l10n.readerSaveImageFailed, isError: true);
    }
  }

  /// 按魔数识别常见图片格式，识别不出时默认 jpg（copymanga 实际多为 jpg/webp）。
  String _detectImageExtension(Uint8List bytes) {
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      // P
      return '.webp';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 && // G
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46) {
      // F
      return '.gif';
    }
    return '.jpg';
  }

  Future<Uint8List> _downloadImageBytes() async {
    final response = await Dio().get<List<int>>(
      widget.imageSource,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) {
      throw StateError('图片下载失败: ${response.statusCode}');
    }
    return Uint8List.fromList(data);
  }

  void _showViewerSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReaderImageViewerSettingsPanel(
        onChanged: () {
          if (!mounted) return;
          setState(() {
            _hasManualRotation = false;
            _applyAutoRotateForCurrentImage(force: true);
          });
        },
      ),
    );
  }

  Widget _buildImage() {
    Widget image;

    if (widget.isDownloaded) {
      image = Image.file(
        File(widget.imageSource),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const _ReaderImageViewerError(),
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: widget.imageSource,
        cacheManager: widget.cacheManager,
        fit: BoxFit.contain,
        placeholder: (_, _) => const Center(
          child: ExpressiveLoadingIndicator(color: ReaderChrome.onSurface),
        ),
        errorWidget: (_, _, _) => const _ReaderImageViewerError(),
      );
    }

    if (Theme.of(context).brightness == Brightness.dark &&
        _user.readerDimming > 0) {
      image = Stack(
        children: [
          image,
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: ReaderChrome.dimOverlay(_user.readerDimming),
              ),
            ),
          ),
        ],
      );
    }

    return image;
  }

  Widget _buildViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageSize = _fittedImageSize(constraints);
        final imageTapRect = _imageTapRect(constraints);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: (details) {
            if (imageTapRect.contains(details.localPosition)) {
              _handleDoubleTapDown(details);
            } else {
              _lastDoubleTapLocalPosition = null;
            }
          },
          onDoubleTap: () {
            if (_lastDoubleTapLocalPosition != null) {
              _handleDoubleTap();
            }
          },
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1,
            maxScale: 5,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Center(
                child: RotatedBox(
                  quarterTurns: _quarterTurns,
                  child: SizedBox(
                    width: imageSize.width,
                    height: imageSize.height,
                    child: _buildImage(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, color: ReaderChrome.onSurface, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: ReaderChrome.controlScrim,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildTopBar() {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: ReaderChrome.controlScrim,
                borderRadius: AppRadius.lgR,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '${widget.pageNumber}/${widget.pageCount}',
                  style: const TextStyle(
                    color: ReaderChrome.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Spacer(),
            _buildIconButton(
              icon: Icons.save_alt,
              tooltip: l10n.readerSaveImage,
              onPressed: _saveImage,
            ),
            const SizedBox(width: AppSpacing.sm),
            _buildIconButton(
              icon: Icons.copy_all_outlined,
              tooltip: widget.isDownloaded
                  ? l10n.readerCopyImagePath
                  : l10n.readerCopyImageUrl,
              onPressed: _copyImageSource,
            ),
            const SizedBox(width: AppSpacing.sm),
            _buildIconButton(
              icon: Icons.settings,
              tooltip: l10n.readerImageViewerSettingsTooltip,
              onPressed: _showViewerSettings,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        backgroundColor: ReaderChrome.surface,
        body: Stack(
          children: [
            Positioned.fill(child: _buildViewport()),
            Align(alignment: Alignment.topCenter, child: _buildTopBar()),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _buildIconButton(
                        icon: Icons.center_focus_strong,
                        tooltip: AppLocalizations.of(context)!.resetButton,
                        onPressed: _resetView,
                      ),
                      _buildIconButton(
                        icon: Icons.rotate_left,
                        tooltip: AppLocalizations.of(context)!.readerRotateLeft,
                        onPressed: () => _rotate(-1),
                      ),
                      _buildIconButton(
                        icon: Icons.rotate_right,
                        tooltip: AppLocalizations.of(
                          context,
                        )!.readerRotateRight,
                        onPressed: () => _rotate(1),
                      ),
                      _buildIconButton(
                        icon: Icons.close,
                        tooltip: AppLocalizations.of(context)!.closeButton,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderImageViewerError extends StatelessWidget {
  const _ReaderImageViewerError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.broken_image,
        color: ReaderChrome.onSurfaceSubtle,
        size: 56,
      ),
    );
  }
}

class _ReaderImageViewerSettingsPanel extends StatefulWidget {
  final VoidCallback onChanged;

  const _ReaderImageViewerSettingsPanel({required this.onChanged});

  @override
  State<_ReaderImageViewerSettingsPanel> createState() =>
      _ReaderImageViewerSettingsPanelState();
}

class _ReaderImageViewerSettingsPanelState
    extends State<_ReaderImageViewerSettingsPanel> {
  final _user = UserManager();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppLocalizations.of(context)!.readerImageViewerSettingsTitle,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  AppLocalizations.of(context)!.readerAutoRotateLandscape,
                ),
                subtitle: Text(
                  AppLocalizations.of(context)!.readerAutoRotateLandscapeDesc,
                ),
                value: _user.imageViewerAutoRotateLandscape,
                onChanged: (value) {
                  _user.setImageViewerAutoRotateLandscape(value);
                  setState(() {});
                  widget.onChanged();
                },
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _user.imageViewerAutoRotateLandscape ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !_user.imageViewerAutoRotateLandscape,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        AppLocalizations.of(context)!.readerRotationDirection,
                        style: tt.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          segments: [
                            ButtonSegment(
                              value: -1,
                              icon: const Icon(Icons.rotate_left),
                              label: Text(
                                AppLocalizations.of(
                                  context,
                                )!.readerRotateLeftShort,
                              ),
                            ),
                            ButtonSegment(
                              value: 1,
                              icon: const Icon(Icons.rotate_right),
                              label: Text(
                                AppLocalizations.of(
                                  context,
                                )!.readerRotateRightShort,
                              ),
                            ),
                          ],
                          selected: {_user.imageViewerLandscapeRotation},
                          onSelectionChanged: (selection) {
                            _user.setImageViewerLandscapeRotation(
                              selection.first,
                            );
                            setState(() {});
                            widget.onChanged();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
