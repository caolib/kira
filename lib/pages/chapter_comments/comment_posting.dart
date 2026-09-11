part of '../chapter_comments_sheet.dart';

extension _ChapterCommentPosting on _ChapterCommentsSheetState {
  String _extractCommentPostErrorMessage(Object error) {
    if (error is DioException) {
      final inner = error.error;
      final innerText = inner?.toString().trim();
      if (innerText != null && innerText.isNotEmpty) {
        return innerText;
      }
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
    return NetworkError.message(error, l10n: AppLocalizations.of(context)!);
  }

  String _formatCommentPostErrorLog(Object error) {
    if (error is DioException) {
      final buffer = StringBuffer();
      buffer.writeln('DioException');
      buffer.writeln('type: ${error.type}');
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        buffer.writeln('message: $message');
      }
      buffer.writeln(
        'request: ${error.requestOptions.method} ${error.requestOptions.uri}',
      );

      final requestData = error.requestOptions.data;
      if (requestData != null) {
        buffer.writeln('requestData: ${_formatLogValue(requestData)}');
      }

      final response = error.response;
      if (response != null) {
        buffer.writeln('statusCode: ${response.statusCode}');
        if (response.data != null) {
          buffer.writeln('responseData: ${_formatLogValue(response.data)}');
        }
      }

      buffer.writeln('toString: ${error.toString()}');
      return buffer.toString().trimRight();
    }

    return error.toString();
  }

