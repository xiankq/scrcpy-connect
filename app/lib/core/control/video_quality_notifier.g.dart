// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'video_quality_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

@ProviderFor(VideoQualityNotifier)
final videoQualityProvider = VideoQualityNotifierFamily._();

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。
final class VideoQualityNotifierProvider
    extends $NotifierProvider<VideoQualityNotifier, VideoQualityState> {
  /// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。
  VideoQualityNotifierProvider._({
    required VideoQualityNotifierFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'videoQualityProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$videoQualityNotifierHash();

  @override
  String toString() {
    return r'videoQualityProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  VideoQualityNotifier create() => VideoQualityNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VideoQualityState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VideoQualityState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VideoQualityNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$videoQualityNotifierHash() =>
    r'7b79b37531affc494bc5114c2963d1305089f5c2';

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

final class VideoQualityNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          VideoQualityNotifier,
          VideoQualityState,
          VideoQualityState,
          VideoQualityState,
          String
        > {
  VideoQualityNotifierFamily._()
    : super(
        retry: null,
        name: r'videoQualityProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

  VideoQualityNotifierProvider call({required String deviceId}) =>
      VideoQualityNotifierProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'videoQualityProvider';
}

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

abstract class _$VideoQualityNotifier extends $Notifier<VideoQualityState> {
  late final _$args = ref.$arg as String;
  String get deviceId => _$args;

  VideoQualityState build({required String deviceId});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VideoQualityState, VideoQualityState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VideoQualityState, VideoQualityState>,
              VideoQualityState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(deviceId: _$args));
  }
}
