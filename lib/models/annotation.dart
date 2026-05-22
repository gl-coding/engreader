class Annotation {
  final String id;
  final String selectedText;
  final String translation;
  final AnnotationType type;
  final int pageIndex;
  final double yPosition;
  final DateTime createdAt;

  /// Character offset start within the page (PDF) or full text (TXT).
  final int? charStart;

  /// Character offset end.
  final int? charEnd;

  /// EPUB CFI range for precise positioning.
  final String? cfiRange;

  Annotation({
    required this.id,
    required this.selectedText,
    required this.translation,
    required this.type,
    required this.pageIndex,
    required this.yPosition,
    this.charStart,
    this.charEnd,
    this.cfiRange,
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
        if (charStart != null) 'charStart': charStart,
        if (charEnd != null) 'charEnd': charEnd,
        if (cfiRange != null) 'cfiRange': cfiRange,
      };

  factory Annotation.fromJson(Map<String, dynamic> json) => Annotation(
        id: json['id'] as String,
        selectedText: json['selectedText'] as String,
        translation: json['translation'] as String,
        type: AnnotationType.values.byName(json['type'] as String),
        pageIndex: json['pageIndex'] as int,
        yPosition: (json['yPosition'] as num).toDouble(),
        charStart: json['charStart'] as int?,
        charEnd: json['charEnd'] as int?,
        cfiRange: json['cfiRange'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

enum AnnotationType {
  word,
  sentence,
}
