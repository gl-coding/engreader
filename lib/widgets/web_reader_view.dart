import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebReaderView extends StatefulWidget {
  final String url;
  final Future<void> Function(String text, double yPosition,
      {int? charStart, int? charEnd, String? cfiRange}) onAnnotateConfirmed;
  final Future<void> Function(String text, String question, double yPosition)?
      onAskConfirmed;
  final List<String> highlightedTexts;

  const WebReaderView({
    super.key,
    required this.url,
    required this.onAnnotateConfirmed,
    this.onAskConfirmed,
    this.highlightedTexts = const [],
  });

  @override
  State<WebReaderView> createState() => _WebReaderViewState();
}

class _WebReaderViewState extends State<WebReaderView> {
  static const _channel = MethodChannel('com.engreader/pdfkit');
  final _webViewKey = GlobalKey();
  InAppWebViewController? _webViewController;
  double _progress = 0;
  String _title = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  void dispose() {
    _webViewController = null;
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onAnnotateConfirmed') {
      final args = call.arguments as Map;
      final text = args['text'] as String;
      final yPosition = (args['yPosition'] as num?)?.toDouble() ?? 0.0;
      await widget.onAnnotateConfirmed(text, yPosition);
    } else if (call.method == 'onAskConfirmed') {
      final args = call.arguments as Map;
      final text = args['text'] as String;
      final question = args['question'] as String;
      final yPosition = (args['yPosition'] as num?)?.toDouble() ?? 0.0;
      await widget.onAskConfirmed?.call(text, question, yPosition);
    }
  }

  void _injectSelectionScript() {
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        if (window.__engReaderInjected) return;
        window.__engReaderInjected = true;

        var lastSentText = "";
        setInterval(function() {
          var sel = window.getSelection();
          var text = sel ? sel.toString().trim() : "";
          if (text.length === 0) {
            lastSentText = "";
            return;
          }
          if (text === lastSentText) return;
          lastSentText = text;

          var range = sel.getRangeAt(0);
          var rect = range.getBoundingClientRect();
          var x = rect.left + rect.width / 2;
          var y = rect.top;

          window.flutter_inappwebview.callHandler("onTextSelected", {
            text: text,
            x: x,
            y: y
          });
        }, 50);
      })();
    ''');
  }

  void _applyHighlights() {
    if (_webViewController == null) return;
    final items = widget.highlightedTexts
        .map((t) => '"${t.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"')
        .join(',');
    _webViewController!.evaluateJavascript(source: '''
      (function() {
        if (!window.CSS || !CSS.highlights) return;
        CSS.highlights.clear();
        var texts = [$items];
        if (texts.length === 0) return;

        var style = document.getElementById('__eng_hl_style');
        if (!style) {
          style = document.createElement('style');
          style.id = '__eng_hl_style';
          style.textContent = '::highlight(eng-hl) { background-color: rgba(255, 200, 0, 0.5); }';
          document.head.appendChild(style);
        }

        var ranges = [];
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        var node;
        while (node = walker.nextNode()) {
          var content = node.textContent;
          for (var i = 0; i < texts.length; i++) {
            var idx = content.indexOf(texts[i]);
            if (idx >= 0) {
              var r = new Range();
              r.setStart(node, idx);
              r.setEnd(node, idx + texts[i].length);
              ranges.push(r);
            }
          }
        }
        if (ranges.length > 0) {
          var hl = new Highlight(...ranges);
          CSS.highlights.set('eng-hl', hl);
        }
      })();
    ''');
  }

  @override
  void didUpdateWidget(WebReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedTexts.length != widget.highlightedTexts.length) {
      _applyHighlights();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (_isLoading)
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            minHeight: 2,
          ),
        if (_title.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                    color: colorScheme.outlineVariant, width: 0.5),
              ),
            ),
            child: Text(
              _title,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Expanded(
          child: InAppWebView(
            key: _webViewKey,
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: false,
              mediaPlaybackRequiresUserGesture: true,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
              controller.addJavaScriptHandler(
                handlerName: 'onTextSelected',
                callback: (args) {
                  if (args.isEmpty) return;
                  final data = args[0] as Map;
                  final text = data['text'] as String? ?? '';
                  final jsX = (data['x'] as num?)?.toDouble() ?? 200;
                  final jsY = (data['y'] as num?)?.toDouble() ?? 200;

                  if (text.isNotEmpty) {
                    final renderBox = _webViewKey.currentContext
                        ?.findRenderObject() as RenderBox?;
                    double screenX = jsX;
                    double screenY = jsY;
                    if (renderBox != null) {
                      final offset = renderBox.localToGlobal(Offset.zero);
                      screenX = offset.dx + jsX;
                      screenY = offset.dy + jsY;
                    }
                    _channel.invokeMethod('showAnnotatePopover', {
                      'text': text,
                      'yPosition': 0.0,
                      'screenX': screenX,
                      'screenY': screenY,
                    });
                  }
                },
              );
            },
            onLoadStop: (controller, url) {
              if (!mounted) return;
              setState(() => _isLoading = false);
              _injectSelectionScript();
              _applyHighlights();
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              setState(() => _progress = progress / 100.0);
            },
            onTitleChanged: (controller, title) {
              if (!mounted) return;
              setState(() => _title = title ?? '');
            },
          ),
        ),
      ],
    );
  }
}
