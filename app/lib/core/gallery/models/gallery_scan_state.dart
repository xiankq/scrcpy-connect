import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/gallery/models/gallery_scan.dart';

part 'gallery_scan_state.freezed.dart';

@freezed
abstract class GalleryScanState with _$GalleryScanState {
  const GalleryScanState._();
  const factory GalleryScanState({
    GalleryScanSnapshot? result,
    GalleryScanSnapshot? latest,
    GalleryScanSnapshot? pendingResult,
    @Default([]) List<FileCatalogEntry> items,
    @Default([]) List<FileCatalogEntry> pendingItems,
    @Default(false) bool showingPrevious,
    @Default(false) bool starting,
    @Default(false) bool paging,
    @Default(false) bool stopping,
    String? error,
  }) = _GalleryScanState;

  GalleryScanSnapshot? get progress => latest ?? result;
  String? get scanId => latest?.scanId;
  bool get scanning => starting || latest?.status == .scanning;
  bool get hasUpdate => pendingResult != null;
  bool get canLoadMore =>
      result?.nextOffset != null &&
      switch (result?.status) {
        .completed || .partial || .cancelled => true,
        .unknown || .scanning || null => false,
      };
}
