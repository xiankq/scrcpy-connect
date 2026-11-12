import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/app_dependencies_provider.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_catalog_entry.dart';

import 'gallery_history_notifier.dart';
import 'gallery_scan.dart';

part 'gallery_scan_notifier.freezed.dart';
part 'gallery_scan_notifier.g.dart';

@freezed
abstract class GalleryScanState with _$GalleryScanState {
  const GalleryScanState._();
  const factory GalleryScanState({
    GalleryScanSnapshot? result,
    GalleryScanSnapshot? latest,
    GalleryScanSnapshot? pendingResult,
    @Default([]) List<FileCatalogEntry> items,
    @Default([]) List<FileCatalogEntry> pendingItems,
    @Default(false) bool showingPrevious,
    @Default(false) bool starting,
    @Default(false) bool paging,
    @Default(false) bool stopping,
    String? error,
  }) = _GalleryScanState;

  GalleryScanSnapshot? get progress => latest ?? result;
  String? get scanId => latest?.scanId;
  bool get scanning => starting || latest?.status == .scanning;
  bool get hasUpdate => pendingResult != null;
  bool get canLoadMore =>
      result?.nextOffset != null &&
      switch (result?.status) {
        .completed || .partial || .cancelled => true,
        .unknown || .scanning || null => false,
      };
}

/// 每页独立拥有后台检查；可见集合与新终态分开，采用新集合由用户决定。
@riverpod
class GalleryScanNotifier extends _$GalleryScanNotifier {
  late _ScanOwner _owner;

  @override
  GalleryScanState build(DeviceSnapshot device, {required Object scope}) {
    final access = ref.watch(
      appDependenciesProvider.select((source) => source.gallery),
    );
    final previous = ref.read(galleryHistoryProvider.notifier).read(device);
    final owner = _owner = _ScanOwner(access, device.id);
    ref.onDispose(() {
      owner.disposed = true;
      owner.generation++;
      owner.poll?.cancel();
      if (owner.target case final target?) unawaited(_retire(owner, target));
    });
    return GalleryScanState(
      result: previous?.result,
      items: previous?.items ?? const [],
      showingPrevious: previous != null,
    );
  }

  bool _current(_ScanOwner owner, int generation) =>
      ref.mounted &&
      !owner.disposed &&
      identical(_owner, owner) &&
      owner.generation == generation;

