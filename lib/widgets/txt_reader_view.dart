import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:engreader/services/settings_service.dart';

class TxtReaderView extends StatefulWidget {
  final String filePath;
  final String content;
  final Future<void> Function(String text, double yPosition) onAnnotateConfirmed;

  const TxtReaderView({
    super.key,
    required this.filePath,
    required this.content,
    required this.onAnnotateConfirmed,
  });

  @override
  State<TxtReaderView> createState() => _TxtReaderViewState();
}

class _TxtReaderViewState extends State<TxtReaderView> {
  static const _channel = MethodChannel('com.engreader/pdfkit');
  final _scrollController = ScrollController();
  Offset? _lastPointerGlobalPos;
  String? _lastNotifiedText;

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
      await widget.onAnnotateConfirmed(text, yPosition);
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

    final yPos = _scrollController.hasClients
        ? _scrollController.offset /
            (_scrollController.position.maxScrollExtent + 1)
        : 0.0;

    // Show native NSPopover via MethodChannel.
    final pos = _lastPointerGlobalPos;
    _channel.invokeMethod('showAnnotatePopover', {
      'text': text,
      'yPosition': yPos,
      'screenX': pos?.dx ?? 200.0,
      'screenY': pos?.dy ?? 200.0,
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Listener(
      onPointerDown: (event) => _lastPointerGlobalPos = event.position,
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
          child: SelectableText(
            widget.content,
            style: TextStyle(
              fontSize: 16,
              height: 1.8,
              color: colorScheme.onSurface,
              fontFamily: 'Georgia',
            ),
            onSelectionChanged: _handleSelectionChanged,
          ),
        ),
      ),
    );
  }
}
