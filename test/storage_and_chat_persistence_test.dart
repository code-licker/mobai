import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/models/chat_session.dart';
import 'package:mobai/services/chat_session_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mobai_storage_test_');
    final rootDir = Directory('${tempDir.path}${Platform.pathSeparator}MobAI');
    await StorageService().initForTesting(rootDir);
    ModelManagerService().configureForTesting();
    ChatSessionService().configureForTesting();
  });

  tearDown(() async {
    await ChatSessionService().flushPendingSaves();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('normalizeMobaiRoot avoids MobAI/MobAI duplication', () {
    final sep = Platform.pathSeparator;
    expect(StorageService.normalizeMobaiRoot('/tmp/docs'), '/tmp/docs${sep}MobAI');
    expect(StorageService.normalizeMobaiRoot('/tmp/docs/'), '/tmp/docs${sep}MobAI');
    expect(StorageService.normalizeMobaiRoot('/tmp/docs/MobAI'), '/tmp/docs/MobAI');
    expect(StorageService.normalizeMobaiRoot('/tmp/docs/mobai/'), '/tmp/docs/mobai');
  });

  test('StorageService creates MobAI/models and MobAI/chats', () {
    final storage = StorageService();
    expect(storage.modelsDirectory.existsSync(), isTrue);
    expect(storage.chatsDirectory.existsSync(), isTrue);
  });

  test('ChatSessionService persists and reloads sessions in MobAI/chats', () async {
    final storage = StorageService();
    final chatService = ChatSessionService();
    final modelFile = File(
      '${storage.modelsPath}${Platform.pathSeparator}demo.gguf',
    );
    await modelFile.writeAsBytes([0x47, 0x47, 0x55, 0x46, 0x03, 0x00]);

    chatService.configureForTesting(
      inferenceOverride: ({
        required String modelPath,
        required List<ChatMessage> priorHistory,
        required String userPrompt,
        required String systemPrompt,
        required double temperature,
      }) async* {
        expect(modelPath, modelFile.path);
        expect(temperature, 0.4);
        expect(systemPrompt, 'Be brief.');
        yield 'Hello ';
        yield 'world!';
      },
    );

    final session = chatService.createSession(
      modelId: 'demo/model',
      modelName: 'Demo Model',
      modelFilePath: modelFile.path,
    );
    chatService.updateSessionSettings(
      session.id,
      temperature: 0.4,
      systemPrompt: 'Be brief.',
    );

    await chatService.sendMessage(sessionId: session.id, prompt: 'Hi');

    // Verify JSON file exists in MobAI/chats
    final chatFile = File(
      '${storage.chatsPath}${Platform.pathSeparator}${session.id}.json',
    );
    expect(chatFile.existsSync(), isTrue);

    // Reload from disk into a clean in-memory list
    await chatService.loadSessionsFromStorage();
    final reloaded = chatService.getSessionById(session.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.messages.length, 2);
    expect(reloaded.messages.first.text, 'Hi');
    expect(reloaded.messages.last.text, 'Hello world!');
    expect(reloaded.temperature, 0.4);
    expect(reloaded.systemPrompt, 'Be brief.');
  });

  test('sendMessage throws ModelFileNotFoundException when .gguf is missing', () async {
    final chatService = ChatSessionService();
    final session = chatService.createSession(
      modelId: 'missing/model',
      modelName: 'Missing Model',
    );
    await chatService.flushPendingSaves();

    await expectLater(
      chatService.sendMessage(sessionId: session.id, prompt: 'Test'),
      throwsA(isA<ModelFileNotFoundException>()),
    );
  });

  test('setCustomFolder with migrateExisting moves models and chats', () async {
    final storage = StorageService();
    final chatService = ChatSessionService();

    final oldModel = File(
      '${storage.modelsPath}${Platform.pathSeparator}tiny.gguf',
    );
    await oldModel.writeAsBytes([0x47, 0x47, 0x55, 0x46, 0x01]);

    final session = chatService.createSession(
      modelId: 'local:tiny.gguf',
      modelName: 'Tiny',
      modelFilePath: oldModel.path,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final newParent = await Directory(
      '${tempDir.path}${Platform.pathSeparator}custom_parent',
    ).create();
    final result = await storage.setCustomFolder(
      newParent.path,
      migrateExisting: true,
    );
    expect(result.success, isTrue);

    final migratedModel = File(
      '${storage.modelsPath}${Platform.pathSeparator}tiny.gguf',
    );
    expect(migratedModel.existsSync(), isTrue);
    expect(oldModel.existsSync(), isFalse);

    await chatService.loadSessionsFromStorage();
    final reloaded = chatService.getSessionById(session.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.modelFilePath, migratedModel.path);
  });
}
