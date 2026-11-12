// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'audio_sources_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

@ProviderFor(AudioSourcesNotifier)
final audioSourcesProvider = AudioSourcesNotifierFamily._();

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。
final class AudioSourcesNotifierProvider
    extends $NotifierProvider<AudioSourcesNotifier, AudioSourcesState> {
  /// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。
  AudioSourcesNotifierProvider._({
    required AudioSourcesNotifierFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'audioSourcesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$audioSourcesNotifierHash();

  @override
  String toString() {
    return r'audioSourcesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AudioSourcesNotifier create() => AudioSourcesNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AudioSourcesState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AudioSourcesState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AudioSourcesNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$audioSourcesNotifierHash() =>
    r'f7771c85405405f3fc7aed754977439206ba6cfb';

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

final class AudioSourcesNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          AudioSourcesNotifier,
          AudioSourcesState,
          AudioSourcesState,
          AudioSourcesState,
          String?
        > {
  AudioSourcesNotifierFamily._()
    : super(
        retry: null,
        name: r'audioSourcesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

  AudioSourcesNotifierProvider call({String? deviceId}) =>
      AudioSourcesNotifierProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'audioSourcesProvider';
}

/// 同 scope、同查询共享一次读取和事件订阅；最后一个消费者离开后释放。

abstract class _$AudioSourcesNotifier extends $Notifier<AudioSourcesState> {
  late final _$args = ref.$arg as String?;
  String? get deviceId => _$args;

  AudioSourcesState build({String? deviceId});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AudioSourcesState, AudioSourcesState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AudioSourcesState, AudioSourcesState>,
              AudioSourcesState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(deviceId: _$args));
  }
}
