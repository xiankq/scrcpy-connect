import 'package:freezed_annotation/freezed_annotation.dart';

part 'background_status.freezed.dart';
part 'background_status.g.dart';

@freezed
abstract class BackgroundStatus with _$BackgroundStatus {
  // Freezed 将构造器上的序列化选项转给生成类。
  // ignore: invalid_annotation_target
  @JsonSerializable(checked: true)
  const factory BackgroundStatus({
    @Default(false) bool supported,
    @Default(false) bool canRequest,
    @Default(false) bool running,
    @Default(false) bool stopped,
    bool? connectionRequested,
    bool? audioRequested,
    bool? mediaPlaybackReady,
    bool? notificationPermission,
    bool? requested,
    String? platform,
    @Default('系统后台条件') String title,
    @Default('尚未确认本机后台能力。请保持 App 在前台，并核对活动的实际状态。') String reason,
  }) = _BackgroundStatus;

  factory BackgroundStatus.fromJson(Map<String, dynamic> json) =>
      _$BackgroundStatusFromJson(json);
}
