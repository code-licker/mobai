import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/services/model_catalog_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';
import 'package:mobai/utils/format_utils.dart';

void main() {
  group('format_utils', () {
    test('formatSizeMb formats MB and GB consistently', () {
      expect(formatSizeMb(73), '73 MB');
      expect(formatSizeMb(1023), '1023 MB');
      expect(formatSizeMb(2048), '2.0 GB');
      expect(formatSizeMb(19400), '18.9 GB');
    });

    test('formatRelativeReleaseDate formats recent and older dates', () {
      final now = DateTime(2026, 11, 26, 12);
      expect(
        formatRelativeReleaseDate(DateTime(2026, 11, 26, 8), now: now),
        'Today',
      );
      expect(
        formatRelativeReleaseDate(DateTime(2026, 11, 23, 12), now: now),
        '3d ago',
      );
      expect(
        formatRelativeReleaseDate(DateTime(2025, 4, 10), now: now),
        '2025-04',
      );
    });
  });

  group('Catalog pagination, pipeline filter & sorting', () {
    late Directory tempDir;
    late HttpServer server;
    final requestedUrls = <Uri>[];

    setUp(() async {
      requestedUrls.clear();
      tempDir = await Directory.systemTemp.createTemp('mobai_catalog_test_');
      final rootDir = Directory('${tempDir.path}${Platform.pathSeparator}MobAI');
      await StorageService().initForTesting(rootDir);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        requestedUrls.add(req.requestedUri);
        final cursor = req.uri.queryParameters['cursor'];
        final sort = req.uri.queryParameters['sort'];
        final baseUrl = 'http://127.0.0.1:${server.port}/api/models';

        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.json;

        if (cursor == 'page2') {
          req.response.write(
            jsonEncode([
              {
                'id': 'owner/model-3b',
                'author': 'owner',
                'createdAt': '2026-11-10T00:00:00Z',
                'downloads': 100,
                'likes': 5,
                'siblings': [
                  {'rfilename': 'model-3b-Q4_K_M.gguf', 'size': 1800 * 1024 * 1024},
                ],
              },
            ]),
          );
        } else if (sort == 'createdAt') {
          req.response.write(
            jsonEncode([
              {
                'id': 'owner/newest-1b',
                'author': 'owner',
                'createdAt': '2026-11-26T00:00:00Z',
                'downloads': 10,
                'likes': 2,
                'siblings': [
                  {'rfilename': 'newest-1b-Q4_K_M.gguf', 'size': 700 * 1024 * 1024},
                ],
              },
            ]),
          );
        } else {
          req.response.headers.set(
            'link',
            '<$baseUrl?cursor=page2&pipeline_tag=text-generation>; rel="next"',
          );
          req.response.write(
            jsonEncode([
              {
                'id': 'owner/big-7b',
                'author': 'owner',
                'createdAt': '2026-10-01T00:00:00Z',
                'downloads': 5000,
                'likes': 100,
                'siblings': [
                  {'rfilename': 'big-7b-Q4_K_M.gguf', 'size': 4200 * 1024 * 1024},
                ],
              },
              {
                'id': 'owner/tiny-0.5b',
                'author': 'owner',
                'createdAt': '2026-09-01T00:00:00Z',
                'downloads': 9000,
                'likes': 200,
                'siblings': [
                  {'rfilename': 'tiny-0.5b-Q4_K_M.gguf', 'size': 380 * 1024 * 1024},
                ],
              },
            ]),
          );
        }
        await req.response.close();
      });

      final baseUrl = 'http://127.0.0.1:${server.port}/api/models';
      ModelManagerService().configureForTesting(
        downloadDio: Dio(),
        catalogService: ModelCatalogService(
          dio: Dio(),
          apiBaseUrl: baseUrl,
        ),
      );
    });

    tearDown(() async {
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fetches text-generation models, paginates via Link cursor, and sorts', () async {
      final manager = ModelManagerService();
      await manager.loadModels();

      expect(requestedUrls.first.queryParameters['pipeline_tag'], 'text-generation');
      expect(requestedUrls.first.queryParameters['sort'], 'downloads');
      expect(manager.models.length, 2);
      expect(manager.hasMoreModels, isTrue);

      await manager.loadMoreModels();
      expect(manager.models.length, 3);
      expect(manager.hasMoreModels, isFalse);

      // Client-side size sort
      await manager.setSortOption(ModelSortOption.sizeAsc);
      expect(manager.filteredModels.first.id, 'owner/tiny-0.5b');
      expect(manager.filteredModels.last.id, 'owner/big-7b');

      // Client-side parameter sort
      await manager.setSortOption(ModelSortOption.paramsDesc);
      expect(manager.filteredModels.first.id, 'owner/big-7b');
      expect(manager.filteredModels.last.id, 'owner/tiny-0.5b');

      // Server-side latest sort re-fetches with sort=createdAt
      await manager.setSortOption(ModelSortOption.latest);
      expect(requestedUrls.last.queryParameters['sort'], 'createdAt');
      expect(manager.filteredModels.first.id, 'owner/newest-1b');
    });
  });
}
