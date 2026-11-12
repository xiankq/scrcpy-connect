// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'thumbnail_queue_provider.dart';

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
    required String super.argument,
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
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ThumbnailQueue> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThumbnailQueue create(Ref ref) {
    final argument = this.argument as String;
    return thumbnailQueue(ref, argument);
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

String _$thumbnailQueueHash() => r'ed867ed7fc7505466fce90b306082670a9fb42e5';

final class ThumbnailQueueFamily extends $Family
    with $FunctionalFamilyOverride<ThumbnailQueue, String> {
  ThumbnailQueueFamily._()
    : super(
        retry: null,
        name: r'thumbnailQueueProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ThumbnailQueueProvider call(String deviceId) =>
      ThumbnailQueueProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'thumbnailQueueProvider';
}