  Future<void> start() async {
    final owner = _owner;
    if (!_current(owner, owner.generation)) return;
    final generation = ++owner.generation;
    owner.poll?.cancel();
    if (owner.target case final old?) unawaited(_retire(owner, old));
    owner.target = null;
    state = state.copyWith(
      starting: true,
      paging: false,
      stopping: false,
      latest: null,
      pendingResult: null,
      pendingItems: const [],
      showingPrevious: state.result != null,
      error: null,
    );
    GalleryScanTarget? admission;
    try {
      final pending = owner.access.startScan(owner.deviceId);
      // 超时、换源或离页后的迟到创建，也只能交还原来的能力实例。
      unawaited(
        pending.then<void>((next) {
          if (!_current(owner, generation)) {
            unawaited(_retire(owner, next.target));
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      final next = await pending.timeout(const Duration(seconds: 15));
      if (!_current(owner, generation)) return;
      if (next.deviceId == owner.deviceId && next.scanId.isNotEmpty) {
        admission = next.target;
      }
      _accept(owner, next, offset: 0);
      state = state.copyWith(starting: false);
      _schedule(owner, generation);
    } catch (failure) {
      if (_current(owner, generation)) {
        owner.generation++;
        if (admission case final target? when owner.target != target) {
          unawaited(_retire(owner, target));
        }
        state = state.copyWith(
          starting: false,
          paging: false,
          error: '相册检查未能开始：$failure',
        );
      }
    }
  }

  void _accept(
    _ScanOwner owner,
    GalleryScanSnapshot next, {
    required int offset,
    bool append = false,
  }) {
    final target = next.target;
    final status = next.status;
    if (target.scanId.isEmpty ||
        target.deviceId != owner.deviceId ||
        (append
            ? state.result?.target != target
            : owner.target != null && owner.target != target) ||
        next.offset != offset ||
        (append && status == .scanning) ||
        status == .unknown) {
      throw const RequestFailure('invalid_data', '相册结果归属或范围无法核验，请重新检查。');
    }
    if (append && state.items.length != offset) {
      throw const RequestFailure('invalid_data', '相册分页位置已变化，请重新检查。');
    }
    if (next.nextOffset case final cursor?
        when cursor <= offset || cursor != offset + next.items.length) {
      throw const RequestFailure('invalid_data', '相册分页位置无法核验，请重新检查。');
    }
    final combined = [if (append) ...state.items, ...next.items];
    final paths = combined.map((file) => file.path).toSet();
    if (paths.length != combined.length ||
        paths.contains(null) ||
        paths.contains('')) {
      throw const RequestFailure('invalid_data', '相册分页包含重复或无效项目，请重新检查。');
    }
    if (append) {
      state = state.copyWith(result: next, items: combined);
      return;
    }
    owner.target = target;
    var updated = state.copyWith(latest: next, error: null);
    if (state.showingPrevious) {
      if (status != .scanning) {
        updated = updated.copyWith(pendingResult: next, pendingItems: combined);
      }
    } else if (status == .scanning) {
      final seen = state.items.map((file) => file.path).toSet();
      updated = updated.copyWith(
        result: next,
        items: [
          ...state.items,
          ...next.items.where((file) => seen.add(file.path)),
        ],
      );
    } else if (state.result?.status == .scanning &&
        state.items.isNotEmpty &&
        (state.items.length != combined.length ||
            state.items.indexed.any((entry) {
              final (index, file) = entry;
              return file.path != combined[index].path;
            }))) {
      updated = updated.copyWith(
        showingPrevious: true,
        pendingResult: next,
        pendingItems: combined,
      );
    } else {
      updated = updated.copyWith(result: next, items: combined);
    }
    state = updated;
  }

  void _schedule(_ScanOwner owner, int generation) {
    if (_current(owner, generation) && state.scanning && !state.stopping) {
      owner.poll = Timer(
        const Duration(milliseconds: 400),
        () => unawaited(refresh()),
      );
    }
  }

  Future<void> refresh() async {
    final owner = _owner;
    if (!_current(owner, owner.generation)) return;
    if (owner.target case final target?) {
      await _page(owner, target, 0, append: false);
    }
  }

  Future<void> loadMore() async {
    final owner = _owner;
    if (!_current(owner, owner.generation)) return;
    final target = state.result?.target, offset = state.result?.nextOffset;
    if (target == null ||
        offset == null ||
        !state.canLoadMore ||
        state.paging ||
        state.stopping) {
      return;
    }
    state = state.copyWith(paging: true);
    await _page(owner, target, offset, append: true);
  }

  Future<void> _page(
    _ScanOwner owner,
    GalleryScanTarget target,
    int offset, {
    required bool append,
  }) async {
    final generation = owner.generation;
    final read = append ? ++owner.pagingRead : ++owner.read;
    if (!append) owner.poll?.cancel();
    try {
      final next = await owner.access
          .readScan(target, offset: offset)
          .timeout(const Duration(seconds: 15));
      if (!_current(owner, generation) ||
          read != (append ? owner.pagingRead : owner.read)) {
        return;
      }
      _accept(owner, next, offset: offset, append: append);
      if (append) state = state.copyWith(paging: false);
      if (!append) _schedule(owner, generation);
    } catch (failure) {
      if (_current(owner, generation) &&
          read == (append ? owner.pagingRead : owner.read)) {
        state = state.copyWith(
          paging: append ? false : state.paging,
          error: '相册检查未完成：$failure',
        );
      }
    }
  }

  Future<void> cancel() async {
    final owner = _owner, generation = owner.generation;
    if (!_current(owner, generation)) return;
    final target = owner.target;
    if (target == null || !state.scanning || state.stopping) return;
    ++owner.read;
    owner.poll?.cancel();
    state = state.copyWith(stopping: true);
    try {
      final next = await owner.access
          .cancelScan(target)
          .timeout(const Duration(seconds: 15));
      if (!_current(owner, generation)) return;
      _accept(owner, next, offset: 0);
      state = state.copyWith(stopping: false);
    } catch (failure) {
      if (_current(owner, generation)) {
        state = state.copyWith(stopping: false, error: '停止检查尚未确认：$failure');
      }
    }
  }

  void applyUpdate() {
    final owner = _owner;
    if (!_current(owner, owner.generation)) return;
    final next = state.pendingResult;
    if (next == null) return;
    ++owner.pagingRead;
    state = state.copyWith(
      paging: false,
      result: next,
      items: state.pendingItems,
      pendingResult: null,
      pendingItems: const [],
      showingPrevious: false,
    );
  }

  Future<void> _retire(_ScanOwner owner, GalleryScanTarget target) async {
    if (target.scanId.isEmpty || target.deviceId != owner.deviceId) return;
    try {
      await owner.access
          .cancelScan(target)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // 后端拥有有界的只读任务；未知的取消结果不触发重放。
    }
  }
}

final class _ScanOwner {
  _ScanOwner(this.access, this.deviceId);
  final GalleryScanner access;
  final String deviceId;
  bool disposed = false;
  int generation = 0, read = 0, pagingRead = 0;
  Timer? poll;
  GalleryScanTarget? target;
}
