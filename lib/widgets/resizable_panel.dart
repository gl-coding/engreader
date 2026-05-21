import 'package:flutter/material.dart';

class ResizablePanel extends StatefulWidget {
  final Widget child;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;
  final bool resizeFromLeft;

  const ResizablePanel({
    super.key,
    required this.child,
    this.initialWidth = 320,
    this.minWidth = 200,
    this.maxWidth = 600,
    this.resizeFromLeft = true,
  });

  @override
  State<ResizablePanel> createState() => ResizablePanelState();
}

class ResizablePanelState extends State<ResizablePanel> {
  late double _width;

  double get width => _width;

  @override
  void initState() {
    super.initState();
    _width = widget.initialWidth;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: _width,
      child: Row(
        children: [
          if (widget.resizeFromLeft)
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _width = (_width - details.delta.dx)
                        .clamp(widget.minWidth, widget.maxWidth);
                  });
                },
                child: Container(
                  width: 6,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 1,
                      color: colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: widget.child),
          if (!widget.resizeFromLeft)
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _width = (_width + details.delta.dx)
                        .clamp(widget.minWidth, widget.maxWidth);
                  });
                },
                child: Container(
                  width: 6,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 1,
                      color: colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
