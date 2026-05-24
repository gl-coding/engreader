import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:engreader/services/settings_service.dart';

class TxtReaderView extends StatefulWidget {
  final String filePath;
  final String content;
  final Future<void> Function(String text, double yPosition,
      {int? charStart, int? charEnd}) onAnnotateConfirmed;
  final Future<void> Function(String text, String question, double yPosition,
      {int? charStart, int? charEnd})? onAskConfirmed;
  final List<String> highlightedTexts;
  final List<({int start, int end})> highlightRanges;

  const TxtReaderView({
    super.key,
    required this.filePath,
    required this.content,
    required this.onAnnotateConfirmed,
    this.onAskConfirmed,
    this.highlightedTexts = const [],
    this.highlightRanges = const [],
  });

  @override
  State<TxtReaderView> createState() => _TxtReaderViewState();
}

class _TxtReaderViewState extends State<TxtReaderView> {
  static const _channel = MethodChannel('com.engreader/pdfkit');
  final _scrollController = ScrollController();
  Offset? _lastPointerGlobalPos;
  Offset? _selectionStartPos;
  String? _lastNotifiedText;
  int? _lastSelStart;
  int? _lastSelEnd;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
    _restoreProgress();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _restoreProgress() async {
    final progress =
        await SettingsService.getReadingProgress(widget.filePath);
    if (progress != null && progress['scrollOffset'] != null) {
      final offset = (progress['scrollOffset'] as num).toDouble();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
              offset.clamp(0.0, _scrollController.position.maxScrollExtent));
        }
      });
    }
  }

  void _onScroll() {
    SettingsService.saveReadingProgress(widget.filePath, {
      'scrollOffset': _scrollController.offset,
    });
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onAnnotateConfirmed') {
      final args = call.arguments as Map;
      final text = args['text'] as String;
      final yPosition = (args['yPosition'] as num?)?.toDouble() ?? 0.0;
      await widget.onAnnotateConfirmed(text, yPosition,
          charStart: _lastSelStart, charEnd: _lastSelEnd);
    } else if (call.method == 'onAskConfirmed') {
      final args = call.arguments as Map;
      final text = args['text'] as String;
      final question = args['question'] as String;
      final yPosition = (args['yPosition'] as num?)?.toDouble() ?? 0.0;
      await widget.onAskConfirmed?.call(text, question, yPosition,
          charStart: _lastSelStart, charEnd: _lastSelEnd);
    }
  }

  void _handleSelectionChanged(
      TextSelection selection, SelectionChangedCause? cause) {
    if (selection.isCollapsed) return;

    final text =
        widget.content.substring(selection.start, selection.end).trim();
    if (text.isEmpty) return;
    if (text == _lastNotifiedText) return;
    _lastNotifiedText = text;
    _lastSelStart = selection.start;
    _lastSelEnd = selection.end;

    final yPos = _scrollController.hasClients
        ? _scrollController.offset /
            (_scrollController.position.maxScrollExtent + 1)
        : 0.0;

    // Anchor popover above selection top edge.
    final start = _selectionStartPos;
    final end = _lastPointerGlobalPos;
    double screenX = 200.0;
    double screenY = 200.0;
    if (start != null && end != null) {
      screenX = (start.dx + end.dx) / 2;
      // Use the higher Y (smaller value) minus line height offset for top edge.
      screenY = (start.dy < end.dy ? start.dy : end.dy) - 12;
    } else if (start != null) {
      screenX = start.dx;
      screenY = start.dy - 12;
    } else if (end != null) {
      screenX = end.dx;
      screenY = end.dy - 12;
    }
    _channel.invokeMethod('showAnnotatePopover', {
      'text': text,
      'yPosition': yPos,
      'screenX': screenX,
      'screenY': screenY,
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  TextSpan _buildHighlightedSpan(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = TextStyle(
      fontSize: 16,
      height: 1.8,
      color: colorScheme.onSurface,
      fontFamily: 'Georgia',
    );
    final highlightStyle = baseStyle.copyWith(
      backgroundColor: Colors.yellow.withValues(alpha: 0.35),
    );

    if (widget.highlightRanges.isEmpty && widget.highlightedTexts.isEmpty) {
      return TextSpan(text: widget.content, style: baseStyle);
    }

    final content = widget.content;
    final matches = <_MatchRange>[];

    // Use precise ranges when available.
    for (final r in widget.highlightRanges) {
      if (r.start >= 0 && r.end <= content.length && r.start < r.end) {
        matches.add(_MatchRange(r.start, r.end));
      }
    }

    // Fallback: text search for annotations without position data.
    for (final ht in widget.highlightedTexts) {
      int searchFrom = 0;
      while (true) {
        final idx = content.indexOf(ht, searchFrom);
        if (idx == -1) break;
        matches.add(_MatchRange(idx, idx + ht.length));
        searchFrom = idx + ht.length;
      }
    }

    if (matches.isEmpty) {
      return TextSpan(text: content, style: baseStyle);
    }

    matches.sort((a, b) => a.start.compareTo(b.start));

    // Merge overlapping ranges.
    final merged = <_MatchRange>[];
    for (final m in matches) {
      if (merged.isNotEmpty && m.start <= merged.last.end) {
        merged.last = _MatchRange(
            merged.last.start, m.end > merged.last.end ? m.end : merged.last.end);
      } else {
        merged.add(m);
      }
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final range in merged) {
      if (range.start > lastEnd) {
        spans.add(TextSpan(text: content.substring(lastEnd, range.start), style: baseStyle));
      }
      spans.add(TextSpan(text: content.substring(range.start, range.end), style: highlightStyle));
      lastEnd = range.end;
    }
    if (lastEnd < content.length) {
      spans.add(TextSpan(text: content.substring(lastEnd), style: baseStyle));
    }

    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _lastPointerGlobalPos = event.position;
        _selectionStartPos = event.position;
      },
      onPointerMove: (event) {
        if (event.kind == PointerDeviceKind.mouse ||
            event.kind == PointerDeviceKind.stylus ||
            event.kind == PointerDeviceKind.touch) {
          _lastPointerGlobalPos = event.position;
        }
      },
      onPointerUp: (event) => _lastPointerGlobalPos = event.position,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 80),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          child: SelectableText.rich(
            _buildHighlightedSpan(context),
            onSelectionChanged: _handleSelectionChanged,
          ),
        ),
      ),
    );
  }
}

class _MatchRange {
  int start;
  int end;
  _MatchRange(this.start, this.end);
}
