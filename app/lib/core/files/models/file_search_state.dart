import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/file_search_snapshot.dart';

part 'file_search_state.freezed.dart';

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
