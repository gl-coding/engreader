import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:engreader/models/llm_config.dart';

class AnnotationTemplate {
  final String id;
  final String name;
  final String prompt;
  final bool isBuiltin;

  const AnnotationTemplate({
    required this.id,
    required this.name,
    required this.prompt,
    this.isBuiltin = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prompt': prompt,
        'isBuiltin': isBuiltin,
      };

  factory AnnotationTemplate.fromJson(Map<String, dynamic> json) =>
      AnnotationTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        prompt: json['prompt'] as String,
        isBuiltin: json['isBuiltin'] as bool? ?? false,
      );

  static const builtinTemplates = [
    AnnotationTemplate(
      id: 'empty',
      name: '仅标记',
      prompt: '',
      isBuiltin: true,
    ),
    AnnotationTemplate(
      id: 'word_translate',
      name: '单词翻译',
      prompt: '''Please provide a concise explanation for the English word "\$TEXT":
1. Phonetic transcription (IPA)
2. Part of speech
3. Chinese meaning (主要释义)
4. One example sentence with Chinese translation

Format:
/\$TEXT/ [phonetic]
[pos.] 中文释义
Example: ...
译: ...''',
      isBuiltin: true,
    ),
    AnnotationTemplate(
      id: 'sentence_translate',
      name: '句子翻译',
      prompt: '''Please analyze this English sentence:
"\$TEXT"

Provide:
1. Chinese translation (中文翻译)
2. Key grammar points (语法要点, if any notable structure)
3. Key vocabulary (重点词汇, 2-3 words with brief Chinese meaning)

Format:
翻译: ...
语法: ...
词汇: word1 - 释义; word2 - 释义''',
      isBuiltin: true,
    ),
  ];
}

class SettingsService {
  static const _llmConfigKey = 'llm_config';
  static const _recentFilesKey = 'recent_files';
  static const _readingProgressKey = 'reading_progress';
  static const _activeTemplatesKey = 'active_templates';
  static const _templatePromptsKey = 'template_prompts';
  static const _customTemplatesKey = 'custom_templates';

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

  /// Get active (selected) template IDs. Defaults to ['empty'].
  static Future<List<String>> getActiveTemplateIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_activeTemplatesKey) ?? ['empty'];
  }

  /// Save active template IDs.
  static Future<void> saveActiveTemplateIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_activeTemplatesKey, ids);
  }

  /// Get custom prompt overrides for builtin templates (template_id -> prompt).
  static Future<Map<String, String>> getTemplatePrompts() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_templatePromptsKey);
    if (json == null) return {};
    final map = jsonDecode(json) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, v as String));
  }

  /// Save a custom prompt override for a builtin template.
  static Future<void> saveTemplatePrompt(String templateId, String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getTemplatePrompts();
    existing[templateId] = prompt;
    await prefs.setString(_templatePromptsKey, jsonEncode(existing));
  }

  /// Get user-created custom templates.
  static Future<List<AnnotationTemplate>> getCustomTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_customTemplatesKey);
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list
        .map((e) => AnnotationTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Save user-created custom templates list.
  static Future<void> saveCustomTemplates(List<AnnotationTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _customTemplatesKey, jsonEncode(templates.map((t) => t.toJson()).toList()));
  }

  /// Add a new custom template.
  static Future<void> addCustomTemplate(AnnotationTemplate template) async {
    final templates = await getCustomTemplates();
    templates.add(template);
    await saveCustomTemplates(templates);
  }

  /// Update an existing custom template.
  static Future<void> updateCustomTemplate(AnnotationTemplate template) async {
    final templates = await getCustomTemplates();
    final idx = templates.indexWhere((t) => t.id == template.id);
    if (idx >= 0) {
      templates[idx] = template;
      await saveCustomTemplates(templates);
    }
  }

  /// Delete a custom template.
  static Future<void> deleteCustomTemplate(String templateId) async {
    final templates = await getCustomTemplates();
    templates.removeWhere((t) => t.id == templateId);
    await saveCustomTemplates(templates);
    // Also remove from active list.
    final activeIds = await getActiveTemplateIds();
    activeIds.remove(templateId);
    await saveActiveTemplateIds(activeIds);
  }

  /// Get all templates (builtin + custom) with effective prompts.
  static Future<List<AnnotationTemplate>> getAllTemplates() async {
    final overrides = await getTemplatePrompts();
    final builtins = AnnotationTemplate.builtinTemplates.map((t) => AnnotationTemplate(
          id: t.id,
          name: t.name,
          prompt: overrides[t.id] ?? t.prompt,
          isBuiltin: true,
        ));
    final custom = await getCustomTemplates();
    return [...builtins, ...custom];
  }

  /// Get active templates with effective prompts applied.
  static Future<List<AnnotationTemplate>> getActiveTemplates() async {
    final ids = await getActiveTemplateIds();
    final all = await getAllTemplates();
    return all.where((t) => ids.contains(t.id)).toList();
  }
}
