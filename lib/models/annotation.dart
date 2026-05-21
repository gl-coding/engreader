class Annotation {
  final String id;
  final String selectedText;
  final String translation;
  final AnnotationType type;
  final int pageIndex;
  final double yPosition;
  final DateTime createdAt;

  Annotation({
    required this.id,
    required this.selectedText,
    required this.translation,
    required this.type,
    required this.pageIndex,
    required this.yPosition,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'selectedText': selectedText,
        'translation': translation,
        'type': type.name,
        'pageIndex': pageIndex,
        'yPosition': yPosition,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Annotation.fromJson(Map<String, dynamic> json) => Annotation(
        id: json['id'] as String,
        selectedText: json['selectedText'] as String,
        translation: json['translation'] as String,
        type: AnnotationType.values.byName(json['type'] as String),
        pageIndex: json['pageIndex'] as int,
        yPosition: (json['yPosition'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

enum AnnotationType {
  word,
  sentence,
}
