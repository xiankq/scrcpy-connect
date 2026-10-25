import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64Util;

import 'package:adb/adb.dart';

import 'generated/third_party/interop_adb_api/api.dart' as native;

/// 当前动态库的本机文件绑定；普通 Dart 接口不暴露生成对象。
final class FrbNativeLocalFiles implements NativeLocalFilesApi {
  const FrbNativeLocalFiles();

  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      if (error is LocalFileException) rethrow;
      if (error is native.LocalFileError) {
        throw LocalFileException(
          LocalFileErrorCode.values.byName(error.code.name),
          error.message,
          bytesCopied: error.bytesCopied.toInt(),
          partialDestinationPossible: error.partialDestinationPossible,
        );
      }
      // 未获得类型化 native 回执时，不把跨语言错误冒充文件未写入。
      throw LocalFileException(
        LocalFileErrorCode.resultUnknown,
        error.toString(),
        partialDestinationPossible: true,
      );
    }
  }

  LocalFileIdentity _identity(native.LocalFileIdentity value) =>
      LocalFileIdentity(
        device: value.device,
        inode: value.inode,
        size: value.size,
        modifiedSeconds: value.modifiedSeconds.toInt(),
        modifiedNanos: value.modifiedNanos,
        kind: LocalFileKind.values.byName(value.kind.name),
      );
  native.LocalFileIdentity _nativeIdentity(LocalFileIdentity value) =>
      native.LocalFileIdentity(
        device: value.device,
        inode: value.inode,
        size: value.size,
        modifiedSeconds: PlatformInt64Util.from(value.modifiedSeconds),
        modifiedNanos: value.modifiedNanos,
        kind: native.LocalFileKind.values.byName(value.kind.name),
      );

  @override
  Future<String> openScope(
    String scopeKey,
    List<Uint8List> allowedRoots,
    int closeTimeoutMs,
  ) => _call(
    () => native.adbLocalScopeOpen(
      ownerKey: scopeKey,
      closeTimeoutMs: closeTimeoutMs,
      roots: allowedRoots,
    ),
  );
  @override
  Future<void> closeScope(String scopeId, int timeoutMs) => _call(
    () => native.adbLocalScopeClose(scopeId: scopeId, timeoutMs: timeoutMs),
  );
  @override
  Future<LocalFileStat> stat(String scopeId, Uint8List path) async {
    final value = await _call(
      () => native.adbLocalStat(scopeId: scopeId, path: path),
    );
    return LocalFileStat(
      identity: _identity(value.identity),
      freeBytes: value.freeBytes,
    );
  }

  @override
  Future<LocalFileList> list(
    String scopeId,
    Uint8List path,
    int maxEntries,
  ) async {
    final value = await _call(
      () => native.adbLocalList(
        scopeId: scopeId,
        path: path,
        maxEntries: maxEntries,
      ),
    );
    return LocalFileList(
      identity: _identity(value.identity),
      entries: [
        for (final entry in value.entries)
          LocalFileEntry(name: entry.name, identity: _identity(entry.identity)),
      ],
    );
  }

  @override
  Future<void> mkdir(String scopeId, Uint8List path, bool exclusive) => _call(
    () => native.adbLocalMkdir(
      scopeId: scopeId,
      path: path,
      exclusive: exclusive,
    ),
  );
  @override
  Future<void> remove(
    String scopeId,
    Uint8List path,
    LocalFileIdentity expectedIdentity,
  ) => _call(
    () => native.adbLocalRemove(
      scopeId: scopeId,
      path: path,
      expected: _nativeIdentity(expectedIdentity),
    ),
  );
  @override
  Future<String> createCopy(String scopeId, LocalFileCopyRequest request) =>
      _call(
        () => native.adbLocalCopyCreate(
          scopeId: scopeId,
          request: native.LocalFileCopyRequest(
            sourcePath: request.source.pathBytes,
            sourceFd: request.source.descriptor,
            targetPath: request.target.pathBytes,
            targetFd: request.target.descriptor,
            sourceOffset: BigInt.from(request.sourceOffset),
            length: request.length == null
                ? null
                : BigInt.from(request.length!),
            expectedSource: request.expectedSource == null
                ? null
                : _nativeIdentity(request.expectedSource!),
            maxBytes: BigInt.from(request.maxBytes),
            timeoutMs: request.timeoutMs,
          ),
        ),
      );
  @override
  Future<LocalFileCopyResult> runCopy(String copyId) async {
    final value = await _call(() => native.adbLocalCopyRun(copyId: copyId));
    return LocalFileCopyResult(
      bytes: value.bytes.toInt(),
      identity: _identity(value.identity),
      sourceIdentity: _identity(value.sourceIdentity),
    );
  }

  @override
  Future<void> cancelCopy(String copyId) =>
      _call(() => native.adbLocalCopyCancel(copyId: copyId));
  @override
  Future<void> closeCopy(String copyId, int timeoutMs) => _call(
    () => native.adbLocalCopyClose(copyId: copyId, timeoutMs: timeoutMs),
  );
  @override
  Future<LocalFileIdentity> commit(
    String scopeId,
    String copyId,
    Uint8List destination,
    LocalFileIdentity expectedIdentity,
  ) async => _identity(
    await _call(
      () => native.adbLocalCommit(
        scopeId: scopeId,
        copyId: copyId,
        destination: destination,
        expectedIdentity: _nativeIdentity(expectedIdentity),
      ),
    ),
  );
}
