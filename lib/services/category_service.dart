import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:engreader/models/file_category.dart';

class CategoryService {
  static const _key = 'file_categories';

  static Future<List<FileCategory>> getCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) {
      return [
        FileCategory(id: 'all', name: '全部文件', icon: 'all'),
        FileCategory(id: 'recent', name: '最近阅读', icon: 'recent'),
      ];
    }
    final list = jsonDecode(json) as List;
    return list
        .map((e) => FileCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveCategories(List<FileCategory> categories) async {
    final prefs = await SharedPreferences.getInstance();
    final json = categories.map((c) => c.toJson()).toList();
    await prefs.setString(_key, jsonEncode(json));
  }

  static Future<void> addCategory(String name) async {
    final categories = await getCategories();
    categories.add(FileCategory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    ));
    await saveCategories(categories);
  }

  static Future<void> removeCategory(String id) async {
    final categories = await getCategories();
    categories.removeWhere((c) => c.id == id && c.id != 'all' && c.id != 'recent');
    await saveCategories(categories);
  }

  static Future<void> addFileToCategory(String categoryId, String filePath) async {
    final categories = await getCategories();
    final index = categories.indexWhere((c) => c.id == categoryId);
    if (index >= 0) {
      if (!categories[index].filePaths.contains(filePath)) {
        categories[index].filePaths.add(filePath);
        await saveCategories(categories);
      }
    }
  }

  static Future<void> removeFileFromCategory(String categoryId, String filePath) async {
    final categories = await getCategories();
    final index = categories.indexWhere((c) => c.id == categoryId);
    if (index >= 0) {
      categories[index].filePaths.remove(filePath);
      await saveCategories(categories);
    }
  }
}
