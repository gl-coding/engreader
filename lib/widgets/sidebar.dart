import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:engreader/models/file_category.dart';
import 'package:engreader/services/category_service.dart';
import 'package:engreader/services/settings_service.dart';
import 'package:engreader/services/file_library_service.dart';
import 'package:path/path.dart' as p;

class Sidebar extends StatefulWidget {
  final void Function(String filePath, String fileType) onFileSelected;

  const Sidebar({super.key, required this.onFileSelected});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  List<FileCategory> _categories = [];
  String _selectedCategoryId = 'all';
  List<String> _recentFiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final categories = await CategoryService.getCategories();
    final recent = await SettingsService.getRecentFiles();
    setState(() {
      _categories = categories;
      _recentFiles = recent;
      _loading = false;
    });
  }

  List<String> _getFilesForCategory(String categoryId) {
    if (categoryId == 'all') {
      final allFiles = <String>{};
      for (final cat in _categories) {
        allFiles.addAll(cat.filePaths);
      }
      allFiles.addAll(_recentFiles);
      return allFiles.toList();
    }
    if (categoryId == 'recent') {
      return _recentFiles;
    }
    final cat = _categories.firstWhere(
      (c) => c.id == categoryId,
      orElse: () => FileCategory(id: '', name: ''),
    );
    return cat.filePaths;
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入分类名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      await CategoryService.addCategory(name.trim());
      await _loadData();
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      final externalPath = result.files.single.path!;
      // Copy into sandbox-accessible library so native PDF view can open it.
      final localPath = await FileLibraryService.importFile(externalPath);
      await SettingsService.addRecentFile(localPath);
      if (_selectedCategoryId != 'all' && _selectedCategoryId != 'recent') {
        await CategoryService.addFileToCategory(_selectedCategoryId, localPath);
      }
      await _loadData();
    }
  }

  void _onFileTap(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    final fileType = ext == '.pdf' ? 'pdf' : 'txt';
    widget.onFileSelected(filePath, fileType);
  }

  Future<void> _deleteCategory(String id) async {
    await CategoryService.removeCategory(id);
    if (_selectedCategoryId == id) {
      _selectedCategoryId = 'all';
    }
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final files = _getFilesForCategory(_selectedCategoryId);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return DragTarget<String>(
      onAcceptWithDetails: (details) async {
        final filePath = details.data;
        if (_selectedCategoryId != 'all' && _selectedCategoryId != 'recent') {
          await CategoryService.addFileToCategory(_selectedCategoryId, filePath);
          await _loadData();
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: isDragOver
                ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                : colorScheme.surfaceContainerLow,
            border: Border(
              right: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '文件库',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    _SmallIconButton(
                      icon: Icons.create_new_folder_outlined,
                      onTap: _addCategory,
                      tooltip: '新建分类',
                    ),
                    _SmallIconButton(
                      icon: Icons.add,
                      onTap: _importFile,
                      tooltip: '导入文件',
                    ),
                  ],
                ),
              ),
              // Categories
              SizedBox(
                height: 140,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = cat.id == _selectedCategoryId;
                    final isSystem = cat.id == 'all' || cat.id == 'recent';

                    return DragTarget<String>(
                      onAcceptWithDetails: (details) async {
                        if (!isSystem) {
                          await CategoryService.addFileToCategory(
                              cat.id, details.data);
                          await _loadData();
                        }
                      },
                      builder: (ctx, candidate, rejected) {
                        final dragHover = candidate.isNotEmpty;
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          selected: isSelected,
                          selectedTileColor:
                              colorScheme.primaryContainer.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: dragHover
                                ? BorderSide(color: colorScheme.primary, width: 2)
                                : BorderSide.none,
                          ),
                          leading: Icon(
                            _getCategoryIcon(cat.icon),
                            size: 18,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            cat.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          trailing: !isSystem
                              ? InkWell(
                                  onTap: () => _deleteCategory(cat.id),
                                  child: Icon(Icons.close,
                                      size: 14,
                                      color: colorScheme.onSurfaceVariant),
                                )
                              : null,
                          onTap: () =>
                              setState(() => _selectedCategoryId = cat.id),
                        );
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              // File list
              Expanded(
                child: files.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.note_add_outlined,
                                  size: 32,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4)),
                              const SizedBox(height: 8),
                              Text(
                                '拖入文件或点击 + 导入',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final filePath = files[index];
                          final fileName = p.basename(filePath);
                          final ext = p.extension(filePath).toLowerCase();
                          final exists = File(filePath).existsSync();

                          return Draggable<String>(
                            data: filePath,
                            feedback: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      ext == '.pdf'
                                          ? Icons.picture_as_pdf
                                          : Icons.text_snippet,
                                      size: 16,
                                      color: ext == '.pdf'
                                          ? Colors.red
                                          : Colors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(fileName,
                                        style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: Icon(
                                ext == '.pdf'
                                    ? Icons.picture_as_pdf
                                    : Icons.text_snippet,
                                size: 18,
                                color: exists
                                    ? (ext == '.pdf' ? Colors.red : Colors.blue)
                                    : Colors.grey,
                              ),
                              title: Text(
                                fileName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: exists ? null : Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: exists ? () => _onFileTap(filePath) : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String icon) {
    switch (icon) {
      case 'all':
        return Icons.library_books_outlined;
      case 'recent':
        return Icons.history;
      default:
        return Icons.folder_outlined;
    }
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _SmallIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}
