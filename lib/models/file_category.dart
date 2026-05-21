class FileCategory {
  final String id;
  final String name;
  final String icon;
  final List<String> filePaths;

  FileCategory({
    required this.id,
    required this.name,
    this.icon = 'folder',
    List<String>? filePaths,
  }) : filePaths = filePaths ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'filePaths': filePaths,
      };

  factory FileCategory.fromJson(Map<String, dynamic> json) => FileCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String? ?? 'folder',
        filePaths: (json['filePaths'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

  FileCategory copyWith({
    String? name,
    String? icon,
    List<String>? filePaths,
  }) =>
      FileCategory(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        filePaths: filePaths ?? this.filePaths,
      );
}
