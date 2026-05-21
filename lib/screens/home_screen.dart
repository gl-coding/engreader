import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:engreader/services/settings_service.dart';
import 'package:path/path.dart' as p;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> _recentFiles = [];

  static IconData _fileIcon(String ext) {
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.epub':
        return Icons.book;
      default:
        return Icons.text_snippet;
    }
  }

  static Color _fileColor(String ext) {
    switch (ext) {
      case '.pdf':
        return Colors.red;
      case '.epub':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
  }

  Future<void> _loadRecentFiles() async {
    final files = await SettingsService.getRecentFiles();
    setState(() => _recentFiles = files);
  }

  Future<void> _openFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      await SettingsService.addRecentFile(path);
      await _loadRecentFiles();
      _navigateToReader(path);
    }
  }

  void _navigateToReader(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    final fileType = ext == '.pdf' ? 'pdf' : 'txt';
    Navigator.pushNamed(context, '/reader', arguments: {
      'filePath': filePath,
      'fileType': fileType,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_stories,
                      size: 36, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'EngReader',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.pushNamed(context, '/settings'),
                    tooltip: '设置',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '英文阅读 · 智能批注',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 40),
              // Open file button
              SizedBox(
                width: double.infinity,
                height: 120,
                child: OutlinedButton(
                  onPressed: _openFile,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: BorderSide(
                      color: colorScheme.outline.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline,
                          size: 36, color: colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        '打开文件',
                        style: TextStyle(
                            fontSize: 16, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '支持 PDF、TXT 格式',
                        style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Recent files
              if (_recentFiles.isNotEmpty) ...[
                Text(
                  '最近打开',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: _recentFiles.length,
                    itemBuilder: (context, index) {
                      final filePath = _recentFiles[index];
                      final file = File(filePath);
                      final exists = file.existsSync();
                      final fileName = p.basename(filePath);
                      final ext = p.extension(filePath).toLowerCase();

                      return ListTile(
                        leading: Icon(
                          _fileIcon(ext),
                          color: exists ? _fileColor(ext) : Colors.grey,
                        ),
                        title: Text(
                          fileName,
                          style: TextStyle(
                            color: exists ? null : Colors.grey,
                            decoration:
                                exists ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Text(
                          filePath,
                          style: TextStyle(
                              fontSize: 11, color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: exists ? () => _navigateToReader(filePath) : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    },
                  ),
                ),
              ] else
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.menu_book,
                            size: 64,
                            color:
                                colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text(
                          '导入文件开始阅读',
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
