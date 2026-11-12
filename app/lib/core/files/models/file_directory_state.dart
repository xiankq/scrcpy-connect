import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/file_directory_snapshot.dart';

part 'file_directory_state.freezed.dart';

@freezed
abstract class FileDirectoryState with _$FileDirectoryState {
  const FileDirectoryState._();
  const factory FileDirectoryState({
    FileDirectorySnapshot? data,
    @Default(true) bool loading,
    Object? error,
    @Default(0) int revision,
  }) = _FileDirectoryState;

  bool get verified => !loading && error == null && data != null;
}
