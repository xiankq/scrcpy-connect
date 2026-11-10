final class SharedSourceFile {
  const SharedSourceFile({
    required this.diskName,
    required this.name,
    required this.size,
    this.directory = false,
  });
  final String diskName, name;
  final int size;
  final bool directory;
  Map<String, dynamic> toJson() => {
    'diskName': diskName,
    'name': name,
    'size': size,
    if (directory) 'directory': true,
  };
}
