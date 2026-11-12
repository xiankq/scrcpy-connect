// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'video_quality_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(videoQuality)
final videoQualityProvider = VideoQualityFamily._();

final class VideoQualityProvider
    extends
        $FunctionalProvider<
          AsyncValue<VideoQualityOptions>,
          VideoQualityOptions,
          FutureOr<VideoQualityOptions>
        >
    with
        $FutureModifier<VideoQualityOptions>,
        $FutureProvider<VideoQualityOptions> {
  VideoQualityProvider._({
    required VideoQualityFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'videoQualityProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$videoQualityHash();

  @override
  String toString() {
    return r'videoQualityProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<VideoQualityOptions> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<VideoQualityOptions> create(Ref ref) {
    final argument = this.argument as String;
    return videoQuality(ref, deviceId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is VideoQualityProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$videoQualityHash() => r'379967183c0aed0f92f436c430302cf981599b59';

final class VideoQualityFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<VideoQualityOptions>, String> {
  VideoQualityFamily._()
    : super(
        retry: _noRetry,
        name: r'videoQualityProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  VideoQualityProvider call({required String deviceId}) =>
      VideoQualityProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'videoQualityProvider';
}
