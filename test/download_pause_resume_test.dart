import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';

typedef _AdapterHandler = Future<ResponseBody> Function(
  RequestOptions options,
  Future<void>? cancelFuture,
);

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final _AdapterHandler handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _buildFakeGgufPayload(int totalBytes) {
  final bytes = Uint8List(totalBytes);
  // Valid GGUF magic header ('GGUF') followed by deterministic pattern.
  bytes[0] = 0x47;
  bytes[1] = 0x47;
  bytes[2] = 0x55;
  bytes[3] = 0x46;
  for (var i = 4; i < totalBytes; i++) {
    bytes[i] = i & 0xFF;
  }
  return bytes;
}

OpenModel _makeHfModel({
  String id = 'owner/test-gguf',
  String fileName = 'test-q4.gguf',
  int sizeBytes = 4096,
}) {
  return OpenModel.fromHuggingFace({
    'id': id,
    'author': 'owner',
    'siblings': [
      {'rfilename': fileName, 'size': sizeBytes},
    ],
  });
}

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mobai_dl_test_');
    await StorageService().initForTesting(tempRoot);
  });

  tearDown(() async {
    await ModelManagerService().cancelDownload('owner/test-gguf');
    await ModelManagerService().cancelDownload('owner/gated-gguf');
    await ModelManagerService().cancelDownload('owner/throttle-gguf');
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('ModelManagerService pause, resume, auth & throttling', () {
    test('pauses mid-download, persists state across sync, and resumes via HTTP Range 206', () async {
      const totalSize = 1500 * 1024; // 1.5 MB (> 1 MB buffer threshold)
      final payload = _buildFakeGgufPayload(totalSize);
      final recordedRequests = <RequestOptions>[];
      final firstChunkSent = Completer<void>();

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, cancelFuture) async {
        recordedRequests.add(options);
        final rangeHeader = options.headers['Range']?.toString();

        if (rangeHeader == null) {
          final controller = StreamController<Uint8List>();
          var cancelled = false;
          cancelFuture?.whenComplete(() {
            cancelled = true;
            if (!controller.isClosed) {
              controller.close();
            }
          });

          // Emit 1.1 MB (> 1 MB buffer) so it flushes to .part on pause.
          scheduleMicrotask(() async {
            if (cancelled) return;
            controller.add(Uint8List.sublistView(payload, 0, 600 * 1024));
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (cancelled) return;
            controller.add(Uint8List.sublistView(payload, 600 * 1024, 1100 * 1024));
            if (!firstChunkSent.isCompleted) {
              firstChunkSent.complete();
            }
          });

          return ResponseBody(
            controller.stream,
            200,
            headers: {
              Headers.contentLengthHeader: ['$totalSize'],
            },
          );
        }

        // Expect Range: bytes=<offset>-
        final match = RegExp(r'^bytes=(\d+)-$').firstMatch(rangeHeader);
        expect(match, isNotNull);
        final offset = int.parse(match!.group(1)!);
        expect(offset, greaterThan(0));
        expect(offset, lessThan(totalSize));

        final remaining = Uint8List.sublistView(payload, offset);
        return ResponseBody(
          Stream<Uint8List>.fromIterable([remaining]),
          206,
          headers: {
            Headers.contentLengthHeader: ['${remaining.length}'],
            'content-range': ['bytes $offset-${totalSize - 1}/$totalSize'],
          },
        );
      });

      ModelManagerService().configureForTesting(downloadDio: dio);
      final model = _makeHfModel(sizeBytes: totalSize);

      // Start download; pause once initial 1.1 MB chunks are delivered.
      final downloadFuture = ModelManagerService().downloadModel(
        model.id,
        model: model,
      );
      await firstChunkSent.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await ModelManagerService().pauseDownload(model.id);

      final pausedResult = await downloadFuture;
      expect(pausedResult, isNull);
      expect(ModelManagerService().isModelPaused(model.id), isTrue);
      expect(ModelManagerService().isModelDownloading(model.id), isFalse);

      final modelsDir = StorageService().modelsDirectory;
      final sep = Platform.pathSeparator;
      final partFile = File('${modelsDir.path}${sep}test-q4.gguf.part');
      final stateFile = File('${modelsDir.path}${sep}downloads_state.json');
      expect(await partFile.exists(), isTrue);
      expect(await partFile.length(), 1100 * 1024);
      expect(await stateFile.exists(), isTrue);

      final persisted = jsonDecode(await stateFile.readAsString()) as List<dynamic>;
      expect(
        persisted.any(
          (entry) =>
              entry is Map &&
              entry['modelId'] == model.id &&
              entry['isPaused'] == true,
        ),
        isTrue,
      );

      // Re-sync from disk to simulate app restart restoring paused state.
      await ModelManagerService().syncWithStorage();
      expect(ModelManagerService().isModelPaused(model.id), isTrue);
      final restoredState = ModelManagerService().getDownloadState(model.id);
      expect(restoredState?.receivedBytes, 1100 * 1024);

      // Resume download and expect HTTP 206 completion.
      final completed = await ModelManagerService().resumeDownload(
        model.id,
        model: model,
      );
      expect(completed, isNotNull);
      expect(completed!.fileName, 'test-q4.gguf');
      expect(await partFile.exists(), isFalse);
      final finalFile = File('${modelsDir.path}/test-q4.gguf');
      expect(await finalFile.exists(), isTrue);
      expect(await finalFile.readAsBytes(), payload);
      expect(recordedRequests.length, 2);
      expect(recordedRequests[1].headers['Range'], 'bytes=${1100 * 1024}-');
    });

    test('falls back to restarting from byte 0 when resume server ignores Range and returns 200', () async {
      const totalSize = 64 * 1024;
      final payload = _buildFakeGgufPayload(totalSize);
      final dio = Dio();
      var callCount = 0;

      dio.httpClientAdapter = _FakeHttpClientAdapter((options, cancelFuture) async {
        callCount++;
        return ResponseBody(
          Stream<Uint8List>.fromIterable([payload]),
          200,
          headers: {
            Headers.contentLengthHeader: ['$totalSize'],
          },
        );
      });

      ModelManagerService().configureForTesting(downloadDio: dio);
      final model = _makeHfModel(sizeBytes: totalSize);

      // Seed a stale .part and downloads_state.json as if paused earlier.
      final modelsDir = StorageService().modelsDirectory;
      final sep = Platform.pathSeparator;
      await modelsDir.create(recursive: true);
      final partFile = File('${modelsDir.path}${sep}test-q4.gguf.part');
      await partFile.writeAsBytes(Uint8List.fromList([0x00, 0x01, 0x02, 0x03]));
      final stateFile = File('${modelsDir.path}${sep}downloads_state.json');
      await stateFile.writeAsString(jsonEncode([
        {
          'modelId': model.id,
          'fileName': 'test-q4.gguf',
          'sourceUrl': 'https://huggingface.co/owner/test-gguf/resolve/main/test-q4.gguf',
          'receivedBytes': 4,
          'totalBytes': totalSize,
          'isPaused': true,
          'quantization': 'Q4_K_M',
        },
      ]));

      await ModelManagerService().syncWithStorage();
      expect(ModelManagerService().isModelPaused(model.id), isTrue);

      final result = await ModelManagerService().resumeDownload(model.id, model: model);
      expect(callCount, 1);
      expect(result, isNotNull);
      final finalFile = File('${modelsDir.path}/test-q4.gguf');
      expect(await finalFile.readAsBytes(), payload);
    });

    test('attaches Authorization Bearer token only for Hugging Face hosts and flags 401 as gated error', () async {
      await StorageService().setHfToken('hf_test123');
      expect(StorageService.isHuggingFaceHost('https://huggingface.co/google/gemma-2b/resolve/main/a.gguf'), isTrue);
      expect(StorageService.isHuggingFaceHost('https://cdn-lfs.hf.co/repos/a.gguf'), isTrue);
      expect(StorageService.isHuggingFaceHost('https://example.com/a.gguf'), isFalse);

      String? capturedAuthHeader;
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, cancelFuture) async {
        capturedAuthHeader = options.headers['Authorization']?.toString();
        return ResponseBody.fromString('Unauthorized', 401);
      });

      ModelManagerService().configureForTesting(downloadDio: dio);
      final gatedModel = _makeHfModel(id: 'owner/gated-gguf', fileName: 'gated.gguf');

      final result = await ModelManagerService().downloadModel(
        gatedModel.id,
        model: gatedModel,
      );
      expect(result, isNull);
      expect(capturedAuthHeader, 'Bearer hf_test123');

      final dlState = ModelManagerService().getDownloadState(gatedModel.id);
      expect(dlState, isNotNull);
      expect(dlState!.isGatedError, isTrue);
      expect(dlState.errorMessage, contains('HTTP 401'));
    });

    test('throttles listener notifications (~1s) during fast multi-chunk transfers', () async {
      const chunkCount = 30;
      const chunkSize = 8 * 1024;
      const totalSize = chunkCount * chunkSize;
      final payload = _buildFakeGgufPayload(totalSize);

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, cancelFuture) async {
        final chunks = <Uint8List>[];
        for (var i = 0; i < chunkCount; i++) {
          chunks.add(Uint8List.sublistView(payload, i * chunkSize, (i + 1) * chunkSize));
        }
        return ResponseBody(
          Stream<Uint8List>.fromIterable(chunks),
          200,
          headers: {
            Headers.contentLengthHeader: ['$totalSize'],
          },
        );
      });

      ModelManagerService().configureForTesting(downloadDio: dio);
      final model = _makeHfModel(id: 'owner/throttle-gguf', fileName: 'throttle.gguf', sizeBytes: totalSize);

      var notifyCount = 0;
      void listener() {
        notifyCount++;
      }

      ModelManagerService().addListener(listener);
      try {
        final completed = await ModelManagerService().downloadModel(model.id, model: model);
        expect(completed, isNotNull);
        // Should only fire on initial state, throttled ticks (none within <1s),
        // finalizing transition, and completion — far below 30 chunk events.
        expect(notifyCount, lessThanOrEqualTo(6));
      } finally {
        ModelManagerService().removeListener(listener);
      }
    });
  });
}
