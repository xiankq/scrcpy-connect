import 'package:scrcpy_connect/core/files/models/file_publication_receipt.dart';

enum SharePublicationStatus { publishing, published, unknown }

final class ShareLeaseRecord {
  const ShareLeaseRecord({
    required this.id,
    required this.shareId,
    this.transferId,
    this.request,
    this.publication,
    this.receipt,
  });

  factory ShareLeaseRecord.fromJson(Map<String, dynamic> value) =>
      ShareLeaseRecord(
        id: value['id'] as String,
        shareId: value['shareId'] as String,
        transferId: value['transferId'] as String?,
        request: value['request'] as String?,
        publication: value['publication'] == null
            ? null
            : SharePublicationStatus.values.byName(
                value['publication'] as String,
              ),
        receipt: value['receipt'] == null
            ? null
            : FilePublicationReceipt.fromJson(
                Map<String, Object?>.from(value['receipt'] as Map),
              ),
      );

  final String id, shareId;
  final String? transferId, request;
  final SharePublicationStatus? publication;
  final FilePublicationReceipt? receipt;

  ShareLeaseRecord copyWith({
    String? transferId,
    String? request,
    SharePublicationStatus? publication,
    FilePublicationReceipt? receipt,
  }) => ShareLeaseRecord(
    id: id,
    shareId: shareId,
    transferId: transferId ?? this.transferId,
    request: request ?? this.request,
    publication: publication ?? this.publication,
    receipt: receipt ?? this.receipt,
  );

  ShareLeaseRecord reset() => ShareLeaseRecord(id: id, shareId: shareId);

  Map<String, dynamic> toJson() => {
    'version': 2,
    'id': id,
    'shareId': shareId,
    'transferId': transferId,
    'request': request,
    'publication': publication?.name,
    'receipt': receipt?.toJson(),
  };
}
