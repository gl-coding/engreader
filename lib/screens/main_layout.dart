import 'dart:io';
import 'package:flutter/material.dart';
import 'package:engreader/models/annotation.dart';
import 'package:engreader/models/llm_config.dart';
import 'package:engreader/services/annotation_store.dart';
import 'package:engreader/services/llm_service.dart';
import 'package:engreader/services/log_service.dart';
import 'package:engreader/services/settings_service.dart';
import 'package:engreader/services/pdf_export_service.dart';
import 'package:engreader/services/file_library_service.dart';
import 'package:engreader/widgets/sidebar.dart';
import 'package:engreader/widgets/resizable_panel.dart';
import 'package:engreader/widgets/annotation_panel.dart';
import 'package:engreader/widgets/txt_reader_view.dart';
import 'package:engreader/widgets/pdf_reader_view.dart';
import 'package:engreader/widgets/epub_reader_view.dart';
import 'package:engreader/widgets/web_reader_view.dart';
import 'package:engreader/screens/settings_screen.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  String? _currentFilePath;
  String? _currentFileType;
  String? _sourceText;
  List<Annotation> _annotations = [];
  LlmConfig _llmConfig = LlmConfig.defaultConfig;
  bool _showSidebar = true;
  bool _showAnnotationPanel = false;
  int _currentPage = 0;

  static IconData _fileIcon(String type) {
    switch (type) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'epub':
        return Icons.book;
      case 'web':
        return Icons.language;
      default:
        return Icons.text_snippet;
    }
  }

  static Color _fileColor(String type) {
    switch (type) {
      case 'pdf':
        return Colors.red;
      case 'epub':
        return Colors.green;
      case 'web':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await SettingsService.getLlmConfig();
    setState(() => _llmConfig = config);
  }

  Future<void> _openFile(String filePath, String fileType) async {
    var actualPath = filePath;

    if (fileType == 'web') {
      await SettingsService.addRecentFile(filePath);
      final annotations = await AnnotationStore.load(filePath);
      LogService.log('FILE', 'openFile: type=web url=$filePath annotations=${annotations.length}');
      setState(() {
        _currentFilePath = filePath;
        _currentFileType = 'web';
        _sourceText = null;
        _annotations = annotations;
        _currentPage = 0;
      });
      return;
    }

    // Ensure file is inside sandbox (needed for native PDFView access).
    final inLibrary = await FileLibraryService.isInLibrary(filePath);
    if (!inLibrary) {
      try {
        actualPath = await FileLibraryService.importFile(filePath);
        await SettingsService.removeRecentFile(filePath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法访问文件: $e')),
          );
        }
        return;
      }
    }

    await SettingsService.addRecentFile(actualPath);

    String? sourceText;
    if (fileType == 'txt') {
      sourceText = await File(actualPath).readAsString();
    }

    final annotations = await AnnotationStore.load(actualPath);
    LogService.log('FILE', 'openFile: type=$fileType path=$actualPath annotations=${annotations.length}');

    setState(() {
      _currentFilePath = actualPath;
      _currentFileType = fileType;
      _sourceText = sourceText;
      _annotations = annotations;
      _currentPage = 0;
    });
  }

  Future<void> _runLlmAndAddAnnotation(
    String text,
    double yPosition, {
    int? charStart,
    int? charEnd,
    String? cfiRange,
  }) async {
    if (_currentFilePath == null) return;

    final isWord = !text.contains(' ') || text.split(' ').length <= 2;
    final type = isWord ? AnnotationType.word : AnnotationType.sentence;

    LogService.log('ANNOTATE', 'addAnnotation: type=$_currentFileType page=$_currentPage '
        'text="${text.length > 40 ? text.substring(0, 40) : text}" '
        'charStart=$charStart charEnd=$charEnd cfiRange=$cfiRange');

    final templates = await SettingsService.getActiveTemplates();
    String translation = '';

    for (final template in templates) {
      if (template.prompt.isEmpty) continue;
      final config = await SettingsService.getLlmConfig();
      if (config.apiKey.isEmpty) continue;
      final service = LlmService(config);
      final prompt = template.prompt.replaceAll('\$TEXT', text);
      final result = await service.chat(prompt);
      if (translation.isNotEmpty) {
        translation += '\n\n--- ${template.name} ---\n$result';
      } else {
        translation = result;
      }
    }

    final annotation = Annotation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      selectedText: text,
      translation: translation,
      type: type,
      pageIndex: _currentPage,
      yPosition: yPosition,
      charStart: charStart,
      charEnd: charEnd,
      cfiRange: cfiRange,
    );

    setState(() => _annotations.add(annotation));
    await AnnotationStore.save(_currentFilePath!, _annotations);
    LogService.log('ANNOTATE', 'saved, total annotations=${_annotations.length}');
  }

  Future<void> _runAskAndAddAnnotation(
    String text,
    String question,
    double yPosition, {
    int? charStart,
    int? charEnd,
    String? cfiRange,
  }) async {
    if (_currentFilePath == null) return;

    LogService.log('ASK', 'question="$question" text="${text.length > 30 ? text.substring(0, 30) : text}"');

    String translation = '';
    final config = await SettingsService.getLlmConfig();
    if (config.apiKey.isNotEmpty) {
      final service = LlmService(config);
      final prompt =
          '用户选中了以下英文文本：\n"$text"\n\n用户的问题：$question\n\n请用中文回答。';
      translation = await service.chat(prompt);
    } else {
      translation = '（未配置 API Key，无法回答）';
    }

    final annotation = Annotation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      selectedText: text,
      translation: '❓ $question\n\n$translation',
      type: AnnotationType.sentence,
      pageIndex: _currentPage,
      yPosition: yPosition,
      charStart: charStart,
      charEnd: charEnd,
      cfiRange: cfiRange,
    );

    setState(() => _annotations.add(annotation));
    await AnnotationStore.save(_currentFilePath!, _annotations);
  }

  Future<void> _exportPdf() async {
    if (_currentFilePath == null) return;

    if (_sourceText == null && _currentFileType == 'txt') {
      _sourceText = await File(_currentFilePath!).readAsString();
    }

    final dir = await getApplicationDocumentsDirectory();
    final fileName = p.basenameWithoutExtension(_currentFilePath!);
    final outputPath = p.join(dir.path, '${fileName}_annotated.pdf');

    final text = _sourceText ?? '(PDF content export not yet supported)';

    await PdfExportService.exportWithAnnotations(
      sourceText: text,
      annotations: _annotations,
      outputPath: outputPath,
      title: p.basename(_currentFilePath!),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已导出到: $outputPath'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(label: '好的', onPressed: () {}),
        ),
      );
    }
  }

  void _deleteAnnotation(String id) async {
    setState(() => _annotations.removeWhere((a) => a.id == id));
    if (_currentFilePath != null) {
      await AnnotationStore.save(_currentFilePath!, _annotations);
    }
  }

  void _clearPageAnnotations() async {
    setState(() => _annotations.removeWhere((a) => a.pageIndex == _currentPage));
    if (_currentFilePath != null) {
      await AnnotationStore.save(_currentFilePath!, _annotations);
    }
  }

  /// Build page-indexed highlight data for PDF native.
  Map<int, List<Map<String, dynamic>>> _buildPageHighlights() {
    final map = <int, List<Map<String, dynamic>>>{};
    for (final a in _annotations) {
      map.putIfAbsent(a.pageIndex, () => []).add({
        'text': a.selectedText,
        'charStart': a.charStart ?? -1,
        'charEnd': a.charEnd ?? -1,
      });
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pageAnnotations =
        _annotations.where((a) => a.pageIndex == _currentPage).toList();

    return Scaffold(
      body: Stack(
        children: [
          _buildMainContent(colorScheme, pageAnnotations),
          // Floating - left: sidebar toggle (fixed in window)
          Positioned(
            top: 12,
            left: (_showSidebar ? 420 : 0) + 8.0,
            child: _buildFloatingPill(
              colorScheme,
              child: InkWell(
                onTap: () => setState(() => _showSidebar = !_showSidebar),
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    _showSidebar ? Icons.menu_open : Icons.menu,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          // Floating - right: actions (fixed in window, never moves)
          if (_currentFilePath != null)
            Positioned(
              top: 12,
              right: 8,
              child: _buildFloatingActions(colorScheme),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent(
      ColorScheme colorScheme, List<Annotation> pageAnnotations) {
    return Row(
      children: [
          // Left sidebar
          if (_showSidebar)
            ResizablePanel(
              initialWidth: 420,
              minWidth: 360,
              maxWidth: 600,
              resizeFromLeft: false,
              child: Sidebar(
                onFileSelected: _openFile,
              ),
            ),
          // Main content area
          Expanded(
            child: Row(
              children: [
                // Reader content
                Expanded(
                  child: _currentFilePath == null
                      ? _buildWelcome(colorScheme)
                      : _buildReaderView(),
                ),
                // Annotation sidebar (pushes content)
                if (_currentFilePath != null && _showAnnotationPanel)
                  Container(
                    width: 300,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      border: Border(
                        left: BorderSide(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: AnnotationPanel(
                      annotations: pageAnnotations,
                      onDelete: _deleteAnnotation,
                      onClearAll: _clearPageAnnotations,
                    ),
                  ),
              ],
            ),
          ),
        ],
    );
  }

  Widget _buildFloatingPill(ColorScheme colorScheme, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
      child: child,
    );
  }

  Widget _buildFloatingActions(ColorScheme colorScheme) {
    return _buildFloatingPill(
      colorScheme,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FloatingActionBtn(
                icon: Icons.picture_as_pdf_outlined,
                tooltip: '导出 PDF',
                onTap: _exportPdf,
              ),
              Container(
                width: 1,
                height: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              _FloatingActionBtn(
                icon: _showAnnotationPanel
                    ? Icons.chrome_reader_mode
                    : Icons.chrome_reader_mode_outlined,
                tooltip: '批注面板',
                onTap: () =>
                    setState(() => _showAnnotationPanel = !_showAnnotationPanel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderView() {
    switch (_currentFileType) {
      case 'pdf':
        return PdfReaderView(
          filePath: _currentFilePath!,
          onAnnotateConfirmed: _runLlmAndAddAnnotation,
          onAskConfirmed: (text, question, yPosition,
              {int? charStart, int? charEnd}) =>
              _runAskAndAddAnnotation(text, question, yPosition,
                  charStart: charStart, charEnd: charEnd),
          onPageChanged: (page) => setState(() => _currentPage = page),
          pageHighlights: _buildPageHighlights(),
        );
      case 'epub':
        return EpubReaderView(
          filePath: _currentFilePath!,
          onAnnotateConfirmed: _runLlmAndAddAnnotation,
          onAskConfirmed: (text, question, yPosition,
              {String? cfiRange}) =>
              _runAskAndAddAnnotation(text, question, yPosition,
                  cfiRange: cfiRange),
          highlights: _annotations
              .where((a) => a.pageIndex == _currentPage)
              .map((a) => {
                    'text': a.selectedText,
                    'cfiRange': a.cfiRange ?? '',
                  })
              .toList(),
          onPageChanged: (page) => setState(() => _currentPage = page),
        );
      case 'web':
        return WebReaderView(
          url: _currentFilePath!,
          onAnnotateConfirmed: _runLlmAndAddAnnotation,
          onAskConfirmed: (text, question, yPosition) =>
              _runAskAndAddAnnotation(text, question, yPosition),
          highlightedTexts: _annotations
              .map((a) => a.selectedText)
              .toList(),
        );
      default:
        final txtAnnotations = _annotations.where((a) => a.pageIndex == 0).toList();
        return TxtReaderView(
          filePath: _currentFilePath!,
          content: _sourceText ?? '',
          onAnnotateConfirmed: _runLlmAndAddAnnotation,
          onAskConfirmed: (text, question, yPosition,
              {int? charStart, int? charEnd}) =>
              _runAskAndAddAnnotation(text, question, yPosition,
                  charStart: charStart, charEnd: charEnd),
          highlightRanges: txtAnnotations
              .where((a) => a.charStart != null && a.charEnd != null)
              .map((a) => (start: a.charStart!, end: a.charEnd!))
              .toList(),
          highlightedTexts: txtAnnotations
              .where((a) => a.charStart == null)
              .map((a) => a.selectedText)
              .toList(),
        );
    }
  }

  Widget _buildWelcome(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories,
              size: 64, color: colorScheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            'EngReader',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '从左侧选择文件开始阅读',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FloatingActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _FloatingActionBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
          ),
          child: Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
