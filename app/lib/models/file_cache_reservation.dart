class FileCacheReservation {
  const FileCacheReservation(
    this.path,
    this.bytes, {
    this.name,
    this.sourceLabel,
    this.sourcePath,
  });
  final String path;
  final int bytes;
  final String? name, sourceLabel, sourcePath;
}
