import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/comment_settings.dart';
import '../models/danmaku_settings.dart';
import '../models/network_settings.dart';
import '../models/reader_settings.dart';
import '../models/theme_settings.dart';
import '../models/user_manager.dart';
import 'app_providers.dart';

/// Provides the [ReaderSettings] sub-store from [UserManager].
final readerSettingsProvider = Provider<ReaderSettings>((ref) {
  return ref.watch(userManagerProvider).reader;
});

/// Provides the [DanmakuSettings] sub-store from [UserManager].
final danmakuSettingsProvider = Provider<DanmakuSettings>((ref) {
  return ref.watch(userManagerProvider).danmaku;
});

/// Provides the [CommentSettings] sub-store from [UserManager].
final commentSettingsProvider = Provider<CommentSettings>((ref) {
  return ref.watch(userManagerProvider).comment;
});

/// Provides the [ThemeSettings] sub-store from [UserManager].
final themeSettingsProvider = Provider<ThemeSettings>((ref) {
  return ref.watch(userManagerProvider).theme;
});

/// Provides the [NetworkSettings] sub-store from [UserManager].
final networkSettingsProvider = Provider<NetworkSettings>((ref) {
  return ref.watch(userManagerProvider).network;
});
