import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:engreader/services/settings_service.dart';

class PdfReaderView extends StatefulWidget {
  final String filePath;

  /// Invoked when the user confirms annotation in the native popover.
  /// This should directly trigger LLM parsing (no extra confirmation needed).
  final Future<void> Function(String text, double yPosition) onAnnotateConfirmed;

  final void Function(int page) onPageChanged;

  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onAnnotateConfirmed,
    required this.onPageChanged,
  });

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends State<PdfReaderView> {
  static const _channel = MethodChannel('com.engreader/pdfkit');
  final _viewKey = GlobalKey();
  int _pageCount = 0;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
    _restoreProgress();
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
        await widget.onAnnotateConfirmed(text, yPosition);
        break;
      case 'onPageChanged':
        final page = call.arguments as int;
        setState(() => _currentPage = page);
        widget.onPageChanged(page);
        SettingsService.saveReadingProgress(widget.filePath, {'page': page});
        break;
      case 'onDocumentLoaded':
        final args = call.arguments as Map;
        setState(() {
          _pageCount = args['pageCount'] as int? ?? 0;
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: KeyedSubtree(key: _viewKey, child: _buildPlatformView()),
        ),
        if (_pageCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 0 ? _previousPage : null,
                  iconSize: 20,
                ),
                Text(
                  '${_currentPage + 1} / $_pageCount',
                  style: const TextStyle(fontSize: 13),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed:
                      _currentPage < _pageCount - 1 ? _nextPage : null,
                  iconSize: 20,
                ),
              ],
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
