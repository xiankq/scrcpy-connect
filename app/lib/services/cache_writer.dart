abstract interface class CacheWriter {
  String get leaseId;
  Future<void> close();
}
