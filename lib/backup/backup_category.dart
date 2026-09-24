/// Only explicitly registered preferences may leave this device or be restored.
/// Add new portable settings here with their actual SharedPreferences type.
enum BackupCategory {
  settings,
  readingHistory,
  readingStatistics,
  bookmarks,
  account,
  aiConnection;

  bool get isSensitive => this == account || this == aiConnection;
}

abstract final class BackupSchema {
  static const accountKeys = {
    'user_token',
    'user_username',
    'user_nickname',
    'user_avatar',
    'user_id',
    'saved_username',
    'saved_password',
    'saved_credentials',
    'auto_login',
    'login_source',
    'copy_login_host',
    'copy_login_custom_hosts',
  };

  static const aiConnectionKeys = {
    'zhipu_api_key',
    'zhipu_base_url',
    'zhipu_api_format',
    'zhipu_model',
    'zhipu_custom_models',
    'ai_providers',
    'ai_active_provider',
  };

  static const _boolKeys = {
    'amoled_dark',
    'app_logging_enabled',
    'auto_check_update',
    'auto_login',
    'back_exit_confirm',
    'banner_visible',
    'bottom_nav_show_labels',
    'comment_auto_load_all',
    'comment_block_group_spam',
    'comment_block_no_remind',
    'comment_compact_layout',
    'comment_preload',
    'comment_show_avatar',
    'comment_show_time',
    'comment_show_user_name',
    'copy_auto_update',
    'download_chapter_comments',
    'image_viewer_auto_rotate_landscape',
    'nav_swipe_enabled',
    'reader_auto_scroll_enabled',
    'reader_auto_scroll_resume',
    'reader_continuous_reading',
    'reader_instant_page_turn',
    'reader_long_press_zoom_enabled',
    'reader_page_rtl',
    'reader_page_vertical',
    'reader_reading_stats_enabled',
    'reader_reading_stats_show_activity_chart',
    'reader_reading_stats_show_overview',
    'reader_reading_stats_show_tags',
    'reader_status_overlay',
    'reader_status_overlay_battery',
    'reader_status_overlay_fps',
    'reader_status_overlay_network',
    'reader_status_overlay_page',
    'reader_status_overlay_time',
    'reader_volume_key',
    'remote_notice_enabled',
    'use_dynamic_color',
    'use_update_mirror',
    'zhipu_auto_summary',
    'zhipu_spoiler_analysis',
    'zhipu_spoiler_warn',
    'zhipu_summary_collapsed',
    'zhipu_summary_enabled',
  };

  static const _intKeys = {
    'api_route',
    'custom_theme_color',
    'download_image_concurrency',
    'image_load_timeout',
    'image_retry_count',
    'image_viewer_landscape_rotation',
    'logo_index',
    'network_proxy_mode',
    'network_proxy_port',
    'network_proxy_type',
    'network_selection_mode',
    'pref_display_mode_refresh_rate',
    'reader_mode',
    'reader_reading_stats_chart_style',
    'reader_scroll_direction',
    'reader_status_overlay_position',
    'theme_mode',
    'zhipu_auto_summary_min',
  };

  static const _doubleKeys = {
    'card_shadow_elevation',
    'comment_font_scale',
    'dark_mode_cover_brightness',
    'default_font_size',
    'reader_auto_scroll_distance',
    'reader_auto_scroll_pause',
    'reader_auto_scroll_resume_delay',
    'reader_dimming',
    'reader_horizontal_image_scale',
    'reader_image_gap',
    'reader_long_press_zoom_pan_sensitivity',
    'reader_status_overlay_opacity',
  };

  static const _stringKeys = {
    'app_font_family',
    'app_logging_minimum_level',
    'bookshelf_ordering',
    'bottom_nav_label_mode',
    'copy_api_host',
    'copy_app_version',
    'copy_home_section_collapsed',
    'copy_login_host',
    'desktop_font_family',
    'discover_source',
    'locale',
    'login_source',
    'manga_home_source',
    'network_fixed_node_host',
    'network_proxy_host',
    'saved_credentials',
    'saved_password',
    'saved_username',
    'theme_color',
    'theme_variant',
    'update_channel',
    'update_mirror_prefix',
    'user_avatar',
    'user_id',
    'user_nickname',
    'user_token',
    'user_username',
    'zhipu_active_preset',
    'zhipu_api_format',
    'zhipu_api_key',
    'zhipu_auto_summary_timing',
    'zhipu_base_url',
    'zhipu_model',
    'zhipu_prompt_presets',
    'ai_providers',
    'ai_active_provider',
  };

  static const _listKeys = {
    'comment_blocked_users',
    'comment_blockwords',
    'copy_login_custom_hosts',
    'nav_order',
    'reader_reading_stats_section_order',
    'reader_status_overlay_order',
    'zhipu_custom_models',
  };

  static BackupCategory? categoryOf(String key) {
    if (key.startsWith('reading_history_')) {
      return BackupCategory.readingHistory;
    }
    if (key == 'reading_stats_v1') return BackupCategory.readingStatistics;
    if (key == 'comic_bookmarks_v1') return BackupCategory.bookmarks;
    if (accountKeys.contains(key)) return BackupCategory.account;
    if (aiConnectionKeys.contains(key)) return BackupCategory.aiConnection;
    return typeOf(key) == null ? null : BackupCategory.settings;
  }

  static String? typeOf(String key) {
    if (_boolKeys.contains(key)) return 'bool';
    if (_intKeys.contains(key)) return 'int';
    if (_doubleKeys.contains(key)) return 'double';
    if (_listKeys.contains(key)) return 'string_list';
    if (_stringKeys.contains(key) ||
        key.startsWith('reading_history_') ||
        key == 'reading_stats_v1' ||
        key == 'comic_bookmarks_v1') {
      return 'string';
    }
    // In particular: backup_*, cache_*, AI conversations/summaries, download
    // queues/paths, local library data, anime and runtime markers are excluded.
    return null;
  }
}
