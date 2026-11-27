import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';

void main() {
  late Directory tempDir;
  late HttpServer server;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mobai_download_test_');
    final rootDir = Directory('${tempDir.path}${Platform.pathSeparator}MobAI');
    await StorageService().initForTesting(rootDir);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      final path = request.uri.path;
      if (path == '/valid.gguf') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.binary;
        final bytes = <int>[0x47, 0x47, 0x55, 0x46, ...List.filled(64, 1)];
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
      } else if (path == '/html-page') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html><body>Login required</body></html>');
      } else if (path == '/gated') {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.write('Forbidden');
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    ModelManagerService().configureForTesting(
      downloadDio: Dio(BaseOptions(followRedirects: true)),
    );
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('downloads real GGUF file into MobAI/models and deletes cleanly', () async {
    final manager = ModelManagerService();
    final baseUrl = 'http://127.0.0.1:${server.port}';
    final model = OpenModel(
      id: 'test/tiny-gguf',
      name: 'Tiny GGUF',
      publisher: 'Test',
      parameterSizeB: '0.1',
      format: 'GGUF',
      quantization: 'Q4_K_M',
      downloadSizeMb: 1,
      minRamGb: 2,
      downloadUrl: '$baseUrl/valid.gguf',
      description: 'Test model',
      repoUrl: baseUrl,
    );
    manager.addCustomModel(model);

    final downloaded = await manager.downloadModel(model.id);
    expect(downloaded, isNotNull);
    expect(manager.isModelDownloaded(model.id), isTrue);

    final localPath = manager.getLocalModelPath(model.id);
    expect(localPath, isNotNull);
    expect(File(localPath!).existsSync(), isTrue);
    expect(localPath.startsWith(StorageService().modelsPath), isTrue);

    await manager.deleteDownloadedModel(model.id);
    expect(manager.isModelDownloaded(model.id), isFalse);
    expect(File(localPath).existsSync(), isFalse);
  });

  test('rejects HTML response and cleans up .part file', () async {
    final manager = ModelManagerService();
    final baseUrl = 'http://127.0.0.1:${server.port}';
    final model = OpenModel(
      id: 'test/html-gguf',
      name: 'HTML Response',
      publisher: 'Test',
      parameterSizeB: '0.1',
      format: 'GGUF',
      quantization: 'Q4_K_M',
      downloadSizeMb: 1,
      minRamGb: 2,
      downloadUrl: '$baseUrl/html-page',
      description: 'Bad response',
      repoUrl: baseUrl,
    );
    manager.addCustomModel(model);

    final downloaded = await manager.downloadModel(model.id);
    expect(downloaded, isNull);
    expect(manager.isModelDownloaded(model.id), isFalse);
    expect(manager.getDownloadError(model.id), isNotNull);
    expect(StorageService().modelsDirectory.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
  });

  test('surfaces friendly error on 403 gated Hugging Face response', () async {
    final manager = ModelManagerService();
    final baseUrl = 'http://127.0.0.1:${server.port}';
    final model = OpenModel(
      id: 'test/gated',
      name: 'Gated Model',
      publisher: 'Meta',
      parameterSizeB: '1.0',
      format: 'GGUF',
      quantization: 'Q4_K_M',
      downloadSizeMb: 1,
      minRamGb: 2,
      downloadUrl: '$baseUrl/gated',
      description: 'Gated',
      repoUrl: baseUrl,
    );
    manager.addCustomModel(model);

    final downloaded = await manager.downloadModel(model.id);
    expect(downloaded, isNull);
    expect(manager.getDownloadError(model.id), contains('403'));
  });

  test('syncWithStorage auto-detects unmanaged .gguf files in MobAI/models', () async {
    final manualFile = File(
      '${StorageService().modelsPath}${Platform.pathSeparator}custom-q4_k_m.gguf',
    );
    await manualFile.writeAsBytes([0x47, 0x47, 0x55, 0x46, 0x01, 0x02]);

    final manager = ModelManagerService();
    await manager.syncWithStorage();

    expect(manager.isModelDownloaded('local:custom-q4_k_m.gguf'), isTrue);
    expect(
      manager.getLocalModelPath('local:custom-q4_k_m.gguf'),
      manualFile.path,
    );
  });
}
