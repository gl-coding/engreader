import 'package:flutter/material.dart';
import 'package:engreader/models/annotation.dart';

class AnnotationPanel extends StatelessWidget {
  final List<Annotation> annotations;
  final void Function(String id) onDelete;

  const AnnotationPanel({
    super.key,
    required this.annotations,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.sticky_note_2_outlined,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '批注',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Text(
                  '${annotations.length}',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: annotations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app_outlined,
                            size: 40,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          '选中文本添加批注',
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: annotations.length,
                    itemBuilder: (context, index) {
                      final annotation = annotations[index];
                      return _AnnotationCard(
                        annotation: annotation,
                        onDelete: () => onDelete(annotation.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AnnotationCard extends StatelessWidget {
  final Annotation annotation;
  final VoidCallback onDelete;

  const _AnnotationCard({
    required this.annotation,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWord = annotation.type == AnnotationType.word;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isWord
                        ? Colors.blue.withValues(alpha: 0.1)
                        : Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isWord ? '单词' : '句子',
                    style: TextStyle(
                      fontSize: 10,
                      color: isWord ? Colors.blue : Colors.purple,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: onDelete,
                  child: Icon(Icons.close,
                      size: 16, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '「${annotation.selectedText}」',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: colorScheme.primary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              annotation.translation,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
