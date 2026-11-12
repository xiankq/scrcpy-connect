import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/app_dependencies_provider.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';

import 'file_search.dart';

part 'file_search_notifier.freezed.dart';
part 'file_search_notifier.g.dart';

@freezed
abstract class FileSearchState with _$FileSearchState {
  const FileSearchState._();
  const factory FileSearchState({
    FileSearchSnapshot? result,
    String? error,
    @Default(false) bool starting,
    @Default(false) bool stopping,
  }) = _FileSearchState;

  String? get searchId => result?.searchId;
  bool get running => starting || result?.status == .running;
}

/// 每个页面 scope 独立拥有搜索、轮询与原任务的取消责任。
@riverpod
class FileSearchNotifier extends _$FileSearchNotifier {
  late _SearchOwner _owner;

  @override
  FileSearchState build(String deviceId, {required Object scope}) {
    final access = ref.watch(
      appDependenciesProvider.select((source) => source.fileSearch),
    );
    final owner = _owner = _SearchOwner(access, deviceId);
    ref.onDispose(() {
      owner.disposed = true;
      owner.generation++;
      owner.poll?.cancel();
      if (owner.target case final target? when owner.needsCancel) {
        unawaited(_retire(owner, target));
      }
    });
    return const FileSearchState();
  }

  bool _current(_SearchOwner owner, int generation) =>
      ref.mounted &&
      !owner.disposed &&
      identical(_owner, owner) &&
      owner.generation == generation;

  Future<void> start(
    String query,
    FileCatalogFilter filter, {
    required String path,
  }) async {
    final owner = _owner;
    if (!_current(owner, owner.generation)) return;
    final generation = ++owner.generation;
    owner.poll?.cancel();
    if (owner.target case final previous? when owner.needsCancel) {
      unawaited(_retire(owner, previous));
    }
    owner.target = null;
    owner.needsCancel = false;
    state = const FileSearchState(starting: true);
    try {
      final next = await owner.access.startSearch(
        owner.deviceId,
        path: path,
        query: query,
        filter: filter,
      );
      if (next.deviceId != owner.deviceId ||
          next.path != path ||
          next.searchId.isEmpty) {
        throw const RequestFailure('invalid_data', '搜索归属无法核验，请重新搜索。');
      }
      if (!_current(owner, generation)) {
        await _retire(owner, next.target);
        return;
      }
      owner.target = next.target;
      owner.needsCancel = next.status == .running;
      state = FileSearchState(result: next);
      await _refresh(owner, generation, next.target);
    } catch (error) {
      if (_current(owner, generation)) {
        state = state.copyWith(starting: false, error: '$error');
      }
    }
  }

  Future<void> refresh() async {
    final owner = _owner;
    if (!_current(owner, owner.generation)) return;
    if (owner.target case final target?) {
      await _refresh(owner, owner.generation, target);
    }
  }

  Future<void> _refresh(
    _SearchOwner owner,
    int generation,
    FileSearchTarget target,
  ) async {
    if (!_current(owner, generation)) return;
    final readGeneration = ++owner.readGeneration;
    owner.poll?.cancel();
    try {
      final next = await owner.access.readSearch(target);
      if (!_current(owner, generation) ||
          readGeneration != owner.readGeneration) {
        return;
      }
      if (next.target != target) {
        throw const RequestFailure('invalid_data', '搜索结果归属无法核验，未显示其他范围的内容。');
      }
      owner.needsCancel = next.status == .running;
      state = state.copyWith(
        result: next,
        error: null,
        stopping: state.stopping && next.status == .running,
      );
      if (next.status == .running) {
        owner.poll = Timer(
          const Duration(milliseconds: 400),
          () => unawaited(_refresh(owner, generation, target)),
        );
      }
    } catch (error) {
      if (_current(owner, generation) &&
          readGeneration == owner.readGeneration) {
        state = state.copyWith(error: '$error');
      }
    }
  }

  Future<void> cancel() async {
    final owner = _owner, generation = owner.generation;
    if (!_current(owner, generation)) return;
    final target = owner.target;
    if (target == null || !state.running || state.stopping) return;
    state = state.copyWith(stopping: true, error: null);
    try {
      await owner.access.cancelSearch(target);
      if (_current(owner, generation)) {
        await _refresh(owner, generation, target);
      }
    } catch (error) {
      if (_current(owner, generation)) {
        state = state.copyWith(stopping: false, error: '停止搜索未确认：$error');
      }
    }
  }

  Future<void> _retire(_SearchOwner owner, FileSearchTarget target) async {
    try {
      await owner.access.cancelSearch(target);
    } catch (_) {
      // 后端拥有只读任务和截止时间；离开页面不重放未知操作。
    }
  }
}

/// 这里只保留执行代次与回收句柄；可呈现状态由 Riverpod 独占。
final class _SearchOwner {
  _SearchOwner(this.access, this.deviceId);
  final FileSearch access;
  final String deviceId;
  bool disposed = false, needsCancel = false;
  int generation = 0, readGeneration = 0;
  FileSearchTarget? target;
  Timer? poll;
}
