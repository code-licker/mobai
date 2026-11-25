class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] ?? '',
    text: json['text'] ?? '',
    isUser: json['isUser'] ?? false,
    timestamp: json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
        : DateTime.now(),
  );
}

class ChatSession {
  static const String defaultSystemPrompt =
      'You are a helpful, accurate, and concise AI assistant running locally on-device.';

  final String id;
  String title;
  final String modelId;
  final String modelName;
  String? modelFilePath;
  double temperature;
  String systemPrompt;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.modelId,
    required this.modelName,
    this.modelFilePath,
    this.temperature = 0.7,
    this.systemPrompt = defaultSystemPrompt,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  String get lastMessagePreview {
    if (messages.isEmpty) return 'No messages yet';
    return messages.last.text;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'modelId': modelId,
    'modelName': modelName,
    if (modelFilePath != null) 'modelFilePath': modelFilePath,
    'temperature': temperature,
    'systemPrompt': systemPrompt,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] ?? '',
    title: json['title'] ?? 'Chat',
    modelId: json['modelId'] ?? '',
    modelName: json['modelName'] ?? 'AI Model',
    modelFilePath: json['modelFilePath'] as String?,
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
    systemPrompt: (json['systemPrompt'] as String?)?.isNotEmpty == true
        ? json['systemPrompt'] as String
        : defaultSystemPrompt,
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
        : DateTime.now(),
    updatedAt: json['updatedAt'] != null
        ? DateTime.tryParse(json['updatedAt']) ?? DateTime.now()
        : DateTime.now(),
    messages: (json['messages'] as List<dynamic>?)
            ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
