import 'dart:io';
import 'package:flutter/material.dart';
import 'package:engreader/models/annotation.dart';
import 'package:engreader/models/llm_config.dart';
import 'package:engreader/services/annotation_store.dart';
import 'package:engreader/services/llm_service.dart';
import 'package:engreader/services/settings_service.dart';
import 'package:engreader/services/pdf_export_service.dart';
import 'package:engreader/services/file_library_service.dart';
import 'package:engreader/widgets/sidebar.dart';
import 'package:engreader/widgets/resizable_panel.dart';
import 'package:engreader/widgets/annotation_panel.dart';
import 'package:engreader/widgets/txt_reader_view.dart';
import 'package:engreader/widgets/pdf_reader_view.dart';
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
  bool _showAnnotationPanel = true;
  int _currentPage = 0;
  // Pending selection awaiting user confirmation to annotate.

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

    setState(() {
      _currentFilePath = actualPath;
      _currentFileType = fileType;
      _sourceText = sourceText;
      _annotations = annotations;
      _currentPage = 0;
    });
  }

  Future<void> _runLlmAndAddAnnotation(String text, double yPosition) async {
    if (_currentFilePath == null) return;

    final isWord = !text.contains(' ') || text.split(' ').length <= 2;
    final type = isWord ? AnnotationType.word : AnnotationType.sentence;

    final loadingAnnotation = Annotation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      selectedText: text,
      translation: '正在解析...',
      type: type,
      pageIndex: _currentPage,
      yPosition: yPosition,
    );

    setState(() => _annotations.add(loadingAnnotation));

    final llm = LlmService(_llmConfig);
    final result = isWord
        ? await llm.translateWord(text)
        : await llm.translateSentence(text);

    final annotation = Annotation(
      id: loadingAnnotation.id,
      selectedText: text,
      translation: result,
      type: type,
      pageIndex: _currentPage,
      yPosition: yPosition,
    );

    setState(() {
      _annotations.removeWhere((a) => a.id == loadingAnnotation.id);
      _annotations.add(annotation);
    });

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pageAnnotations =
        _annotations.where((a) => a.pageIndex == _currentPage).toList();

    return Scaffold(
      body: _buildMainContent(colorScheme, pageAnnotations),
    );
  }

  Widget _buildMainContent(
      ColorScheme colorScheme, List<Annotation> pageAnnotations) {
    return Row(
      children: [
          // Left sidebar
          if (_showSidebar)
            ResizablePanel(
              initialWidth: 240,
              minWidth: 180,
              maxWidth: 400,
              resizeFromLeft: false,
              child: Sidebar(
                onFileSelected: _openFile,
              ),
            ),
          // Main content
          Expanded(
            child: Column(
              children: [
                // Toolbar
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    border: Border(
                      bottom: BorderSide(
                          color: colorScheme.outlineVariant, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _showSidebar
                              ? Icons.menu_open
                              : Icons.menu,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _showSidebar = !_showSidebar),
                        tooltip: '侧边栏',
                        iconSize: 20,
                      ),
                      if (_currentFilePath != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          _currentFileType == 'pdf'
                              ? Icons.picture_as_pdf
                              : Icons.text_snippet,
                          size: 16,
                          color: _currentFileType == 'pdf'
                              ? Colors.red
                              : Colors.blue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p.basename(_currentFilePath!),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                      const Spacer(),
                      if (_currentFilePath != null) ...[
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf_outlined,
                              size: 20),
                          onPressed: _exportPdf,
                          tooltip: '导出 PDF',
                          iconSize: 20,
                        ),
                        IconButton(
                          icon: Icon(
                            _showAnnotationPanel
                                ? Icons.chrome_reader_mode
                                : Icons.chrome_reader_mode_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _showAnnotationPanel = !_showAnnotationPanel),
                          tooltip: '批注面板',
                          iconSize: 20,
                        ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, size: 20),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/settings'),
                        tooltip: '设置',
                        iconSize: 20,
                      ),
                    ],
                  ),
                ),
                // Reading area + annotation panel
                Expanded(
                  child: _currentFilePath == null
                      ? _buildWelcome(colorScheme)
                      : Row(
                          children: [
                            Expanded(
                              child: _currentFileType == 'pdf'
                                  ? PdfReaderView(
                                      filePath: _currentFilePath!,
                                      onAnnotateConfirmed:
                                          _runLlmAndAddAnnotation,
                                      onPageChanged: (page) => setState(
                                          () => _currentPage = page),
                                    )
                                  : TxtReaderView(
                                      filePath: _currentFilePath!,
                                      content: _sourceText ?? '',
                                      onAnnotateConfirmed:
                                          _runLlmAndAddAnnotation,
                                    ),
                            ),
                            if (_showAnnotationPanel)
                              ResizablePanel(
                                initialWidth: 320,
                                minWidth: 220,
                                maxWidth: 550,
                                resizeFromLeft: true,
                                child: AnnotationPanel(
                                  annotations: pageAnnotations,
                                  onDelete: _deleteAnnotation,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
    );
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
