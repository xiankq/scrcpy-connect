import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/document_outcome.dart';

part 'document_operation_state.freezed.dart';

/// 当前文档表单的只读状态；系统任务和来源租约不属于状态快照。
@freezed
abstract class DocumentOperationState with _$DocumentOperationState {
  const factory DocumentOperationState({
    @Default(false) bool loaded,
    @Default(false) bool refreshing,
    @Default(false) bool busy,
    @Default(false) bool cancelling,
    String? operationId,
    String? recordOperationId,
    DocumentOutcome? result,
    String? error,
  }) = _DocumentOperationState;
}
