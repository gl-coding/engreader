import 'package:flutter/material.dart';
import 'package:engreader/models/annotation.dart';

class AnnotationPanel extends StatefulWidget {
  final List<Annotation> annotations;
  final void Function(String id) onDelete;
  final VoidCallback? onClearAll;

  const AnnotationPanel({
    super.key,
    required this.annotations,
    required this.onDelete,
    this.onClearAll,
  });

  @override
  State<AnnotationPanel> createState() => _AnnotationPanelState();
}

class _AnnotationPanelState extends State<AnnotationPanel> {
  final Set<String> _expandedIds = {};

  void _collapseAll() {
    setState(() => _expandedIds.clear());
  }

  void _expandAll() {
    setState(() {
      for (final a in widget.annotations) {
        _expandedIds.add(a.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 52, 8, 8),
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
                const SizedBox(width: 6),
                Text(
                  '${widget.annotations.length}',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                if (widget.annotations.isNotEmpty) ...[
                  _ActionButton(
                    icon: Icons.unfold_more,
                    label: '展开',
                    onTap: _expandAll,
                  ),
                  const SizedBox(width: 4),
                  _ActionButton(
                    icon: Icons.unfold_less,
                    label: '折叠',
                    onTap: _collapseAll,
                  ),
                  const SizedBox(width: 4),
                  _ActionButton(
                    icon: Icons.delete_sweep_outlined,
                    label: '清除',
                    onTap: widget.onClearAll,
                    color: Colors.red,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.annotations.isEmpty
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
                    itemCount: widget.annotations.length,
                    itemBuilder: (context, index) {
                      final annotation = widget.annotations[index];
                      final isExpanded =
                          _expandedIds.contains(annotation.id);
                      return _AnnotationCard(
                        annotation: annotation,
                        isExpanded: isExpanded,
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedIds.remove(annotation.id);
                            } else {
                              _expandedIds.add(annotation.id);
                            }
                          });
                        },
                        onDelete: () => widget.onDelete(annotation.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }
}

class _AnnotationCard extends StatelessWidget {
  final Annotation annotation;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AnnotationCard({
    required this.annotation,
    required this.isExpanded,
    required this.onTap,
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
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      annotation.selectedText,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onDelete,
                    child: Icon(Icons.close,
                        size: 14, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (isExpanded && annotation.translation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  annotation.translation,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
