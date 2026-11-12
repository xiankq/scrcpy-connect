// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'background_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 只读取系统事实；权限申请只由页面的显式动作发起。

@ProviderFor(backgroundStatus)
final backgroundStatusProvider = BackgroundStatusProvider._();

/// 只读取系统事实；权限申请只由页面的显式动作发起。

final class BackgroundStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<BackgroundStatus>,
          BackgroundStatus,
          FutureOr<BackgroundStatus>
        >
    with $FutureModifier<BackgroundStatus>, $FutureProvider<BackgroundStatus> {
  /// 只读取系统事实；权限申请只由页面的显式动作发起。
  BackgroundStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'backgroundStatusProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backgroundStatusHash();

  @$internal
  @override
  $FutureProviderElement<BackgroundStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<BackgroundStatus> create(Ref ref) {
    return backgroundStatus(ref);
  }
}

String _$backgroundStatusHash() => r'8dc1a4fbd3ed82f862fcd2e2bf06b41efb9801b1';
