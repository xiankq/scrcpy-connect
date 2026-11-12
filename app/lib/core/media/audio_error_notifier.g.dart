// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'audio_error_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AudioErrorNotifier)
final audioErrorProvider = AudioErrorNotifierProvider._();

final class AudioErrorNotifierProvider
    extends $NotifierProvider<AudioErrorNotifier, String?> {
  AudioErrorNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'audioErrorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$audioErrorNotifierHash();

  @$internal
  @override
  AudioErrorNotifier create() => AudioErrorNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$audioErrorNotifierHash() =>
    r'a6db488d496c1e57d6adf6ff70cdd8b298e5b08e';

abstract class _$AudioErrorNotifier extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
