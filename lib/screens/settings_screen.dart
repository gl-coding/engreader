import 'package:flutter/material.dart';
import 'package:engreader/models/llm_config.dart';
import 'package:engreader/services/llm_service.dart';
import 'package:engreader/services/log_service.dart';
import 'package:engreader/services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSettingsDialog();
    });
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _SettingsDialog(),
    ).then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}

void showSettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  String _selectedSection = 'llm';
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  String _provider = 'deepseek';
  bool _loading = true;
  bool _obscureKey = true;
  bool _testing = false;
  String? _testResult;
  bool? _testSuccess;
  List<String> _activeTemplateIds = ['empty'];
  String? _editingTemplateId;
  final _promptController = TextEditingController();
  Map<String, String> _customPrompts = {};
  List<AnnotationTemplate> _customTemplates = [];

  static const _providers = {
    'deepseek': ('DeepSeek', 'https://api.deepseek.com/v1'),
    'openai': ('OpenAI', 'https://api.openai.com/v1'),
    'custom': ('自定义 (OpenAI Compatible)', ''),
  };

  static const _sections = [
    ('llm', Icons.smart_toy_outlined, '模型配置'),
    ('templates', Icons.style_outlined, '批注模板'),
    ('debug', Icons.bug_report_outlined, '调试'),
    ('about', Icons.info_outline, '关于'),
  ];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await SettingsService.getLlmConfig();
    final templateIds = await SettingsService.getActiveTemplateIds();
    final customPrompts = await SettingsService.getTemplatePrompts();
    final customTemplates = await SettingsService.getCustomTemplates();
    _apiUrlController.text = config.apiUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _provider = config.provider;
    _activeTemplateIds = templateIds;
    _customPrompts = customPrompts;
    _customTemplates = customTemplates;
    setState(() => _loading = false);
  }

  Future<void> _saveConfig() async {
    final config = LlmConfig(
      apiUrl: _apiUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      provider: _provider,
    );
    await SettingsService.saveLlmConfig(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('设置已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
      _testSuccess = null;
    });

    final config = LlmConfig(
      apiUrl: _apiUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      provider: _provider,
    );

    if (config.apiKey.isEmpty) {
      setState(() {
        _testing = false;
        _testSuccess = false;
        _testResult = '请先填写 API Key';
      });
      return;
    }

    final service = LlmService(config);
    final result = await service.translateWord('hello');

    if (!mounted) return;
    final success = !result.startsWith('请求失败') &&
        !result.startsWith('请求出错') &&
        !result.startsWith('请先在设置中配置');
    setState(() {
      _testing = false;
      _testSuccess = success;
      _testResult = success ? '连接成功！模型响应正常。' : result;
    });
  }

  void _onProviderChanged(String? value) {
    if (value == null) return;
    setState(() {
      _provider = value;
      final (_, defaultUrl) = _providers[value]!;
      if (defaultUrl.isNotEmpty) {
        _apiUrlController.text = defaultUrl;
      }
      if (value == 'deepseek') {
        _modelController.text = 'deepseek-chat';
      } else if (value == 'openai') {
        _modelController.text = 'gpt-4o-mini';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 680,
        height: 480,
        child: Row(
          children: [
            // Left sidebar
            Container(
              width: 180,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF5F3F0),
                border: Border(
                  right: BorderSide(
                    color: isDark
                        ? const Color(0xFF38383A)
                        : const Color(0xFFE0DDD8),
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                    child: Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  ..._sections.map((s) {
                    final (id, icon, label) = s;
                    final selected = _selectedSection == id;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 1),
                      child: Material(
                        color: selected
                            ? (isDark
                                ? const Color(0xFF3A3A3C)
                                : const Color(0xFFE8E5E0))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () =>
                              setState(() => _selectedSection = id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Icon(icon,
                                    size: 18,
                                    color: selected
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: selected
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            // Right content
            Expanded(
              child: Container(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildContent(colorScheme, isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme, bool isDark) {
    switch (_selectedSection) {
      case 'llm':
        return _buildLlmSection(colorScheme);
      case 'templates':
        return _buildTemplatesSection(colorScheme);
      case 'debug':
        return _buildDebugSection(colorScheme);
      case 'about':
        return _buildAboutSection(colorScheme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLlmSection(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('大模型 API 配置',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text('配置用于英文解析的大模型接口',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _provider,
            decoration: const InputDecoration(
              labelText: 'API 提供商',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _providers.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value.$1)))
                .toList(),
            onChanged: _onProviderChanged,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiUrlController,
            decoration: const InputDecoration(
              labelText: 'API URL',
              hintText: 'https://api.deepseek.com/v1',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureKey ? Icons.visibility_off : Icons.visibility,
                    size: 18),
                onPressed: () =>
                    setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: '模型名称',
              hintText: 'deepseek-chat',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveConfig,
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('保存', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 16),
                  label: Text(_testing ? '测试中...' : '测试连接',
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _testSuccess == true
                    ? Colors.green.withValues(alpha: 0.08)
                    : Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testSuccess == true
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testSuccess == true
                        ? Icons.check_circle
                        : Icons.error,
                    color:
                        _testSuccess == true ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testSuccess == true
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTemplatesSection(ColorScheme colorScheme) {
    final allTemplates = [
      ...AnnotationTemplate.builtinTemplates,
      ..._customTemplates,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('批注模板',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text('勾选模板启用批注，点击展开可查看/编辑提示词',
                        style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              SizedBox(
                height: 30,
                child: FilledButton.icon(
                  onPressed: _addNewTemplate,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('新增', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...allTemplates.map((t) => _buildTemplateCard(t, colorScheme)),
          const SizedBox(height: 12),
          Text(
            '提示：\$TEXT 为选中文本占位符；「仅标记」不调用 LLM。',
            style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(
      AnnotationTemplate t, ColorScheme colorScheme) {
    final isActive = _activeTemplateIds.contains(t.id);
    final isEditing = _editingTemplateId == t.id;
    final effectivePrompt =
        t.isBuiltin ? (_customPrompts[t.id] ?? t.prompt) : t.prompt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isActive
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(10),
                bottom: Radius.circular(isEditing ? 0 : 10),
              ),
              onTap: () {
                setState(() {
                  if (isActive) {
                    _activeTemplateIds.remove(t.id);
                  } else {
                    _activeTemplateIds.add(t.id);
                  }
                });
                SettingsService.saveActiveTemplateIds(_activeTemplateIds);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      isActive
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: isActive
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                t.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              if (t.isBuiltin) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.3),
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Text('内置',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: colorScheme
                                              .onSurfaceVariant)),
                                ),
                              ],
                            ],
                          ),
                          if (t.prompt.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              t.prompt.length > 40
                                  ? '${t.prompt.substring(0, 40)}...'
                                  : t.prompt,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ] else ...[
                            const SizedBox(height: 2),
                            Text('仅标记高亮，不调用大模型',
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        colorScheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                    if (t.prompt.isNotEmpty || !t.isBuiltin)
                      IconButton(
                        icon: Icon(
                          isEditing
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          setState(() {
                            if (isEditing) {
                              _editingTemplateId = null;
                            } else {
                              _editingTemplateId = t.id;
                              _promptController.text = effectivePrompt;
                            }
                          });
                        },
                        tooltip: isEditing ? '收起' : '编辑',
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                    if (!t.isBuiltin)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
                        onPressed: () => _deleteTemplate(t.id),
                        tooltip: '删除模板',
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),
            if (isEditing) ...[
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!t.isBuiltin) ...[
                      TextField(
                        controller: TextEditingController(text: t.name),
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: '模板名称',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        onChanged: (v) {
                          final idx = _customTemplates
                              .indexWhere((ct) => ct.id == t.id);
                          if (idx >= 0) {
                            _customTemplates[idx] = AnnotationTemplate(
                              id: t.id,
                              name: v,
                              prompt: _customTemplates[idx].prompt,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      '提示词（\$TEXT 为选中文本占位符）',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _promptController,
                      maxLines: 8,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          height: 28,
                          child: FilledButton.icon(
                            onPressed: () =>
                                _saveTemplatePrompt(t),
                            icon: const Icon(Icons.save, size: 14),
                            label: const Text('保存',
                                style: TextStyle(fontSize: 12)),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (t.isBuiltin &&
                            _customPrompts.containsKey(t.id))
                          SizedBox(
                            height: 28,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _resetBuiltinPrompt(t),
                              icon:
                                  const Icon(Icons.restore, size: 14),
                              label: const Text('恢复默认',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveTemplatePrompt(AnnotationTemplate t) async {
    if (t.isBuiltin) {
      await SettingsService.saveTemplatePrompt(
          t.id, _promptController.text);
      setState(() {
        _customPrompts[t.id] = _promptController.text;
      });
    } else {
      final idx = _customTemplates.indexWhere((ct) => ct.id == t.id);
      if (idx >= 0) {
        final updated = AnnotationTemplate(
          id: t.id,
          name: _customTemplates[idx].name,
          prompt: _promptController.text,
        );
        _customTemplates[idx] = updated;
        await SettingsService.saveCustomTemplates(_customTemplates);
        setState(() {});
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _resetBuiltinPrompt(AnnotationTemplate t) async {
    final original = AnnotationTemplate.builtinTemplates
        .firstWhere((bt) => bt.id == t.id);
    await SettingsService.saveTemplatePrompt(t.id, original.prompt);
    setState(() {
      _customPrompts.remove(t.id);
      _promptController.text = original.prompt;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('已恢复默认'),
            duration: Duration(seconds: 1)),
      );
    }
  }

  void _addNewTemplate() {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final template = AnnotationTemplate(
      id: id,
      name: '新模板',
      prompt: '请分析以下英文内容："\$TEXT"\n\n提供中文解释。',
    );
    setState(() {
      _customTemplates.add(template);
      _editingTemplateId = id;
      _promptController.text = template.prompt;
    });
    SettingsService.saveCustomTemplates(_customTemplates);
  }

  Future<void> _deleteTemplate(String templateId) async {
    await SettingsService.deleteCustomTemplate(templateId);
    setState(() {
      _customTemplates.removeWhere((t) => t.id == templateId);
      _activeTemplateIds.remove(templateId);
      if (_editingTemplateId == templateId) {
        _editingTemplateId = null;
      }
    });
  }

  Widget _buildDebugSection(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('调试',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text('开发与诊断工具',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              final path = await LogService.getLogPath();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('日志路径: $path'),
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            },
            icon: const Icon(Icons.description_outlined, size: 16),
            label:
                const Text('查看日志文件路径', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('关于',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface)),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.auto_stories,
                  size: 36, color: colorScheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('EngReader',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface)),
                  Text('v1.0.0',
                      style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '英文阅读器，支持 PDF、TXT、EPUB 和网页链接。\n通过 LLM 智能批注帮助理解英文内容。',
            style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                height: 1.6),
          ),
        ],
      ),
    );
  }
}
