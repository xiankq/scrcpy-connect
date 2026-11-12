import 'package:freezed_annotation/freezed_annotation.dart';

part 'share_submission_state.freezed.dart';

@freezed
abstract class ShareSubmissionState with _$ShareSubmissionState {
  const factory ShareSubmissionState({
    @Default(false) bool busy,
    @Default(false) bool pushed,
    @Default(false) bool copied,
    @Default(false) bool completed,
    @Default(false) bool showTransfers,
    String? error,
  }) = _ShareSubmissionState;
}