  String _formatLogValue(Object? value) {
    if (value == null) return 'null';
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  Widget _buildPostCommentErrorPanel(
    BuildContext context, {
    required String message,
    required String log,
    required VoidCallback onCopy,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: AppRadius.mdR,
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: cs.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.chapterCommentsDioException,
                  style: tt.labelLarge?.copyWith(
                    color: cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onCopy,
                style: TextButton.styleFrom(foregroundColor: cs.error),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l10n.chapterCommentsCopyLog),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: tt.bodySmall?.copyWith(
              color: cs.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: SingleChildScrollView(
              child: SelectableText(
                log,
                style: tt.bodySmall?.copyWith(
                  color: cs.onErrorContainer.withValues(alpha: 0.9),
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPostCommentDialog() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_user.isLoggedIn) {
      showToast(
        context,
        l10n.chapterCommentsLoginRequiredToPost,
        isError: true,
      );
      return;
    }

    var submitting = false;
    String? errorText;
    String? errorLog;

    Future<void> submit(
      BuildContext dialogContext,
      StateSetter setLocal,
      TextEditingController controller,
    ) async {
      final content = controller.text.trim();
      final length = CommentText.lengthOf(content);
      if (length < CommentText.minLength || length > CommentText.maxLength) {
        setLocal(() {
          errorText = l10n.chapterCommentsLengthRange;
          errorLog = 'ValidationError: ${l10n.chapterCommentsLengthRange}';
        });
        return;
      }

      setLocal(() {
        submitting = true;
        errorText = null;
        errorLog = null;
      });

      try {
        await _api.manga.postChapterComment(widget.chapterUuid, content);
        if (!mounted) return;
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        showToast(context, l10n.chapterCommentsPosted);
        await _refreshFirstPage();
      } catch (e) {
        if (!dialogContext.mounted) return;
        setLocal(() {
          submitting = false;
          errorText = _extractCommentPostErrorMessage(e);
          errorLog = _formatCommentPostErrorLog(e);
        });
      }
    }

    // 控制器交给 TextControllerScope 托管：弹窗退出动画期间子树仍会重建，
    // 提前 dispose 会命中 “used after being disposed” 断言。
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          builder: (dialogContext, controller) {
            return StatefulBuilder(
              builder: (dialogContext, setLocal) {
                final length = CommentText.lengthOf(controller.text);
                final canSubmit =
                    !submitting &&
                    length >= CommentText.minLength &&
                    length <= CommentText.maxLength;
                return AlertDialog(
                  title: Text(l10n.chapterCommentsPostTitle),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: controller,
                          autofocus: true,
                          enabled: !submitting,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: CommentText.maxLength,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(200),
                          ],
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: l10n.chapterCommentsPostHint,
                            helperText: l10n.chapterCommentsLengthHelper,
                            errorText: errorText,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setLocal(() {
                            errorText = null;
                            errorLog = null;
                          }),
                        ),
                        if (errorText != null && errorLog != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _buildPostCommentErrorPanel(
                            dialogContext,
                            message: errorText!,
                            log: errorLog!,
                            onCopy: () async {
                              await Clipboard.setData(
                                ClipboardData(text: errorLog!),
                              );
                              if (!mounted) return;
                              showToast(context, l10n.chapterCommentsLogCopied);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: Text(l10n.cancelButton),
                    ),
                    FilledButton(
                      onPressed: canSubmit
                          ? () => submit(dialogContext, setLocal, controller)
                          : null,
                      child: submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.chapterCommentsPublish),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showPostCommentErrorDialog(Object error) async {
    final l10n = AppLocalizations.of(context)!;
    final message = _extractCommentPostErrorMessage(error);
    final log = _formatCommentPostErrorLog(error);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chapterCommentsPostFailed),
        content: SingleChildScrollView(
          child: _buildPostCommentErrorPanel(
            dialogContext,
            message: message,
            log: log,
            onCopy: () async {
              await Clipboard.setData(ClipboardData(text: log));
              if (!mounted) return;
              showToast(context, l10n.chapterCommentsLogCopied);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  Future<void> _showCommentSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height *
            _ChapterCommentsSheetState._sheetMaxHeightFactor,
      ),
      builder: (sheetContext) {
        final sheetSize = MediaQuery.sizeOf(sheetContext);
        // 键盘弹出时面板顶边保持不动、底边抬到输入法上方，否则输入法
        // 会盖住面板底部的屏蔽词输入框。
        final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
        final sheetHeight =
            (sheetSize.height *
                        _ChapterCommentsSheetState._sheetMaxHeightFactor -
                    keyboard)
                .clamp(0.0, sheetSize.height)
                .toDouble();
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SizedBox(
              width: sheetSize.width,
              height: sheetHeight,
              child: ExcludeSemantics(
                child: CommentSettingsPanel(
                  useCompactLayout: _useCompactLayout,
                  showUserAvatar: _showUserAvatar,
                  showUserName: _showUserName,
                  showCommentTime: _showCommentTime,
                  commentFontScale: _commentFontScale,
                  commentPreload: _user.commentPreload,
                  commentAutoLoadAll: _user.commentAutoLoadAll,
                  onLayoutChanged: (compact) {
                    if (!mounted) return;
                    _setState(() => _useCompactLayout = compact);
                    _user.setCommentCompactLayout(compact);
                  },
                  onShowAvatarChanged: (enabled) {
                    if (!mounted) return;
                    _setState(() => _showUserAvatar = enabled);
                    _user.setCommentShowAvatar(enabled);
                  },
                  onShowUserNameChanged: (enabled) {
                    if (!mounted) return;
                    _setState(() => _showUserName = enabled);
                    _user.setCommentShowUserName(enabled);
                  },
                  onShowCommentTimeChanged: (enabled) {
                    if (!mounted) return;
                    _setState(() => _showCommentTime = enabled);
                    _user.setCommentShowTime(enabled);
                  },
                  onFontScaleChanged: (scale) {
                    if (!mounted) return;
                    _setState(() => _commentFontScale = scale);
                    _user.setCommentFontScale(scale);
                  },
                  onPreloadChanged: (enabled) {
                    _user.setCommentPreload(enabled);
                    if (!enabled &&
                        _aiSettings.autoSummaryTiming ==
                            AiAutoSummaryTiming.afterPreload) {
                      _aiSettings.setAutoSummaryTiming(
                        AiAutoSummaryTiming.onOpen,
                      );
                    }
                  },
                  onAutoLoadAllChanged: (enabled) {
                    _user.setCommentAutoLoadAll(enabled);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    // 编辑屏蔽词/屏蔽用户后，重新过滤已加载的评论。
    _setState(_rebuildGroupedEntries);
  }
}
