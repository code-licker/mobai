import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mobai/models/chat_session.dart';
import 'package:mobai/services/local_inference_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';

class ModelFileNotFoundException implements Exception {
  final String modelId;
  final String modelName;
  final String message;

  const ModelFileNotFoundException({
    required this.modelId,
    required this.modelName,
    required this.message,
  });

  @override
  String toString() => message;
}

typedef InferenceStreamBuilder = Stream<String> Function({
  required String modelPath,
  required List<ChatMessage> priorHistory,
  required String userPrompt,
  required String systemPrompt,
  required double temperature,
});

class ChatSessionService extends ChangeNotifier {
  static final ChatSessionService _instance = ChatSessionService._internal();
  factory ChatSessionService() => _instance;
  ChatSessionService._internal();

  final StorageService _storageService = StorageService();
  final ModelManagerService _modelManager = ModelManagerService();
  final LocalInferenceService _inferenceService = LocalInferenceService();

  InferenceStreamBuilder? _inferenceOverride;
  VoidCallback? _stopOverride;
  final Map<String, Future<void>> _saveQueues = {};

  final List<ChatSession> _sessions = [];

  List<ChatSession> get sessions => List.unmodifiable(_sessions);

  @visibleForTesting
  void configureForTesting({
    InferenceStreamBuilder? inferenceOverride,
    VoidCallback? stopOverride,
  }) {
    _inferenceOverride = inferenceOverride;
    _stopOverride = stopOverride;
    _saveQueues.clear();
    _sessions.clear();
  }

  /// Waits for all queued session file writes to complete.
  Future<void> flushPendingSaves() async {
    if (_saveQueues.isEmpty) return;
    await Future.wait(_saveQueues.values.toList());
  }

  File _sessionFile(String sessionId) {
    final safeId = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File(
      '${_storageService.chatsPath}${Platform.pathSeparator}$safeId.json',
    );
  }

