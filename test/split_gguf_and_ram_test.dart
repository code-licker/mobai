import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/local_inference_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';
import 'package:mobai/utils/format_utils.dart';

typedef _AdapterHandler = Future<ResponseBody> Function(
  RequestOptions options,
  Future<void>? cancelFuture,
);

class _SplitFakeAdapter implements HttpClientAdapter {
  _SplitFakeAdapter(this.handler);

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

Uint8List _buildPart1Bytes(int size) {
  final bytes = Uint8List(size);
  bytes[0] = 0x47; // G
  bytes[1] = 0x47; // G
  bytes[2] = 0x55; // U
  bytes[3] = 0x46; // F
  for (var i = 4; i < size; i++) {
    bytes[i] = i & 0xFF;
  }
  return bytes;
}

Uint8List _buildShardContinuationBytes(int size, int seed) {
  final bytes = Uint8List(size);
  // Deliberately non-GGUF header to ensure shards 2..N do not fail magic check.
  for (var i = 0; i < size; i++) {
    bytes[i] = (i + seed) & 0xFF;
  }
  return bytes;
}

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mobai_split_test_');
    await StorageService().initForTesting(tempRoot);
  });

  tearDown(() async {
    await ModelManagerService().cancelDownload('HazLove/DeepSeek-Split-GGUF');
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('Formatters & Split GGUF Parsing', () {
    test('formats TB sizes and multi-part labels cleanly', () {
      expect(formatSizeMb(1536), '1.5 GB');
      expect(formatSizeMb(1024 * 1024), '1.00 TB');
      expect(formatSizeMb(1300000), '1.24 TB');
      expect(formatSizeWithParts(151962, partCount: 4), '148.4 GB (4 parts)');
      expect(formatSizeWithParts(2048, partCount: 1), '2.0 GB');
      expect(formatBytes(2 * 1024 * 1024 * 1024 * 1024), '2.00 TB');
    });

    test('groups multi-part GGUF shards, sums size, and prefers single-file variants', () {
      final hfJson = {
        'id': 'HazLove/DeepSeek-V4.1-Flash-1017-GGUF',
        'author': 'HazLove',
        'siblings': [
          {
            'rfilename': 'DeepSeek-V4.1-IQ1_M-00003-of-00004.gguf',
            'size': 38000 * 1024 * 1024,
          },
          {
            'rfilename': 'DeepSeek-V4.1-IQ1_M-00001-of-00004.gguf',
            'size': 37000 * 1024 * 1024,
          },
          {
            'rfilename': 'DeepSeek-V4.1-IQ1_M-00004-of-00004.gguf',
            'size': 35000 * 1024 * 1024,
          },
          {
            'rfilename': 'DeepSeek-V4.1-IQ1_M-00002-of-00004.gguf',
            'size': 38000 * 1024 * 1024,
          },
        ],
      };

      final model = OpenModel.fromHuggingFace(hfJson);
      expect(model.variants.length, 1);
      final variant = model.variants.first;
      expect(variant.isSplit, isTrue);
      expect(variant.partCount, 4);
      expect(variant.hasMissingParts, isFalse);
      expect(variant.fileName, 'DeepSeek-V4.1-IQ1_M-00001-of-00004.gguf');
      expect(variant.quantization, 'IQ1_M');
      expect(variant.sizeBytes, 148000 * 1024 * 1024);
      expect(model.downloadSizeMb, 148000);
      expect(model.partCount, 4);
      expect(model.minRamGb, greaterThan(64));
      expect(model.isTooLargeForPhone(deviceRamGb: 16.0), isTrue);

      // When a single-file variant coexists with split variants, single-file sorts first.
      final mixedVariants = OpenModel.parseGgufVariantsFromSiblings(
        'owner/mixed-gguf',
        [
          {'rfilename': 'model-BF16-00001-of-00002.gguf', 'size': 4000 * 1024 * 1024},
          {'rfilename': 'model-BF16-00002-of-00002.gguf', 'size': 4000 * 1024 * 1024},
          {'rfilename': 'model-Q4_K_M.gguf', 'size': 2500 * 1024 * 1024},
        ],
      );
      expect(mixedVariants.length, 2);
      expect(mixedVariants.first.isSplit, isFalse);
      expect(mixedVariants.first.fileName, 'model-Q4_K_M.gguf');
      expect(mixedVariants[1].isSplit, isTrue);
    });

    test('flags missing shards and evaluates phone RAM thresholds accurately', () {
      final incomplete = OpenModel.parseGgufVariantsFromSiblings(
        'owner/broken-split',
        [
          {'rfilename': 'big-Q4_K_M-00001-of-00003.gguf', 'size': 1000 * 1024 * 1024},
          {'rfilename': 'big-Q4_K_M-00003-of-00003.gguf', 'size': 1000 * 1024 * 1024},
        ],
      );
      expect(incomplete.single.hasMissingParts, isTrue);
      expect(incomplete.single.partCount, 3);

      final medium = OpenModel(
        id: 'owner/medium-gguf',
        name: 'Medium',
        publisher: 'Owner',
        parameterSizeB: '7',
        format: 'GGUF',
        quantization: 'Q4_K_M',
        downloadSizeMb: 4500,
        minRamGb: 8,
        downloadUrl: 'https://huggingface.co/owner/medium/resolve/main/m.gguf',
        description: 'Medium',
        repoUrl: 'https://huggingface.co/owner/medium',
      );
      expect(medium.isTooLargeForPhone(deviceRamGb: 6.0), isTrue);
      expect(medium.isTooLargeForPhone(deviceRamGb: 8.0), isFalse);

      final fourteenGbRam = medium.copyWith(minRamGb: 14);
      expect(fourteenGbRam.isTooLargeForPhone(deviceRamGb: 16.0), isTrue);
    });
  });

  group('Sequential Multi-Part Download, Sync, Delete & Inference Checks', () {
    test('downloads parts sequentially, pauses mid-part 2, resumes 206, and deletes all parts', () async {
      const partSize = 600 * 1024;
      final part1Data = _buildPart1Bytes(partSize);
      final part2Data = _buildShardContinuationBytes(partSize, 17);
      final part2FirstChunkSent = Completer<void>();

      final dio = Dio();
      dio.httpClientAdapter = _SplitFakeAdapter((options, cancelFuture) async {
        final url = options.path;
        final rangeHeader = options.headers['Range']?.toString();

        if (url.endsWith('00001-of-00002.gguf')) {
          return ResponseBody(
            Stream<Uint8List>.fromIterable([part1Data]),
            200,
            headers: {
              Headers.contentLengthHeader: ['$partSize'],
            },
          );
        }

        if (rangeHeader == null) {
          final controller = StreamController<Uint8List>();
          var cancelled = false;
          cancelFuture?.whenComplete(() {
            cancelled = true;
            if (!controller.isClosed) controller.close();
          });

          scheduleMicrotask(() async {
            if (cancelled) return;
            controller.add(Uint8List.sublistView(part2Data, 0, 200 * 1024));
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (!part2FirstChunkSent.isCompleted) {
              part2FirstChunkSent.complete();
            }
          });

          return ResponseBody(
            controller.stream,
            200,
            headers: {
              Headers.contentLengthHeader: ['$partSize'],
            },
          );
        }

        final offset = int.parse(
          RegExp(r'^bytes=(\d+)-$').firstMatch(rangeHeader)!.group(1)!,
        );
        final rem = Uint8List.sublistView(part2Data, offset);
        return ResponseBody(
          Stream<Uint8List>.fromIterable([rem]),
          206,
          headers: {
            Headers.contentLengthHeader: ['${rem.length}'],
            'content-range': ['bytes $offset-${partSize - 1}/$partSize'],
          },
        );
      });

      ModelManagerService().configureForTesting(downloadDio: dio);
      final model = OpenModel.fromHuggingFace({
        'id': 'HazLove/DeepSeek-Split-GGUF',
        'author': 'HazLove',
        'siblings': [
          {
            'rfilename': 'DeepSeek-IQ1_M-00001-of-00002.gguf',
            'size': partSize,
          },
          {
            'rfilename': 'DeepSeek-IQ1_M-00002-of-00002.gguf',
            'size': partSize,
          },
        ],
      });

      final firstRun = ModelManagerService().downloadModel(
        model.id,
        model: model,
      );
      await part2FirstChunkSent.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await ModelManagerService().pauseDownload(model.id);

      final pausedResult = await firstRun;
      expect(pausedResult, isNull);
      final state = ModelManagerService().getDownloadState(model.id);
      expect(state?.isPaused, isTrue);
      expect(state?.totalParts, 2);
      expect(state?.currentPartIndex, 1);
      expect(state?.receivedBytes, partSize + 200 * 1024);

      final completed = await ModelManagerService().resumeDownload(
        model.id,
        model: model,
      );
      expect(completed, isNotNull);
      expect(completed!.partCount, 2);
      expect(completed.sizeBytes, partSize * 2);
      expect(completed.fileName, 'DeepSeek-IQ1_M-00001-of-00002.gguf');

      final sep = Platform.pathSeparator;
      final modelsPath = StorageService().modelsPath;
      final f1 = File('$modelsPath${sep}DeepSeek-IQ1_M-00001-of-00002.gguf');
      final f2 = File('$modelsPath${sep}DeepSeek-IQ1_M-00002-of-00002.gguf');
      expect(await f1.exists(), isTrue);
      expect(await f2.exists(), isTrue);
      expect(await f2.readAsBytes(), part2Data);

      await ModelManagerService().deleteDownloadedModel(model.id);
      expect(await f1.exists(), isFalse);
      expect(await f2.exists(), isFalse);
    });

    test('syncWithStorage ignores incomplete manual split files and LocalInferenceService rejects missing shards', () async {
      final sep = Platform.pathSeparator;
      final dir = StorageService().modelsDirectory;
      await dir.create(recursive: true);

      final shard1 = File('${dir.path}${sep}Manual-00001-of-00003.gguf');
      await shard1.writeAsBytes(_buildPart1Bytes(64));
      await ModelManagerService().syncWithStorage();
      expect(ModelManagerService().downloadedModels, isEmpty);

      await expectLater(
        LocalInferenceService().ensureModelLoaded(shard1.path),
        throwsA(isA<llama.LlamaModelException>()),
      );

      final shard2 = File('${dir.path}${sep}Manual-00002-of-00003.gguf');
      await shard2.writeAsBytes(_buildShardContinuationBytes(64, 5));
      await expectLater(
        LocalInferenceService().ensureModelLoaded(shard2.path),
        throwsA(isA<llama.LlamaModelException>()),
      );
    });
  });
}
