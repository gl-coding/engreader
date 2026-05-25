import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:engreader/services/local_server.dart';
import 'package:engreader/services/settings_service.dart';

class EpubChapter {
  final String label;
  final String href;
  EpubChapter({required this.label, required this.href});
}

class EpubReaderView extends StatefulWidget {
  final String filePath;
  final Future<void> Function(String text, double yPosition,
      {int? charStart, int? charEnd, String? cfiRange}) onAnnotateConfirmed;
  final Future<void> Function(String text, String question, double yPosition,
      {String? cfiRange})? onAskConfirmed;
  final List<Map<String, String>> highlights;
  final void Function(int page)? onPageChanged;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onAnnotateConfirmed,
    this.onAskConfirmed,
    this.highlights = const [],
    this.onPageChanged,
  });

  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();
}

class _EpubReaderViewState extends State<EpubReaderView> {
  static const _channel = MethodChannel('com.engreader/pdfkit');
  final _server = LocalFileServer();
  final _webViewKey = GlobalKey();
  InAppWebViewController? _webViewController;
  List<EpubChapter> _chapters = [];
  int _selectedChapter = 0;
  double _progress = 0;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _locationsReady = false;
  bool _showToc = false;
  String? _readerUrl;
  String _loadingStatus = '正在准备阅读器...';
  bool _bookLoaded = false;
  String? _savedCfi;
  String? _cachedLocations;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
    _loadSavedProgress();
    _setupServer();
  }

  @override
  void didUpdateWidget(EpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlights.length != widget.highlights.length) {
      _applyHighlights();
    }
  }

  void _applyHighlights() {
    if (_webViewController == null) return;
    final items = widget.highlights.map((h) {
      final text = (h['text'] ?? '').replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      final cfi = (h['cfiRange'] ?? '').replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      if (cfi.isNotEmpty) {
        return '{"text":"$text","cfiRange":"$cfi"}';
      }
      return '{"text":"$text"}';
    }).join(',');
    _webViewController!.evaluateJavascript(
        source: 'applyHighlights([$items]);');
  }

  Future<void> _loadSavedProgress() async {
    final progress = await SettingsService.getReadingProgress(widget.filePath);
    if (progress != null && progress['cfi'] != null) {
      _savedCfi = progress['cfi'] as String;
    }
    // Load cached locations from file.
    final cacheFile = await _locationsCacheFile();
    if (cacheFile.existsSync()) {
      _cachedLocations = await cacheFile.readAsString();
    }
  }

  Future<File> _locationsCacheFile() async {
    final dir = await getApplicationSupportDirectory();
    final fileName = p.basenameWithoutExtension(widget.filePath);
    return File(p.join(dir.path, 'epub_locations', '$fileName.json'));
  }

  Future<void> _saveLocationsCache(String data) async {
    final file = await _locationsCacheFile();
    final dir = file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    await file.writeAsString(data);
  }

  @override
  void dispose() {
    _webViewController = null;
    _server.stop();
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onAnnotateConfirmed') {
      final args = call.arguments as Map;
      final text = args['text'] as String;
      final yPosition = (args['yPosition'] as num?)?.toDouble() ?? 0.0;
      final cfi = _lastSelectedCfi;
      await widget.onAnnotateConfirmed(text, yPosition,
          cfiRange: (cfi != null && cfi.isNotEmpty) ? cfi : null);
    } else if (call.method == 'onAskConfirmed') {
      final args = call.arguments as Map;
      final text = args['text'] as String;
      final question = args['question'] as String;
      final yPosition = (args['yPosition'] as num?)?.toDouble() ?? 0.0;
      final cfi = _lastSelectedCfi;
      await widget.onAskConfirmed?.call(text, question, yPosition,
          cfiRange: (cfi != null && cfi.isNotEmpty) ? cfi : null);
    }
  }

  String? _lastSelectedCfi;

  Future<void> _setupServer() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final serveDir = Directory(p.join(dir.path, 'epub_serve'));
      if (!serveDir.existsSync()) {
        serveDir.createSync(recursive: true);
      }

      // Copy reader.html to the serve directory.
      final htmlContent =
          await rootBundle.loadString('assets/epub/reader.html');
      final htmlFile = File(p.join(serveDir.path, 'reader.html'));
      await htmlFile.writeAsString(htmlContent);

      // Use a simplified name (no spaces) for the symlink to avoid URL issues.
      const epubServeName = 'book.epub';
      final epubLink = File(p.join(serveDir.path, epubServeName));
      if (epubLink.existsSync()) {
        epubLink.deleteSync();
      }
      // Try symlink first (fast), fallback to copy.
      try {
        Link(epubLink.path).createSync(widget.filePath);
      } catch (_) {
        if (!epubLink.existsSync()) {
          await File(widget.filePath).copy(epubLink.path);
        }
      }

      // Start the local HTTP server.
      await _server.start(serveDir.path);

      final readerUrl = 'http://127.0.0.1:${_server.port}/reader.html';
      setState(() {
        _readerUrl = readerUrl;
        _loadingStatus = '正在加载 EPUB...';
      });
    } catch (e) {
      setState(() {
        _loadingStatus = '准备失败: $e';
      });
    }
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;

    controller.addJavaScriptHandler(
      handlerName: 'onTextSelected',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map;
        final text = data['text'] as String? ?? '';
        final jsX = (data['x'] as num?)?.toDouble() ?? 200;
        final jsY = (data['y'] as num?)?.toDouble() ?? 200;
        _lastSelectedCfi = data['cfiRange'] as String? ?? '';

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

    controller.addJavaScriptHandler(
      handlerName: 'onTocLoaded',
      callback: (args) {
        if (args.isEmpty) return;
        final toc = (args[0] as List).map((ch) {
          final map = ch as Map;
          return EpubChapter(
            label: map['label'] as String? ?? '',
            href: map['href'] as String? ?? '',
          );
        }).toList();
        setState(() {
          _chapters = toc;
          _bookLoaded = true;
        });
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onRelocated',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map;
        final cfi = data['cfi'] as String? ?? '';
        final progress = (data['progress'] as num?)?.toDouble() ?? 0;
        final page = (data['page'] as num?)?.toInt() ?? 0;
        final total = (data['total'] as num?)?.toInt() ?? 0;
        setState(() {
          _progress = progress;
          _currentPage = page;
          _totalPages = total;
          if (data['chapterOnly'] == null || data['chapterOnly'] == false) {
            _locationsReady = true;
          }
        });
        // Notify parent of page change for annotation filtering.
        widget.onPageChanged?.call(page);
        // Persist reading progress.
        if (cfi.isNotEmpty) {
          SettingsService.saveReadingProgress(widget.filePath, {
            'cfi': cfi,
            'chapter': _selectedChapter,
          });
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onLocationsReady',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map;
        final total = (data['total'] as num?)?.toInt() ?? 0;
        setState(() {
          _locationsReady = true;
          _totalPages = total;
        });
        // Cache locations data to disk for fast reload.
        final locationsData = data['locationsData'] as String?;
        if (locationsData != null && locationsData.isNotEmpty) {
          _saveLocationsCache(locationsData);
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'requestLocationsCache',
      callback: (args) {
        return _cachedLocations ?? '';
      },
    );
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    final epubUrl = 'http://127.0.0.1:${_server.port}/book.epub';
    controller.evaluateJavascript(source: "loadBook('$epubUrl');");
    if (_savedCfi != null) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _webViewController?.evaluateJavascript(
            source: "goToCfi('${_savedCfi!.replaceAll("'", "\\'")}');");
      });
    }
    // Apply initial highlights after book loads.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _applyHighlights();
    });
  }

  void _goToChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    final href = _chapters[index].href;
    _webViewController?.evaluateJavascript(source: "goToChapter('$href');");
    setState(() {
      _selectedChapter = index;
      _showToc = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_readerUrl == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_loadingStatus,
                style: TextStyle(
                    fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
            key: _webViewKey,
            initialUrlRequest: URLRequest(url: WebUri(_readerUrl!)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
            ),
            onWebViewCreated: _onWebViewCreated,
            onLoadStop: _onLoadStop,
          ),
        ),
        // Floating TOC button (top-left)
        if (_chapters.isNotEmpty)
          Positioned(
            left: 12,
            bottom: 24,
            child: GestureDetector(
              onTap: () => setState(() => _showToc = !_showToc),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
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
                child: Icon(Icons.list, size: 18, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        // Floating vertical page indicator (right)
        if (_totalPages > 0)
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
                    onTap: _prevPage,
                    child: Icon(Icons.keyboard_arrow_up,
                        size: 20, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_currentPage',
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
                    '$_totalPages',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _nextPage,
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 20, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        // TOC overlay panel
        if (_showToc && _chapters.isNotEmpty)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 260,
            child: Material(
              elevation: 4,
              child: Container(
                color: colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Text('目录',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: colorScheme.onSurface)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _showToc = false),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _chapters.length,
                        itemBuilder: (context, index) {
                          final ch = _chapters[index];
                          final isSelected = index == _selectedChapter;
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            selected: isSelected,
                            selectedTileColor: colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.4),
                            title: Text(
                              ch.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _goToChapter(index),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _prevPage() {
    _webViewController?.evaluateJavascript(source: "prevPage();");
  }

  void _nextPage() {
    _webViewController?.evaluateJavascript(source: "nextPage();");
  }
}
