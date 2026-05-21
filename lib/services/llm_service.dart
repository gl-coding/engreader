import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:engreader/models/llm_config.dart';

class LlmService {
  final LlmConfig config;

  LlmService(this.config);

  Future<String> translateWord(String word) async {
    final prompt = '''Please provide a concise explanation for the English word "$word":
1. Phonetic transcription (IPA)
2. Part of speech
3. Chinese meaning (主要释义)
4. One example sentence with Chinese translation

Format:
/$word/ [phonetic]
[pos.] 中文释义
Example: ...
译: ...''';

    return _chat(prompt);
  }

  Future<String> translateSentence(String sentence) async {
    final prompt = '''Please analyze this English sentence:
"$sentence"

Provide:
1. Chinese translation (中文翻译)
2. Key grammar points (语法要点, if any notable structure)
3. Key vocabulary (重点词汇, 2-3 words with brief Chinese meaning)

Format:
翻译: ...
语法: ...
词汇: word1 - 释义; word2 - 释义''';

    return _chat(prompt);
  }

  Future<String> _chat(String prompt) async {
    if (config.apiKey.isEmpty) {
      return '请先在设置中配置 API Key';
    }

    try {
      final response = await http.post(
        Uri.parse('${config.apiUrl}/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config.apiKey}',
        },
        body: jsonEncode({
          'model': config.model,
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are an English language tutor helping Chinese students. Be concise and accurate.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 500,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List;
        if (choices.isNotEmpty) {
          final message = choices[0]['message'] as Map<String, dynamic>;
          return message['content'] as String;
        }
        return '解析失败：无返回内容';
      } else {
        return '请求失败 (${response.statusCode}): ${response.body}';
      }
    } catch (e) {
      return '请求出错: $e';
    }
  }
}