  /// Loads all persisted chats from `MobAI/chats/*.json`.
  Future<void> loadSessionsFromStorage() async {
    _sessions.clear();
    if (!_storageService.isInitialized) {
      notifyListeners();
      return;
    }

    final chatsDir = _storageService.chatsDirectory;
    if (!await chatsDir.exists()) {
      await chatsDir.create(recursive: true);
      notifyListeners();
      return;
    }

    final loaded = <ChatSession>[];
    await for (final entity in chatsDir.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
        try {
          final raw = await entity.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            final session = ChatSession.fromJson(decoded);
            if (session.id.isNotEmpty) {
              loaded.add(session);
            }
          }
        } catch (e) {
          debugPrint('Skipping corrupt chat file ${entity.path}: $e');
        }
      }
    }

    loaded.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _sessions.addAll(loaded);
    notifyListeners();
  }

  Future<void> _saveSession(ChatSession session) {
    if (!_storageService.isInitialized) return Future.value();
    final previous = _saveQueues[session.id] ?? Future.value();
    final next = previous.catchError((_) {}).then((_) async {
      final dir = _storageService.chatsDirectory;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final target = _sessionFile(session.id);
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(session.toJson()), flush: true);
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);
    });
    _saveQueues[session.id] = next.whenComplete(() {
      if (identical(_saveQueues[session.id], next)) {
        _saveQueues.remove(session.id);
      }
    });
    return next;
  }

  ChatSession createSession({
    required String modelId,
    required String modelName,
    String? modelFilePath,
    String? initialPrompt,
  }) {
    final now = DateTime.now();
    final newId = 'session-${now.millisecondsSinceEpoch}';
    final resolvedPath =
        modelFilePath ?? _modelManager.getLocalModelPath(modelId);
    final session = ChatSession(
      id: newId,
      title: initialPrompt != null && initialPrompt.isNotEmpty
          ? (initialPrompt.length > 28
              ? '${initialPrompt.substring(0, 28)}...'
              : initialPrompt)
          : 'New Chat',
      modelId: modelId,
      modelName: modelName,
      modelFilePath: resolvedPath,
      createdAt: now,
      updatedAt: now,
      messages: [],
    );

    _sessions.insert(0, session);
    unawaited(_saveSession(session));
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

  /// Returns a verified local `.gguf` file path for [session], or null if missing.
  String? resolveModelFilePath(ChatSession session) {
    final indexedPath = _modelManager.getLocalModelPath(session.modelId);
    if (indexedPath != null && File(indexedPath).existsSync()) {
      if (session.modelFilePath != indexedPath) {
        session.modelFilePath = indexedPath;
        unawaited(_saveSession(session));
      }
      return indexedPath;
    }

    final savedPath = session.modelFilePath;
    if (savedPath != null &&
        savedPath.isNotEmpty &&
        File(savedPath).existsSync()) {
      return savedPath;
    }
    return null;
  }

  void updateSessionTitle(String sessionId, String newTitle) {
    final session = getSessionById(sessionId);
    if (session != null) {
      session.title = newTitle;
      session.updatedAt = DateTime.now();
      unawaited(_saveSession(session));
      notifyListeners();
    }
  }

  void updateSessionSettings(
    String sessionId, {
    double? temperature,
    String? systemPrompt,
  }) {
    final session = getSessionById(sessionId);
    if (session == null) return;
    if (temperature != null) {
      session.temperature = temperature;
    }
    if (systemPrompt != null) {
      session.systemPrompt = systemPrompt;
    }
    unawaited(_saveSession(session));
    notifyListeners();
  }

  void clearSessionMessages(String sessionId) {
    final session = getSessionById(sessionId);
    if (session == null) return;
    session.messages.clear();
    session.updatedAt = DateTime.now();
    unawaited(_saveSession(session));
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    if (_storageService.isInitialized) {
      final file = _sessionFile(id);
      if (await file.exists()) {
        await file.delete();
      }
    }
    notifyListeners();
  }

  Future<void> clearAllSessions() async {
    _sessions.clear();
    if (_storageService.isInitialized) {
      final dir = _storageService.chatsDirectory;
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
            await entity.delete();
          }
        }
      }
    }
    notifyListeners();
  }

  Future<void> stopGeneration() async {
    _stopOverride?.call();
    await _inferenceService.stopGeneration();
  }

  Future<void> sendMessage({
    required String sessionId,
    required String prompt,
    void Function(String chunk)? onTokenChunk,
  }) async {
    final session = getSessionById(sessionId);
    if (session == null) return;

    final modelPath = resolveModelFilePath(session);
    if (modelPath == null) {
      throw ModelFileNotFoundException(
        modelId: session.modelId,
        modelName: session.modelName,
        message:
            'Model "${session.modelName}" is not downloaded in MobAI/models. Download it before chatting.',
      );
    }

    final priorHistory = List<ChatMessage>.from(session.messages);

    final userMsg = ChatMessage(
      id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
      text: prompt,
      isUser: true,
      timestamp: DateTime.now(),
    );

    session.messages.add(userMsg);
    session.updatedAt = DateTime.now();
    if (session.messages.length == 1 && session.title == 'New Chat') {
      session.title =
          prompt.length > 26 ? '${prompt.substring(0, 26)}...' : prompt;
    }
    await _saveSession(session);
    notifyListeners();

    final botMsgId = 'bot-${DateTime.now().millisecondsSinceEpoch}';
    final botTimestamp = DateTime.now();
    final botMsg = ChatMessage(
      id: botMsgId,
      text: '',
      isUser: false,
      timestamp: botTimestamp,
    );
    session.messages.add(botMsg);
    notifyListeners();

    final streamBuilder = _inferenceOverride ?? _inferenceService.generateReplyStream;
    final buffer = StringBuffer();

    try {
      await for (final chunk in streamBuilder(
        modelPath: modelPath,
        priorHistory: priorHistory,
        userPrompt: prompt,
        systemPrompt: session.systemPrompt,
        temperature: session.temperature,
      )) {
        buffer.write(chunk);
        final index = session.messages.indexWhere((m) => m.id == botMsgId);
        if (index != -1) {
          session.messages[index] = ChatMessage(
            id: botMsgId,
            text: buffer.toString(),
            isUser: false,
            timestamp: botTimestamp,
          );
        }
        onTokenChunk?.call(chunk);
        notifyListeners();
      }
    } catch (e) {
      if (buffer.isEmpty) {
        session.messages.removeWhere((m) => m.id == botMsgId);
        notifyListeners();
      }
      rethrow;
    } finally {
      if (buffer.isNotEmpty) {
        session.updatedAt = DateTime.now();
      }
      await _saveSession(session);
    }
  }
}
