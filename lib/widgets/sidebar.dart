import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:engreader/models/file_category.dart';
import 'package:engreader/services/category_service.dart';
import 'package:engreader/services/settings_service.dart';
import 'package:engreader/services/file_library_service.dart';
import 'package:engreader/screens/settings_screen.dart';
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
  bool _isAddingCategory = false;
  final _newCategoryController = TextEditingController();
  final _newCategoryFocusNode = FocusNode();
  List<String> _exportedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _newCategoryFocusNode.addListener(() {
      if (!_newCategoryFocusNode.hasFocus && _isAddingCategory) {
        _confirmAddCategory();
      }
    });
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    _newCategoryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final categories = await CategoryService.getCategories();
    final recent = await SettingsService.getRecentFiles();
    final exported = await _scanExportedFiles();
    setState(() {
      _categories = categories;
      _recentFiles = recent;
      _exportedFiles = exported;
      _loading = false;
    });
  }

  Future<List<String>> _scanExportedFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync().whereType<File>().where((f) {
        final name = p.basename(f.path);
        return name.endsWith('_annotated.pdf');
      }).toList();
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files.map((f) => f.path).toList();
    } catch (_) {
      return [];
    }
  }

  List<String> _getFilesForCategory(String categoryId) {
    if (categoryId == 'exported') {
      return _exportedFiles;
    }
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

  void _addCategory() {
    setState(() {
      _isAddingCategory = true;
      _newCategoryController.clear();
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      _newCategoryFocusNode.requestFocus();
    });
  }

  Future<void> _confirmAddCategory() async {
    final name = _newCategoryController.text.trim();
    setState(() => _isAddingCategory = false);
    if (name.isNotEmpty) {
      await CategoryService.addCategory(name);
      await _loadData();
    }
  }


  Future<void> _importFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'epub'],
    );

    if (result != null && result.files.single.path != null) {
      final externalPath = result.files.single.path!;
      final localPath = await FileLibraryService.importFile(externalPath);
      await SettingsService.addRecentFile(localPath);
      if (_selectedCategoryId != 'all' && _selectedCategoryId != 'recent') {
        await CategoryService.addFileToCategory(_selectedCategoryId, localPath);
      }
      await _loadData();
    }
  }

  Future<void> _openUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('打开网页'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入网页链接 (https://...)',
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
            child: const Text('打开'),
          ),
        ],
      ),
    );

    if (url != null && url.trim().isNotEmpty) {
      var finalUrl = url.trim();
      if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
        finalUrl = 'https://$finalUrl';
      }
      await SettingsService.addRecentFile(finalUrl);
      if (_selectedCategoryId != 'all' && _selectedCategoryId != 'recent') {
        await CategoryService.addFileToCategory(_selectedCategoryId, finalUrl);
      }
      await _loadData();
      widget.onFileSelected(finalUrl, 'web');
    }
  }

  void _onFileTap(String filePath) {
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      widget.onFileSelected(filePath, 'web');
      return;
    }
    final ext = p.extension(filePath).toLowerCase();
    final String fileType;
    switch (ext) {
      case '.pdf':
        fileType = 'pdf';
      case '.epub':
        fileType = 'epub';
      default:
        fileType = 'txt';
    }
    widget.onFileSelected(filePath, fileType);
  }

  Future<void> _deleteCategory(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: const Text('删除此文件夹？（文件不会被删除）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await CategoryService.removeCategory(id);
    if (_selectedCategoryId == id) {
      _selectedCategoryId = 'all';
    }
    await _loadData();
  }

  Future<void> _deleteFile(String filePath) async {
    final fileName = p.basename(filePath);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除 "$fileName" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await SettingsService.removeRecentFile(filePath);
    for (final cat in _categories) {
      if (cat.filePaths.contains(filePath)) {
        await CategoryService.removeFileFromCategory(cat.id, filePath);
      }
    }
    final file = File(filePath);
    if (file.existsSync()) {
      file.deleteSync();
    }
    await _loadData();
  }

  void _showFileContextMenu(
      BuildContext context, Offset position, String filePath) {
    final userCategories = _categories
        .where((c) => c.id != 'all' && c.id != 'recent')
        .toList();

    final items = <PopupMenuEntry<dynamic>>[
      if (userCategories.isNotEmpty)
        const PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text('移动到文件夹',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600)),
        ),
      ...userCategories.map((cat) {
        final isInCategory = cat.filePaths.contains(filePath);
        return PopupMenuItem(
          onTap: () async {
            if (isInCategory) {
              await CategoryService.removeFileFromCategory(cat.id, filePath);
            } else {
              await CategoryService.addFileToCategory(cat.id, filePath);
            }
            await _loadData();
          },
          child: Row(
            children: [
              Icon(
                isInCategory
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 16,
                color: isInCategory
                    ? _getCategoryColor(userCategories.indexOf(cat))
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(cat.name, style: const TextStyle(fontSize: 13)),
            ],
          ),
        );
      }),
      if (userCategories.isNotEmpty) const PopupMenuDivider(height: 8),
      PopupMenuItem(
        onTap: () => _deleteFile(filePath),
        child: const Row(
          children: [
            Icon(Icons.delete_outline, size: 16, color: Colors.red),
            SizedBox(width: 8),
            Text('删除', style: TextStyle(fontSize: 13, color: Colors.red)),
          ],
        ),
      ),
    ];

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: items,
    );
  }

  String? _getFileCategoryName(String filePath) {
    for (final cat in _categories) {
      if (cat.id == 'all' || cat.id == 'recent') continue;
      if (cat.filePaths.contains(filePath)) return cat.name;
    }
    return null;
  }

  Color _getFileCategoryColor(String filePath) {
    final userCats = _categories
        .where((c) => c.id != 'all' && c.id != 'recent')
        .toList();
    for (int i = 0; i < userCats.length; i++) {
      if (userCats[i].filePaths.contains(filePath)) {
        return _getCategoryColor(i);
      }
    }
    return Colors.grey;
  }

  static Color _getCategoryColor(int index) {
    const colors = [
      Color(0xFF00BCD4), // cyan
      Color(0xFFE74C3C), // red
      Color(0xFF9B59B6), // purple
      Color(0xFFF39C12), // orange
      Color(0xFF27AE60), // green
      Color(0xFF3498DB), // blue
      Color(0xFFE91E63), // pink
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFBFAF8);
    final dividerColor = isDark
        ? const Color(0xFF38383A)
        : const Color(0xFFE8E5E0);
    final subtleText = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8E8E93);

    if (_loading) {
      return Container(
        color: bgColor,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final userCategories = _categories
        .where((c) => c.id != 'all' && c.id != 'recent')
        .toList();
    final allFileCount = _getFilesForCategory('all').length;

    return Row(
      children: [
        // Left panel - navigation & categories.
        SizedBox(
          width: 180,
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                right: BorderSide(color: dividerColor, width: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Settings icon.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 40, 16, 8),
                  child: GestureDetector(
                    onTap: () => showSettingsDialog(context),
                    child: Icon(Icons.settings_outlined,
                        size: 22, color: subtleText),
                  ),
                ),
                // Navigation items.
                const SizedBox(height: 8),
                _NavItem(
                  icon: Icons.description_outlined,
                  label: '全部文件',
                  count: allFileCount,
                  isSelected: _selectedCategoryId == 'all',
                  onTap: () => setState(() => _selectedCategoryId = 'all'),
                ),
                _NavItem(
                  icon: Icons.schedule_rounded,
                  label: '最近阅读',
                  count: _recentFiles.length,
                  isSelected: _selectedCategoryId == 'recent',
                  onTap: () => setState(() => _selectedCategoryId = 'recent'),
                ),
                _NavItem(
                  icon: Icons.file_download_outlined,
                  label: '导出文件',
                  count: _exportedFiles.length,
                  isSelected: _selectedCategoryId == 'exported',
                  onTap: () => setState(() => _selectedCategoryId = 'exported'),
                ),
                // Folders section.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        '文件夹',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: subtleText,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _addCategory,
                        child: Icon(Icons.add, size: 18, color: subtleText),
                      ),
                    ],
                  ),
                ),
                // Category list with colored dots.
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: userCategories.length + (_isAddingCategory ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Inline editing row for new category (at top).
                      if (_isAddingCategory && index == 0) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _getCategoryColor(0),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _newCategoryController,
                                  focusNode: _newCategoryFocusNode,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                    hintText: '文件夹名称',
                                    hintStyle: TextStyle(fontSize: 13),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        vertical: 4),
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) => _confirmAddCategory(),
                                  onEditingComplete: _confirmAddCategory,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final catIndex = _isAddingCategory ? index - 1 : index;
                      final cat = userCategories[catIndex];
                      final isSelected = cat.id == _selectedCategoryId;
                      final color = _getCategoryColor(catIndex);

                      return DragTarget<String>(
                        onAcceptWithDetails: (details) async {
                          await CategoryService.addFileToCategory(
                              cat.id, details.data);
                          await _loadData();
                        },
                        builder: (ctx, candidate, rejected) {
                          final dragHover = candidate.isNotEmpty;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark
                                      ? const Color(0xFF3A3A3C)
                                      : const Color(0xFFF0EDEA))
                                  : dragHover
                                      ? (isDark
                                          ? const Color(0xFF3A3A3C)
                                          : const Color(0xFFF0EDEA))
                                      : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(
                                  () => _selectedCategoryId = cat.id),
                              onSecondaryTap: () => _deleteCategory(cat.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 9),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        cat.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: colorScheme.onSurface,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (cat.filePaths.isNotEmpty)
                                      Text(
                                        '${cat.filePaths.length}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: subtleText,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right panel - file list.
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
                  child: Row(
                    children: [
                      const Spacer(),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'file') {
                            _importFile();
                          } else if (value == 'url') {
                            _openUrl();
                          }
                        },
                        offset: const Offset(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'file',
                            height: 36,
                            child: Row(
                              children: [
                                Icon(Icons.file_open_outlined, size: 16),
                                SizedBox(width: 8),
                                Text('导入文件',
                                    style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'url',
                            height: 36,
                            child: Row(
                              children: [
                                Icon(Icons.language, size: 16),
                                SizedBox(width: 8),
                                Text('打开网页',
                                    style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                        child: Material(
                          color: const Color(0xFF3478F6),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, size: 14,
                                    color: Colors.white),
                                SizedBox(width: 4),
                                Text('导入',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500)),
                                SizedBox(width: 2),
                                Icon(Icons.arrow_drop_down, size: 14,
                                    color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
                  child: Text(
                    _selectedCategoryId == 'exported'
                        ? '导出文件'
                        : _categories
                            .firstWhere(
                              (c) => c.id == _selectedCategoryId,
                              orElse: () =>
                                  FileCategory(id: '', name: '全部文件'),
                            )
                            .name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // File list.
                Expanded(
                  child: _buildFileList(colorScheme, isDark, subtleText),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileList(
      ColorScheme colorScheme, bool isDark, Color subtleText) {
    final files = _getFilesForCategory(_selectedCategoryId);

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_add_rounded, size: 40, color: subtleText),
            const SizedBox(height: 12),
            Text(
              '没有文件\n点击导入或拖入文件',
              style: TextStyle(fontSize: 13, color: subtleText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return DragTarget<String>(
      onAcceptWithDetails: (details) async {
        if (_selectedCategoryId != 'all' && _selectedCategoryId != 'recent') {
          await CategoryService.addFileToCategory(
              _selectedCategoryId, details.data);
          await _loadData();
        }
      },
      builder: (context, candidateData, rejectedData) {
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          itemCount: files.length,
          separatorBuilder: (_, __) => Divider(
            height: 0.5,
            indent: 56,
            color: isDark
                ? const Color(0xFF38383A)
                : const Color(0xFFF0EDEA),
          ),
          itemBuilder: (context, index) {
            final filePath = files[index];
            final isUrl = filePath.startsWith('http://') ||
                filePath.startsWith('https://');
            final fileName = isUrl
                ? Uri.tryParse(filePath)?.host ?? filePath
                : p.basenameWithoutExtension(filePath);
            final ext = isUrl ? '.web' : p.extension(filePath).toLowerCase();
            final exists = isUrl || File(filePath).existsSync();
            final categoryName = _getFileCategoryName(filePath);
            final categoryColor = _getFileCategoryColor(filePath);

            String dateStr = '';
            if (!isUrl && exists) {
              final stat = File(filePath).statSync();
              final d = stat.modified;
              dateStr = '${d.year}年${d.month}月${d.day}日';
            }

            return Draggable<String>(
              data: filePath,
              feedback: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_fileIcon(ext), size: 14, color: _fileColor(ext)),
                      const SizedBox(width: 6),
                      Text(fileName, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
              child: GestureDetector(
                onSecondaryTapUp: (details) {
                  _showFileContextMenu(
                      context, details.globalPosition, filePath);
                },
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: exists ? () => _onFileTap(filePath) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 10),
                      child: Row(
                        children: [
                          // File type thumbnail.
                          Container(
                            width: 44,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF3A3A3C)
                                  : const Color(0xFFF5F3F0),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF48484A)
                                    : const Color(0xFFE8E5E0),
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                _fileIcon(ext),
                                size: 20,
                                color: exists ? _fileColor(ext) : Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // File info.
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: exists
                                        ? colorScheme.onSurface
                                        : Colors.grey,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: subtleText,
                                  ),
                                ),
                                if (categoryName != null) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          categoryColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      categoryName,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: categoryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static IconData _fileIcon(String ext) {
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf_rounded;
      case '.epub':
        return Icons.auto_stories_rounded;
      case '.web':
        return Icons.language_rounded;
      default:
        return Icons.text_snippet_rounded;
    }
  }

  static Color _fileColor(String ext) {
    switch (ext) {
      case '.pdf':
        return const Color(0xFFE74C3C);
      case '.epub':
        return const Color(0xFF27AE60);
      case '.web':
        return const Color(0xFFF39C12);
      default:
        return const Color(0xFF3498DB);
    }
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF0EDEA))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 18,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0xFF8E8E93)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8E8E93),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
