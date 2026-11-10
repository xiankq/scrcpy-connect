// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'thumbnail_queue.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(thumbnailQueue)
final thumbnailQueueProvider = ThumbnailQueueFamily._();

final class ThumbnailQueueProvider
    extends $FunctionalProvider<ThumbnailQueue, ThumbnailQueue, ThumbnailQueue>
    with $Provider<ThumbnailQueue> {
  ThumbnailQueueProvider._({
    required ThumbnailQueueFamily super.from,
    required (AppStore, String) super.argument,
  }) : super(
         retry: null,
         name: r'thumbnailQueueProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$thumbnailQueueHash();

  @override
  String toString() {
    return r'thumbnailQueueProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<ThumbnailQueue> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThumbnailQueue create(Ref ref) {
    final argument = this.argument as (AppStore, String);
    return thumbnailQueue(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThumbnailQueue value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThumbnailQueue>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThumbnailQueueProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$thumbnailQueueHash() => r'384d63013bdcf6973d3c9e37d2d4eaa340e5fbf3';

final class ThumbnailQueueFamily extends $Family
    with $FunctionalFamilyOverride<ThumbnailQueue, (AppStore, String)> {
  ThumbnailQueueFamily._()
    : super(
        retry: null,
        name: r'thumbnailQueueProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ThumbnailQueueProvider call(AppStore controller, String deviceId) =>
      ThumbnailQueueProvider._(argument: (controller, deviceId), from: this);

  @override
  String toString() => r'thumbnailQueueProvider';
}
