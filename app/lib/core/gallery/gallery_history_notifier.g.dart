// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'gallery_history_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同一应用 scope 的已核验相册历史，最多保留八台设备。

@ProviderFor(GalleryHistoryNotifier)
final galleryHistoryProvider = GalleryHistoryNotifierProvider._();

/// 同一应用 scope 的已核验相册历史，最多保留八台设备。
final class GalleryHistoryNotifierProvider
    extends
        $NotifierProvider<
          GalleryHistoryNotifier,
          Map<String, GalleryHistoryEntry>
        > {
  /// 同一应用 scope 的已核验相册历史，最多保留八台设备。
  GalleryHistoryNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'galleryHistoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$galleryHistoryNotifierHash();

  @$internal
  @override
  GalleryHistoryNotifier create() => GalleryHistoryNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, GalleryHistoryEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, GalleryHistoryEntry>>(
        value,
      ),
    );
  }
}

String _$galleryHistoryNotifierHash() =>
    r'82955ea08202a8169097fca027bb920f6823b2e8';

/// 同一应用 scope 的已核验相册历史，最多保留八台设备。

abstract class _$GalleryHistoryNotifier
    extends $Notifier<Map<String, GalleryHistoryEntry>> {
  Map<String, GalleryHistoryEntry> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, GalleryHistoryEntry>,
              Map<String, GalleryHistoryEntry>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, GalleryHistoryEntry>,
                Map<String, GalleryHistoryEntry>
              >,
              Map<String, GalleryHistoryEntry>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
