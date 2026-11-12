// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'transfer_details_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TransferDetailsNotifier)
final transferDetailsProvider = TransferDetailsNotifierFamily._();

final class TransferDetailsNotifierProvider
    extends
        $NotifierProvider<
          TransferDetailsNotifier,
          FileTransferQueryState<FileTransferSnapshot>
        > {
  TransferDetailsNotifierProvider._({
    required TransferDetailsNotifierFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'transferDetailsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$transferDetailsNotifierHash();

  @override
  String toString() {
    return r'transferDetailsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TransferDetailsNotifier create() => TransferDetailsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    FileTransferQueryState<FileTransferSnapshot> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<FileTransferQueryState<FileTransferSnapshot>>(
            value,
          ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TransferDetailsNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$transferDetailsNotifierHash() =>
    r'bb2e4adba0f7dd1cab94febd1db86f5cc7dcf0b8';

final class TransferDetailsNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          TransferDetailsNotifier,
          FileTransferQueryState<FileTransferSnapshot>,
          FileTransferQueryState<FileTransferSnapshot>,
          FileTransferQueryState<FileTransferSnapshot>,
          String
        > {
  TransferDetailsNotifierFamily._()
    : super(
        retry: null,
        name: r'transferDetailsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TransferDetailsNotifierProvider call(String id) =>
      TransferDetailsNotifierProvider._(argument: id, from: this);

  @override
  String toString() => r'transferDetailsProvider';
}

abstract class _$TransferDetailsNotifier
    extends $Notifier<FileTransferQueryState<FileTransferSnapshot>> {
  late final _$args = ref.$arg as String;
  String get id => _$args;

  FileTransferQueryState<FileTransferSnapshot> build(String id);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              FileTransferQueryState<FileTransferSnapshot>,
              FileTransferQueryState<FileTransferSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                FileTransferQueryState<FileTransferSnapshot>,
                FileTransferQueryState<FileTransferSnapshot>
              >,
              FileTransferQueryState<FileTransferSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
