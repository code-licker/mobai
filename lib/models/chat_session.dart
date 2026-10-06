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
  final String id;
  String title;
  final String modelId;
  final String modelName;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.modelId,
    required this.modelName,
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
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] ?? '',
    title: json['title'] ?? 'Chat',
    modelId: json['modelId'] ?? '',
    modelName: json['modelName'] ?? 'AI Model',
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
