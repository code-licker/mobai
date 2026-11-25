import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/hf_url_parser.dart';
import 'package:mobai/services/model_catalog_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';

void main() {
  group('HfUrlParser', () {
    test('parses Hugging Face repo root URL', () {
      final parsed = HfUrlParser.parse(
        'https://huggingface.co/Orenguteng/Llama-3-8B-Lexi-Uncensored-GGUF/',
      );
      expect(parsed.isHuggingFace, isTrue);
      expect(parsed.repoId, 'Orenguteng/Llama-3-8B-Lexi-Uncensored-GGUF');
      expect(parsed.hasDirectFile, isFalse);
    });

    test('normalizes Hugging Face /blob/ URL to /resolve/', () {
      final parsed = HfUrlParser.parse(
        'https://huggingface.co/owner/repo/blob/main/weights/model-Q4_K_M.gguf',
      );
      expect(parsed.isHuggingFace, isTrue);
      expect(parsed.repoId, 'owner/repo');
      expect(parsed.fileName, 'model-Q4_K_M.gguf');
      expect(
        parsed.directDownloadUrl,
        'https://huggingface.co/owner/repo/resolve/main/weights/model-Q4_K_M.gguf',
      );
    });

    test('parses Hugging Face /resolve/ URL with query string', () {
      final parsed = HfUrlParser.parse(
        'https://huggingface.co/owner/repo/resolve/main/uncensored-Q8_0.gguf?download=true',
      );
      expect(parsed.fileName, 'uncensored-Q8_0.gguf');
      expect(
        parsed.directDownloadUrl,
        'https://huggingface.co/owner/repo/resolve/main/uncensored-Q8_0.gguf',
      );
    });

    test('parses hf:// scheme and direct non-HF URLs', () {
      final hfParsed = HfUrlParser.parse('hf://owner/repo/tiny-Q4_K_M.gguf');
      expect(hfParsed.repoId, 'owner/repo');
      expect(
        hfParsed.directDownloadUrl,
        'https://huggingface.co/owner/repo/resolve/main/tiny-Q4_K_M.gguf',
      );

      final directParsed = HfUrlParser.parse(
        'https://example.com/models/custom-Q5_K_M.gguf',
      );
      expect(directParsed.isHuggingFace, isFalse);
      expect(directParsed.fileName, 'custom-Q5_K_M.gguf');
      expect(
        directParsed.directDownloadUrl,
        'https://example.com/models/custom-Q5_K_M.gguf',
      );
    });
  });

  group('Custom URL resolution, persistence & local import', () {
    late Directory tempDir;
    late HttpServer server;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mobai_custom_test_');
      final rootDir = Directory('${tempDir.path}${Platform.pathSeparator}MobAI');
      await StorageService().initForTesting(rootDir);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        if (req.uri.path == '/api/models/owner/uncensored-gguf') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'id': 'owner/uncensored-gguf',
              'author': 'owner',
              'downloads': 500,
              'likes': 42,
              'siblings': [
                {
                  'rfilename': 'lexi-Q4_K_M.gguf',
                  'size': 600 * 1024 * 1024,
                },
                {
                  'rfilename': 'lexi-Q8_0.gguf',
                  'size': 1100 * 1024 * 1024,
                },
              ],
            }),
          );
        } else if (req.uri.path == '/direct/custom-Q4_K_M.gguf') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentLength = 250 * 1024 * 1024;
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });

      final baseUrl = 'http://127.0.0.1:${server.port}';
      ModelManagerService().configureForTesting(
        downloadDio: Dio(),
        catalogService: ModelCatalogService(
          dio: Dio(),
          apiBaseUrl: '$baseUrl/api/models',
        ),
      );
    });

    tearDown(() async {
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolveCustomModelFromUrl fetches HF repo variants and /blob/ selection', () async {
      final baseUrl = 'http://127.0.0.1:${server.port}';
      final catalog = ModelCatalogService(
        dio: Dio(),
        apiBaseUrl: '$baseUrl/api/models',
      );

      final resolved = await catalog.resolveCustomModelFromUrl(
        'https://huggingface.co/owner/uncensored-gguf/blob/main/lexi-Q8_0.gguf',
      );
      expect(resolved.id, 'owner/uncensored-gguf');
      expect(resolved.variants.length, 2);
      expect(resolved.quantization, 'Q8_0');
      expect(resolved.downloadSizeMb, 1100);
      expect(
        resolved.downloadUrl,
        'https://huggingface.co/owner/uncensored-gguf/resolve/main/lexi-Q8_0.gguf',
      );

      final directResolved = await catalog.resolveCustomModelFromUrl(
        '$baseUrl/direct/custom-Q4_K_M.gguf',
      );
      expect(directResolved.downloadSizeMb, 250);
      expect(directResolved.quantization, 'Q4_K_M');
    });

    test('persists custom_models.json across syncWithStorage and removes cleanly', () async {
      final manager = ModelManagerService();
      final custom = OpenModel(
        id: 'owner/uncensored-gguf',
        name: 'Lexi Uncensored',
        publisher: 'owner',
        parameterSizeB: '8.0',
        format: 'GGUF',
        quantization: 'Q4_K_M',
        downloadSizeMb: 4500,
        minRamGb: 8,
        downloadUrl:
            'https://huggingface.co/owner/uncensored-gguf/resolve/main/lexi-Q4_K_M.gguf',
        description: 'Custom HF model',
        repoUrl: 'https://huggingface.co/owner/uncensored-gguf',
      );
      manager.addCustomModel(custom);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final customFile = File(
        '${StorageService().modelsPath}${Platform.pathSeparator}custom_models.json',
      );
      expect(customFile.existsSync(), isTrue);

      // Simulate fresh in-memory state + cold startup sync
      manager.configureForTesting();
      await manager.syncWithStorage();
      expect(manager.myModels.any((m) => m.id == 'owner/uncensored-gguf'), isTrue);

      await manager.removeCustomModel('owner/uncensored-gguf');
      expect(manager.myModels.any((m) => m.id == 'owner/uncensored-gguf'), isFalse);
    });

    test('importLocalGgufFile copies valid GGUF and rejects non-GGUF', () async {
      final manager = ModelManagerService();
      final downloadsDir = await Directory(
        '${tempDir.path}${Platform.pathSeparator}Downloads',
      ).create();

      final badFile = File(
        '${downloadsDir.path}${Platform.pathSeparator}not_a_model.gguf',
      );
      await badFile.writeAsString('<html>oops</html>');
      await expectLater(
        manager.importLocalGgufFile(badFile.path),
        throwsA(isA<FormatException>()),
      );

      final goodFile = File(
        '${downloadsDir.path}${Platform.pathSeparator}uncensored-Q4_K_M.gguf',
      );
      await goodFile.writeAsBytes([0x47, 0x47, 0x55, 0x46, 0x03, 0x00, 0x01]);

      final imported = await manager.importLocalGgufFile(goodFile.path);
      expect(imported.modelId, 'local:uncensored-Q4_K_M.gguf');
      expect(File(imported.filePath).existsSync(), isTrue);
      expect(
        imported.filePath.startsWith(StorageService().modelsPath),
        isTrue,
      );

      // Verify persistence across cold sync
      manager.configureForTesting();
      await manager.syncWithStorage();
      expect(manager.isModelDownloaded('local:uncensored-Q4_K_M.gguf'), isTrue);
      expect(
        manager.myModels.any((m) => m.id == 'local:uncensored-Q4_K_M.gguf'),
        isTrue,
      );
    });
  });
}
