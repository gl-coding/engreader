class LlmConfig {
  final String apiUrl;
  final String apiKey;
  final String model;
  final String provider;

  const LlmConfig({
    required this.apiUrl,
    required this.apiKey,
    required this.model,
    this.provider = 'openai_compatible',
  });

  static const LlmConfig defaultConfig = LlmConfig(
    apiUrl: 'https://api.deepseek.com/v1',
    apiKey: '',
    model: 'deepseek-chat',
    provider: 'deepseek',
  );

  Map<String, dynamic> toJson() => {
        'apiUrl': apiUrl,
        'apiKey': apiKey,
        'model': model,
        'provider': provider,
      };

  factory LlmConfig.fromJson(Map<String, dynamic> json) => LlmConfig(
        apiUrl: json['apiUrl'] as String,
        apiKey: json['apiKey'] as String,
        model: json['model'] as String,
        provider: json['provider'] as String? ?? 'openai_compatible',
      );

  LlmConfig copyWith({
    String? apiUrl,
    String? apiKey,
    String? model,
    String? provider,
  }) =>
      LlmConfig(
        apiUrl: apiUrl ?? this.apiUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        provider: provider ?? this.provider,
      );
}
