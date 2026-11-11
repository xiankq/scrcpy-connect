import 'package:scrcpy_connect/models/file_cache_reservation.dart';

import 'dart:async';

/// 本机缓存预算准入与路径租约，不另建任务状态所有者。
abstract interface class FileCacheLeases {
  Future<String> reserve(List<FileCacheReservation> reservations);
  Future<void> release(String lease);
}

abstract interface class CacheWriter {
  String get leaseId;
  Future<void> close();
}
