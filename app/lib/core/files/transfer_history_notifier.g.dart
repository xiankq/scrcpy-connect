// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'transfer_history_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TransferHistoryNotifier)
final transferHistoryProvider = TransferHistoryNotifierProvider._();

final class TransferHistoryNotifierProvider
    extends
        $NotifierProvider<
          TransferHistoryNotifier,
          FileTransferQueryState<FileTransferCollection>
        > {
  TransferHistoryNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transferHistoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transferHistoryNotifierHash();

  @$internal
  @override
  TransferHistoryNotifier create() => TransferHistoryNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    FileTransferQueryState<FileTransferCollection> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<FileTransferQueryState<FileTransferCollection>>(
            value,
          ),
    );
  }
}

String _$transferHistoryNotifierHash() =>
    r'e3769104766880adac45d27074a2f78663ceb07f';

abstract class _$TransferHistoryNotifier
    extends $Notifier<FileTransferQueryState<FileTransferCollection>> {
  FileTransferQueryState<FileTransferCollection> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              FileTransferQueryState<FileTransferCollection>,
              FileTransferQueryState<FileTransferCollection>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                FileTransferQueryState<FileTransferCollection>,
                FileTransferQueryState<FileTransferCollection>
              >,
              FileTransferQueryState<FileTransferCollection>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
