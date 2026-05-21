import 'package:flutter/material.dart';
import 'package:engreader/models/llm_config.dart';
import 'package:engreader/services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  String _provider = 'deepseek';
  bool _loading = true;
  bool _obscureKey = true;

  static const _providers = {
    'deepseek': ('DeepSeek', 'https://api.deepseek.com/v1'),
    'openai': ('OpenAI', 'https://api.openai.com/v1'),
    'custom': ('自定义 (OpenAI Compatible)', ''),
  };

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await SettingsService.getLlmConfig();
    _apiUrlController.text = config.apiUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _provider = config.provider;
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
        const SnackBar(content: Text('设置已保存'), duration: Duration(seconds: 1)),
      );
    }
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
  void dispose() {
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton.icon(
            onPressed: _saveConfig,
            icon: const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('大模型 API 配置',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('配置用于英文解析的大模型接口',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            // Provider selection
            DropdownButtonFormField<String>(
              initialValue: _provider,
              decoration: const InputDecoration(
                labelText: 'API 提供商',
                border: OutlineInputBorder(),
              ),
              items: _providers.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value.$1)))
                  .toList(),
              onChanged: _onProviderChanged,
            ),
            const SizedBox(height: 16),
            // API URL
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API URL',
                hintText: 'https://api.deepseek.com/v1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // API Key
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Model
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: 'deepseek-chat',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveConfig,
                icon: const Icon(Icons.save),
                label: const Text('保存设置'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
