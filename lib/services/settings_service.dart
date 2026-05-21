import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:engreader/models/llm_config.dart';

class SettingsService {
  static const _llmConfigKey = 'llm_config';
  static const _recentFilesKey = 'recent_files';
  static const _readingProgressKey = 'reading_progress';

  static Future<LlmConfig> getLlmConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_llmConfigKey);
    if (json == null) return LlmConfig.defaultConfig;
    return LlmConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  static Future<void> saveLlmConfig(LlmConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_llmConfigKey, jsonEncode(config.toJson()));
  }

  static Future<List<String>> getRecentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentFilesKey) ?? [];
  }

  static Future<void> addRecentFile(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final files = prefs.getStringList(_recentFilesKey) ?? [];
    files.remove(path);
    files.insert(0, path);
    if (files.length > 20) files.removeLast();
    await prefs.setStringList(_recentFilesKey, files);
  }

  static Future<void> removeRecentFile(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final files = prefs.getStringList(_recentFilesKey) ?? [];
    files.remove(path);
    await prefs.setStringList(_recentFilesKey, files);
  }

  /// Save reading progress for a file.
  /// [position] is a JSON-serializable map:
  ///   - PDF: {"page": int}
  ///   - TXT: {"scrollOffset": double}
  ///   - EPUB: {"cfi": String, "chapter": int}
  static Future<void> saveReadingProgress(
      String filePath, Map<String, dynamic> position) async {
    final prefs = await SharedPreferences.getInstance();
    final allProgress = prefs.getString(_readingProgressKey);
    final Map<String, dynamic> progressMap =
        allProgress != null ? jsonDecode(allProgress) as Map<String, dynamic> : {};
    progressMap[filePath] = position;
    await prefs.setString(_readingProgressKey, jsonEncode(progressMap));
  }

  /// Get saved reading progress for a file. Returns null if none saved.
  static Future<Map<String, dynamic>?> getReadingProgress(
      String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final allProgress = prefs.getString(_readingProgressKey);
    if (allProgress == null) return null;
    final progressMap = jsonDecode(allProgress) as Map<String, dynamic>;
    final entry = progressMap[filePath];
    if (entry == null) return null;
    return entry as Map<String, dynamic>;
  }
}
