import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mobai/models/chat_session.dart';

class ChatSessionService extends ChangeNotifier {
  static final ChatSessionService _instance = ChatSessionService._internal();
  factory ChatSessionService() => _instance;
  ChatSessionService._internal() {
    _initSampleSessions();
  }

  final List<ChatSession> _sessions = [];

  List<ChatSession> get sessions => List.unmodifiable(_sessions);

  void _initSampleSessions() {
    final now = DateTime.now();
    _sessions.addAll([
      ChatSession(
        id: 'session-1',
        title: 'Flutter UI Architecture Ideas',
        modelId: 'qwen2.5-0.5b-instruct-q4',
        modelName: 'Qwen 2.5 0.5B Instruct',
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(minutes: 15)),
        messages: [
          ChatMessage(
            id: 'm1',
            text: 'What are best practices for state management in Flutter with on-device LLMs?',
            isUser: true,
            timestamp: now.subtract(const Duration(hours: 2)),
          ),
          ChatMessage(
            id: 'm2',
            text: 'For local on-device inference, decouple inference streams into background isolates or dedicated services. Use ChangeNotifier or Bloc to cleanly emit chunked tokens to the chat UI without blocking frame rendering.',
            isUser: false,
            timestamp: now.subtract(const Duration(hours: 2, minutes: -1)),
          ),
        ],
      ),
      ChatSession(
        id: 'session-2',
        title: 'Quantization Comparison Q4 vs FP16',
        modelId: 'llama-3.2-1b-instruct-q4',
        modelName: 'Llama 3.2 1B Instruct',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 5)),
        messages: [
          ChatMessage(
            id: 'm3',
            text: 'Explain the trade-offs of Q4_K_M vs 16-bit float on mobile memory.',
            isUser: true,
            timestamp: now.subtract(const Duration(days: 1)),
          ),
          ChatMessage(
            id: 'm4',
            text: 'Q4_K_M reduces model weight size by roughly 70%, allowing 1B-3B models to run inside 2-4GB mobile RAM while retaining ~97% of perplexity benchmark performance.',
            isUser: false,
            timestamp: now.subtract(const Duration(days: 1, minutes: -1)),
          ),
        ],
      ),
    ]);
  }

  ChatSession createSession({
    required String modelId,
    required String modelName,
    String? initialPrompt,
  }) {
    final now = DateTime.now();
    final newId = 'session-${DateTime.now().millisecondsSinceEpoch}';
    final session = ChatSession(
      id: newId,
      title: initialPrompt != null && initialPrompt.isNotEmpty
          ? (initialPrompt.length > 28 ? '${initialPrompt.substring(0, 28)}...' : initialPrompt)
          : 'New Chat',
      modelId: modelId,
      modelName: modelName,
      createdAt: now,
      updatedAt: now,
      messages: [],
    );

    _sessions.insert(0, session);
    notifyListeners();
    return session;
  }

  ChatSession? getSessionById(String id) {
    try {
      return _sessions.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  void updateSessionTitle(String sessionId, String newTitle) {
    final session = getSessionById(sessionId);
    if (session != null) {
      session.title = newTitle;
      notifyListeners();
    }
  }

  void deleteSession(String id) {
    _sessions.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  void clearAllSessions() {
    _sessions.clear();
    notifyListeners();
  }

  Future<void> sendMessage({
    required String sessionId,
    required String prompt,
    void Function(String chunk)? onTokenChunk,
  }) async {
    final session = getSessionById(sessionId);
    if (session == null) return;

    final userMsg = ChatMessage(
      id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
      text: prompt,
      isUser: true,
      timestamp: DateTime.now(),
    );

    session.messages.add(userMsg);
    session.updatedAt = DateTime.now();
    if (session.messages.length == 1 && session.title == 'New Chat') {
      session.title = prompt.length > 26 ? '${prompt.substring(0, 26)}...' : prompt;
    }
    notifyListeners();

    // Stream realistic model response
    final responseText = _generateMockResponse(session.modelName, prompt);
    final botMsgId = 'bot-${DateTime.now().millisecondsSinceEpoch}';
    final botMsg = ChatMessage(
      id: botMsgId,
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
    );
    session.messages.add(botMsg);
    notifyListeners();

    final words = responseText.split(' ');
    String currentText = '';
    for (int i = 0; i < words.length; i++) {
      await Future.delayed(const Duration(milliseconds: 35));
      currentText += (i == 0 ? '' : ' ') + words[i];
      final index = session.messages.indexWhere((m) => m.id == botMsgId);
      if (index != -1) {
        session.messages[index] = ChatMessage(
          id: botMsgId,
          text: currentText,
          isUser: false,
          timestamp: botMsg.timestamp,
        );
      }
      onTokenChunk?.call(words[i]);
      notifyListeners();
    }
  }

  String _generateMockResponse(String modelName, String prompt) {
    final p = prompt.toLowerCase();
    if (p.contains('hello') || p.contains('hi')) {
      return 'Hello! I am $modelName running on your mobile device. How can I assist your workflow today?';
    } else if (p.contains('code') || p.contains('flutter') || p.contains('dart')) {
      return 'Here is how you can implement that in Flutter:\n\n```dart\n// Clean reactive widget\nConsumer<AppState>(\n  builder: (context, state, child) => Text(state.summary),\n);\n```\nThis ensures high frame rates and zero UI stutter.';
    } else if (p.contains('download') || p.contains('size') || p.contains('gguf')) {
      return '$modelName uses GGUF quantization format. This optimizes memory cache alignment and delivers fast on-device token inference with minimal battery drain.';
    } else {
      return 'I processed your prompt ("$prompt") using $modelName on local device memory. Responses are kept private and execute with low latency.';
    }
  }
}
