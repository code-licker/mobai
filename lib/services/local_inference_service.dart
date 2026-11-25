import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:mobai/models/chat_session.dart';

/// Manages on-device GGUF inference via `llamadart`.
/// Keeps at most one model loaded in memory at a time to prevent mobile OOM.
class LocalInferenceService extends ChangeNotifier {
  static final LocalInferenceService _instance =
      LocalInferenceService._internal();
  factory LocalInferenceService() => _instance;
  LocalInferenceService._internal();

  llama.LlamaEngine? _engine;
  String? _loadedModelPath;
  bool _isModelLoading = false;
  bool _isGenerating = false;
  bool _stopRequested = false;

  String? get loadedModelPath => _loadedModelPath;
  bool get isModelLoading => _isModelLoading;
  bool get isGenerating => _isGenerating;

  /// Loads [modelPath] into memory, unloading any previously loaded model first.
  Future<void> ensureModelLoaded(String modelPath) async {
    final file = File(modelPath);
    if (!await file.exists()) {
      throw FileSystemException(
        'Downloaded model file not found at $modelPath',
        modelPath,
      );
    }

    if (_engine != null &&
        _loadedModelPath == modelPath &&
        _engine!.isReady &&
        !_engine!.isDisposed) {
      return;
    }

    await unloadModel();

    _isModelLoading = true;
    notifyListeners();

    try {
      final engine = await llama.LlamaEngine.load(
        llama.LlamaModel(llama.ModelSource.path(modelPath)),
        params: const llama.ModelParams(
          contextSize: 2048,
        ),
      );
      _engine = engine;
      _loadedModelPath = modelPath;
    } finally {
      _isModelLoading = false;
      notifyListeners();
    }
  }

  /// Streams assistant reply tokens from the local GGUF model at [modelPath].
  Stream<String> generateReplyStream({
    required String modelPath,
    required List<ChatMessage> priorHistory,
    required String userPrompt,
    required String systemPrompt,
    required double temperature,
  }) async* {
    _stopRequested = false;
    await ensureModelLoaded(modelPath);

    final engine = _engine;
    if (engine == null || !engine.isReady || engine.isDisposed) {
      throw StateError('Local inference engine is not ready.');
    }

    final session = llama.ChatSession(
      engine,
      systemPrompt: systemPrompt.trim().isEmpty
          ? ChatSession.defaultSystemPrompt
          : systemPrompt.trim(),
    );

    for (final msg in priorHistory) {
      if (msg.text.trim().isEmpty) continue;
      session.addMessage(
        llama.LlamaChatMessage.fromText(
          role: msg.isUser
              ? llama.LlamaChatRole.user
              : llama.LlamaChatRole.assistant,
          text: msg.text,
        ),
      );
    }

    _isGenerating = true;
    notifyListeners();

    try {
      final stream = session.create(
        [llama.LlamaTextContent(userPrompt)],
        params: llama.GenerationParams(
          temp: temperature,
          maxTokens: 1024,
        ),
      );

      await for (final chunk in stream) {
        if (_stopRequested) break;
        final text = chunk.text;
        if (text.isNotEmpty) {
          yield text;
        }
      }
    } on llama.LlamaStateException catch (e) {
      // Cancellation before first token throws LlamaStateException in llamadart.
      if (!_stopRequested) {
        rethrow;
      }
      debugPrint('Generation cancelled: $e');
    } finally {
      _isGenerating = false;
      _stopRequested = false;
      notifyListeners();
    }
  }

  /// Cooperatively stops any in-flight generation.
  Future<void> stopGeneration() async {
    _stopRequested = true;
    _engine?.cancelGeneration();
  }

  /// Unloads the active model and releases native memory.
  Future<void> unloadModel() async {
    final existing = _engine;
    _engine = null;
    _loadedModelPath = null;
    _isGenerating = false;
    _stopRequested = false;
    if (existing != null) {
      try {
        await existing.dispose();
      } catch (e) {
        debugPrint('Error disposing LlamaEngine: $e');
      }
    }
    notifyListeners();
  }
}
