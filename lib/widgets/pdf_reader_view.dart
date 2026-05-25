import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:engreader/services/log_service.dart';
import 'package:engreader/services/settings_service.dart';

class PdfReaderView extends StatefulWidget {
  final String filePath;

  /// Invoked when the user confirms annotation in the native popover.
  final Future<void> Function(String text, double yPosition,
      {int? charStart, int? charEnd}) onAnnotateConfirmed;

  /// Invoked when the user asks a question about selected text.
  final Future<void> Function(String text, String question, double yPosition,
      {int? charStart, int? charEnd})? onAskConfirmed;

  final void Function(int page) onPageChanged;

  /// Page-indexed highlights: {pageIndex: [{text, charStart, charEnd}, ...]}
  final Map<int, List<Map<String, dynamic>>> pageHighlights;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onAnnotateConfirmed,
    this.onAskConfirmed,
    required this.onPageChanged,
    this.pageHighlights = const {},
  });

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends State<PdfReaderView> {
  static const _channel = MethodChannel('com.engreader/pdfkit');
  final _viewKey = GlobalKey();
  int _pageCount = 0;
  int _currentPage = 0;

  int _lastHighlightCount = 0;

  bool _documentLoaded = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
    _restoreProgress();
    LogService.log('PDF_HL', 'initState, initial highlights count=${widget.pageHighlights.values.fold<int>(0, (s, l) => s + l.length)}');
  }

  @override
  void didUpdateWidget(PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_documentLoaded) return;
    final newCount = widget.pageHighlights.values
        .fold<int>(0, (sum, list) => sum + list.length);
    if (newCount != _lastHighlightCount) {
      LogService.log('PDF_HL', 'didUpdateWidget: count changed $_lastHighlightCount -> $newCount, sending');
      _sendHighlights();
    }
  }

  void _sendHighlights() {
    _lastHighlightCount = widget.pageHighlights.values
        .fold<int>(0, (sum, list) => sum + list.length);
    final encoded = widget.pageHighlights.map(
        (k, v) => MapEntry(k.toString(), v));
    LogService.log('PDF_HL', 'sendHighlights count=$_lastHighlightCount pages=${widget.pageHighlights.keys.toList()}');
    _channel.invokeMethod('setHighlights', {
      'pageHighlights': encoded,
    }).then((_) {
      LogService.log('PDF_HL', 'setHighlights native call succeeded');
    }).catchError((e) {
      LogService.log('PDF_HL', 'setHighlights native call FAILED: $e');
    });
  }


  Future<void> _restoreProgress() async {
    final progress =
        await SettingsService.getReadingProgress(widget.filePath);
    if (progress != null && progress['page'] != null) {
      final savedPage = progress['page'] as int;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _channel.invokeMethod('goToPage', {'page': savedPage});
        setState(() => _currentPage = savedPage);
        widget.onPageChanged(savedPage);
      });
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onAnnotateConfirmed':
        final args = call.arguments as Map;
        final text = args['text'] as String;
        final yPosition = (args['yPosition'] as num?)?.toDouble() ?? 0.0;
        final charStart = (args['charStart'] as num?)?.toInt();
        final charEnd = (args['charEnd'] as num?)?.toInt();
        LogService.log('PDF', 'onAnnotateConfirmed: text="${text.length > 30 ? text.substring(0, 30) : text}" charStart=$charStart charEnd=$charEnd');
        await widget.onAnnotateConfirmed(text, yPosition,
            charStart: charStart != null && charStart >= 0 ? charStart : null,
            charEnd: charEnd != null && charEnd >= 0 ? charEnd : null);
        break;
      case 'onAskConfirmed':
        final args = call.arguments as Map;
        final text = args['text'] as String;
        final question = args['question'] as String;
        final yPosition = (args['yPosition'] as num?)?.toDouble() ?? 0.0;
        final charStart = (args['charStart'] as num?)?.toInt();
        final charEnd = (args['charEnd'] as num?)?.toInt();
        await widget.onAskConfirmed?.call(text, question, yPosition,
            charStart: charStart != null && charStart >= 0 ? charStart : null,
            charEnd: charEnd != null && charEnd >= 0 ? charEnd : null);
        break;
      case 'onPageChanged':
        final page = call.arguments as int;
        LogService.log('PDF', 'onPageChanged: page=$page');
        setState(() => _currentPage = page);
        widget.onPageChanged(page);
        SettingsService.saveReadingProgress(widget.filePath, {'page': page});
        break;
      case 'onDocumentLoaded':
        final args = call.arguments as Map;
        LogService.log('PDF', 'onDocumentLoaded: pageCount=${args['pageCount']}');
        _documentLoaded = true;
        setState(() {
          _pageCount = args['pageCount'] as int? ?? 0;
        });
        // Document is now ready, send highlights.
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          LogService.log('PDF_HL', 'onDocumentLoaded -> sendHighlights');
          _sendHighlights();
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(key: _viewKey, child: _buildPlatformView()),
        ),
        if (_pageCount > 0)
          Positioned(
            right: 12,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _currentPage > 0 ? _previousPage : null,
                    child: Icon(Icons.keyboard_arrow_up,
                        size: 20,
                        color: _currentPage > 0
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.outlineVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_currentPage + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      width: 20,
                      height: 1,
                      color: colorScheme.outlineVariant,
                    ),
                  ),
                  Text(
                    '$_pageCount',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _currentPage < _pageCount - 1 ? _nextPage : null,
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 20,
                        color: _currentPage < _pageCount - 1
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.outlineVariant),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlatformView() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'com.engreader/pdfview',
        creationParams: {'path': widget.filePath},
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      return AppKitView(
        viewType: 'com.engreader/pdfview',
        creationParams: {'path': widget.filePath},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return const Center(child: Text('Platform not supported'));
  }

  void _previousPage() {
    _channel.invokeMethod('goToPage', {'page': _currentPage - 1});
  }

  void _nextPage() {
    _channel.invokeMethod('goToPage', {'page': _currentPage + 1});
  }
}
