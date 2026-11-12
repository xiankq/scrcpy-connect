// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'audio_sources_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(audioSources)
final audioSourcesProvider = AudioSourcesFamily._();

final class AudioSourcesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DeviceAudioSnapshot>>,
          List<DeviceAudioSnapshot>,
          FutureOr<List<DeviceAudioSnapshot>>
        >
    with
        $FutureModifier<List<DeviceAudioSnapshot>>,
        $FutureProvider<List<DeviceAudioSnapshot>> {
  AudioSourcesProvider._({
    required AudioSourcesFamily super.from,
    required String? super.argument,
  }) : super(
         retry: _noRetry,
         name: r'audioSourcesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$audioSourcesHash();

  @override
  String toString() {
    return r'audioSourcesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<DeviceAudioSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DeviceAudioSnapshot>> create(Ref ref) {
    final argument = this.argument as String?;
    return audioSources(ref, deviceId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AudioSourcesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$audioSourcesHash() => r'ac38ea63076bb189183ca89be1bec079eae5da18';

final class AudioSourcesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<DeviceAudioSnapshot>>,
          String?
        > {
  AudioSourcesFamily._()
    : super(
        retry: _noRetry,
        name: r'audioSourcesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AudioSourcesProvider call({String? deviceId}) =>
      AudioSourcesProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'audioSourcesProvider';
}
