import 'package:adb/adb.dart';
import 'package:flutter/services.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/content/content_cache_failure.dart';
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/settings/preference_schema.dart';

import 'request_failure.dart';

/// Converts a failure at the point where it is shown. The caller supplies copy
/// for the action in progress. Native messages and persisted error text can
/// contain system details and must not become visible by default.
String failureMessage(Object? error, {required String fallback}) {
  final code = switch (error) {
    RequestFailure(:final code) ||
    FileFailure(:final code) ||
    ContentCacheFailure(:final code) ||
    PlatformException(:final code) ||
    AdbException(:final code) ||
    ScrcpyException(:final code) ||
    PreferenceFailure(:final code) ||
    SetupIssue(:final code) => code,
    LocalFileException(:final code) => code.name,
    _ => null,
  };
  return failureCodeMessage(code, fallback: fallback);
}

/// Used when a saved result has a code but no exception object.
String failureCodeMessage(String? code, {required String fallback}) =>
    switch (code) {
      'disconnected' ||
      'device_unavailable' ||
      'stale_connection' => '手机连接已断开。重新连接后再试。',
      'connection_changed' => '手机连接已变化。请确认当前连接的手机后再试。',
      'device_identity_mismatch' => '连接到了另一台手机。请检查连接的是哪台手机。',
      'missing_share' => '这次分享已结束。请回原应用重新分享。',
      'share_importing' => '正在读取分享内容，请稍候。',
      'share_empty_selection' => '请选择要发送的文件或文字。',
      'missing_directory' => '无法确认接收文件的文件夹。请重新选择。',
      'metadata_file_too_large' => '设备记录文件太大。请选择不超过 1 MB 的文件。',
      'identity_result_invalid' => '暂时无法确认密钥是否已更新。请重新打开此页检查。',
      'authorization_required' || 'unauthorized' => '请解锁手机并允许 USB 或无线调试，然后重试。',
      'duplicate_name' ||
      'duplicate_destination' ||
      'conflict' => '这里已有同名文件或文件夹。请换个名称或位置。',
      'source_changed' ||
      'sourceChanged' ||
      'target_changed' ||
      'targetChanged' => '所选内容已变化。请刷新列表后重新选择。',
      'not_a_file' => '这个位置不是文件。请选择一个文件。',
      'not_a_directory' || 'not_directory' => '这个位置不是文件夹。请选择其他位置。',
      'not_found' ||
      'notFound' ||
      'device_not_found' ||
      'missing_file' => '找不到所选内容。请刷新列表后重新选择。',
      'invalid_filename' => '无法识别这个文件名。请在手机上重命名后刷新。',
      'storage_full' => '本机存储空间不足。腾出空间后再试。',
      'cache_full' ||
      'cache_budget_exceeded' ||
      'cache_capacity' ||
      'document_cache_full' ||
      'share_cache_full' => '临时文件空间不足。请前往设置清理媒体暂存后再试。',
      'cache_evicted' || 'cache_unavailable' => '临时文件已不可用。请从手机重新取回。',
      'atomic_save_unavailable' => '当前位置无法完成原件的安全保存。请检查本机暂存位置后重试。',
      'permission_denied' => '系统没有允许这项操作。请检查相关权限后再试。',
      'storage_version' => '本机数据来自较新版本。更新应用后再试。',
      'expired' => '这次请求已过期。请重新开始。',
      'usb_unsupported' => '本机无法通过 USB 添加手机。请选择其他连接方式。',
      'audio_focus_denied' => '声音目前无法播放。请先暂停本机正在播放的媒体。',
      'clipboard_not_text' => '剪贴板里没有可发送的文字。',
      'clipboard_locked' => '暂时无法读取剪贴板。解锁设备后再试。',
      'invalid_pairing_code' => '请输入手机上显示的 6 位配对码。',
      'invalid_port' => '请输入 1 到 65535 之间的端口号。',
      'result_unknown' ||
      'resultUnknown' ||
      'preferences_apply_unknown' ||
      'share_submission_unknown' ||
      'close_failed' ||
      'cleanupUnconfirmed' => '暂时无法确认操作是否完成。请先检查结果，再决定是否重试。',
      final String code when code.endsWith('_cleanup_unconfirmed') =>
        '上一次操作还没有完全结束。请先检查当前状态。',
      _ => fallback,
    };
