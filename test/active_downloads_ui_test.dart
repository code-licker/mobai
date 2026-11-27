import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobai/models/model_filter_criteria.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/screens/home_screen.dart';
import 'package:mobai/screens/widgets/active_downloads_sheet.dart';
import 'package:mobai/services/download_notification_service.dart';
import 'package:mobai/services/model_catalog_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';

typedef _AdapterHandler =
    Future<ResponseBody> Function(
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
  required String id,
  required String name,
  required String fileName,
  String publisher = 'owner',
  String quantization = 'Q4_K_M',
  int sizeBytes = 4096,
}) {
  return OpenModel(
    id: id,
    name: name,
    publisher: publisher,
    parameterSizeB: '1.0',
    format: 'GGUF',
    quantization: quantization,
    downloadSizeMb: (sizeBytes / (1024 * 1024)).ceil().clamp(1, 100000),
    minRamGb: 4,
    downloadUrl: 'https://huggingface.co/$id/resolve/main/$fileName',
    description: 'Test model $name',
    repoUrl: 'https://huggingface.co/$id',
    variants: [
      GgufVariant(
        fileName: fileName,
        quantization: quantization,
        sizeBytes: sizeBytes,
        downloadUrl: 'https://huggingface.co/$id/resolve/main/$fileName',
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(
    'com.bokachoda.mobai/download_notifications',
  );
  const eventChannelName = 'com.bokachoda.mobai/download_notification_events';

  late Directory tempRoot;
  final recordedMethodCalls = <MethodCall>[];
  dynamic pendingActionToReturn;

  void installNotificationChannelMocks() {
    recordedMethodCalls.clear();
    pendingActionToReturn = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
          recordedMethodCalls.add(call);
          if (call.method == 'consumePendingAction') {
            final action = pendingActionToReturn;
            pendingActionToReturn = null;
            return action;
          }
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(eventChannelName), (
          MethodCall call,
        ) async {
          return null;
        });
  }

  void clearNotificationChannelMocks() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(eventChannelName), null);
  }

  Future<void> emitNativeEvent(Map<String, dynamic> event) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          eventChannelName,
          const StandardMethodCodec().encodeSuccessEnvelope(event),
          (_) {},
        );
  }

  setUp(() async {
    installNotificationChannelMocks();
    tempRoot = await Directory.systemTemp.createTemp('mobai_active_dl_test_');
    await StorageService().initForTesting(tempRoot);
    ModelManagerService().configureForTesting();
  });

  tearDown(() async {
    final ids = ModelManagerService().activeAndPausedDownloads
        .map((s) => s.modelId)
        .toList();
    for (final id in ids) {
      await ModelManagerService().cancelDownload(id);
    }
    ModelManagerService().configureForTesting();
    clearNotificationChannelMocks();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('ModelManagerService filter/search/sort & force-close persistence', () {
    test(
      'active and paused downloads continue unaffected through searchModels, updateFilterCriteria, clearFilters, and updateSortOption',
      () async {
        const totalSize = 64 * 1024;
        final payloadA = _buildFakeGgufPayload(totalSize);
        final payloadB = _buildFakeGgufPayload(totalSize);

        final controllerA = StreamController<Uint8List>();
        final streamAOpened = Completer<void>();
        final firstChunkBDelivered = Completer<void>();

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((HttpRequest req) async {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode([
              {
                'id': 'owner/catalog-item',
                'author': 'owner',
                'createdAt': '2026-11-26T00:00:00Z',
                'downloads': 50,
                'likes': 1,
                'siblings': [
                  {
                    'rfilename': 'catalog-item-Q4_K_M.gguf',
                    'size': 500 * 1024 * 1024,
                  },
                ],
              },
            ]),
          );
          await req.response.close();
        });

        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((
          options,
          cancelFuture,
        ) async {
          if (options.uri.path.contains('model-a.gguf')) {
            cancelFuture?.whenComplete(() {
              if (!controllerA.isClosed) {
                controllerA.close();
              }
            });
            controllerA.add(Uint8List.sublistView(payloadA, 0, 16 * 1024));
            if (!streamAOpened.isCompleted) {
              streamAOpened.complete();
            }
            return ResponseBody(
              controllerA.stream,
              200,
              headers: {
                Headers.contentLengthHeader: ['$totalSize'],
              },
            );
          }

          // Model B: send half, wait until cancelled for pause.
          final controllerB = StreamController<Uint8List>();
          cancelFuture?.whenComplete(() {
            if (!controllerB.isClosed) {
              controllerB.close();
            }
          });
          scheduleMicrotask(() {
            controllerB.add(Uint8List.sublistView(payloadB, 0, 24 * 1024));
            if (!firstChunkBDelivered.isCompleted) {
              firstChunkBDelivered.complete();
            }
          });
          return ResponseBody(
            controllerB.stream,
            200,
            headers: {
              Headers.contentLengthHeader: ['$totalSize'],
            },
          );
        });

        final manager = ModelManagerService();
        manager.configureForTesting(
          downloadDio: dio,
          catalogService: ModelCatalogService(
            dio: Dio(),
            apiBaseUrl: 'http://127.0.0.1:${server.port}/api/models',
          ),
        );

        final modelA = _makeHfModel(
          id: 'owner/model-a',
          name: 'Alpha Active 1B',
          fileName: 'model-a.gguf',
          sizeBytes: totalSize,
        );
        final modelB = _makeHfModel(
          id: 'owner/model-b',
          name: 'Beta Paused 2B',
          fileName: 'model-b.gguf',
          sizeBytes: totalSize,
        );

        try {
          final downloadAFuture = manager.downloadModel(
            modelA.id,
            model: modelA,
          );
          final downloadBFuture = manager.downloadModel(
            modelB.id,
            model: modelB,
          );
          await streamAOpened.future;
          await firstChunkBDelivered.future;
          await Future<void>.delayed(const Duration(milliseconds: 20));

          await manager.pauseDownload(modelB.id);
          await downloadBFuture;

          expect(manager.isModelDownloading(modelA.id), isTrue);
          expect(manager.isModelPaused(modelB.id), isTrue);
          expect(manager.activeDownloadCount, 1);
          expect(manager.pausedDownloadCount, 1);

          // Mutate search, filters, and sort options while downloads run/pause.
          await manager.searchModels('unrelated-query');
          manager.updateFilterCriteria(
            ModelFilterCriteria(
              hideNotRecommended: true,
              selectedProviders: {'NonExistentProvider'},
            ),
          );
          await manager.updateSortOption(ModelSortOption.sizeDesc);
          await manager.updateSortOption(ModelSortOption.latest);
          manager.clearFilters();

          expect(manager.isModelDownloading(modelA.id), isTrue);
          expect(manager.isModelPaused(modelB.id), isTrue);
          expect(
            manager.activeAndPausedDownloads.map((s) => s.modelId),
            containsAll(<String>[modelA.id, modelB.id]),
          );

          // Finish Model A cleanly after catalog mutations.
          controllerA.add(Uint8List.sublistView(payloadA, 16 * 1024));
          await controllerA.close();
          final completedA = await downloadAFuture;
          expect(completedA, isNotNull);
          expect(manager.isModelDownloaded(modelA.id), isTrue);
          expect(manager.isModelPaused(modelB.id), isTrue);
        } finally {
          await server.close(force: true);
        }
      },
    );

    test(
      'pauseAllActiveDownloads flushes .part and downloads_state.json cleanly for force-close resume',
      () async {
        const totalSize = 128 * 1024;
        final payload = _buildFakeGgufPayload(totalSize);
        const partialLen = 40 * 1024;
        final chunkDelivered = Completer<void>();

        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((
          options,
          cancelFuture,
        ) async {
          final rangeHeader = options.headers['Range']?.toString();
          if (rangeHeader == null) {
            final controller = StreamController<Uint8List>();
            cancelFuture?.whenComplete(() {
              if (!controller.isClosed) {
                controller.close();
              }
            });
            scheduleMicrotask(() {
              controller.add(Uint8List.sublistView(payload, 0, partialLen));
              if (!chunkDelivered.isCompleted) {
                chunkDelivered.complete();
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

          expect(rangeHeader, 'bytes=$partialLen-');
          final remaining = Uint8List.sublistView(payload, partialLen);
          return ResponseBody(
            Stream<Uint8List>.fromIterable([remaining]),
            206,
            headers: {
              Headers.contentLengthHeader: ['${remaining.length}'],
              'content-range': ['bytes $partialLen-${totalSize - 1}/$totalSize'],
            },
          );
        });

        final manager = ModelManagerService();
        manager.configureForTesting(downloadDio: dio);

        final model = _makeHfModel(
          id: 'owner/force-close-model',
          name: 'Force Close Model',
          fileName: 'force-close.gguf',
          sizeBytes: totalSize,
        );

        final downloadFuture = manager.downloadModel(model.id, model: model);
        await chunkDelivered.future;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await manager.pauseAllActiveDownloads();
        await downloadFuture;

        expect(manager.hasActiveDownloads, isFalse);
        expect(manager.isModelPaused(model.id), isTrue);
        expect(manager.pausedDownloadCount, 1);

        final modelsDir = StorageService().modelsDirectory;
        final sep = Platform.pathSeparator;
        final partFile = File('${modelsDir.path}${sep}force-close.gguf.part');
        final stateFile = File('${modelsDir.path}${sep}downloads_state.json');

        expect(await partFile.exists(), isTrue);
        expect(await partFile.length(), partialLen);
        expect(await stateFile.exists(), isTrue);

        final saved = jsonDecode(await stateFile.readAsString()) as List<dynamic>;
        expect(saved.length, 1);
        final entry = saved.first as Map<String, dynamic>;
        expect(entry['modelId'], model.id);
        expect(entry['modelName'], 'Force Close Model');
        expect(entry['fileName'], 'force-close.gguf');
        expect(entry['receivedBytes'], partialLen);
        expect(entry['totalBytes'], totalSize);
        expect(entry['isPaused'], isTrue);

        // Simulate fresh app launch restoring paused state from disk.
        manager.configureForTesting(downloadDio: dio);
        await manager.syncWithStorage();
        expect(manager.isModelPaused(model.id), isTrue);
        expect(manager.getDownloadState(model.id)?.receivedBytes, partialLen);

        final resumed = await manager.resumeDownload(model.id);
        expect(resumed, isNotNull);
        expect(await partFile.exists(), isFalse);
        expect(manager.isModelDownloaded(model.id), isTrue);
      },
    );
  });

  group('DownloadNotificationService channels & lifecycle', () {
    test(
      'invokes syncDownloadNotifications, handles notification actions, and pauses only on detached lifecycle',
      () async {
        final pausedIds = <String>[];
        final resumedIds = <String>[];
        final cancelledIds = <String>[];
        var forceCloseCount = 0;
        var openDownloadsEvents = 0;

        final service = DownloadNotificationService();
        final openSub = service.onOpenDownloadsRequested.listen((_) {
          openDownloadsEvents++;
        });

        try {
          pendingActionToReturn = {'action': 'open_downloads', 'modelId': null};

          await service.initialize(
            onPause: (id) async => pausedIds.add(id),
            onResume: (id) async => resumedIds.add(id),
            onCancel: (id) async => cancelledIds.add(id),
            onForceClose: () async => forceCloseCount++,
          );
          await Future<void>.delayed(Duration.zero);

          expect(
            recordedMethodCalls.any((c) => c.method == 'consumePendingAction'),
            isTrue,
          );
          expect(openDownloadsEvents, 1);

          await service.syncNotifications(const [
            ModelDownloadState(
              modelId: 'owner/model-1',
              modelName: 'Model One',
              progress: 0.45,
              receivedBytes: 450,
              totalBytes: 1000,
              speedBytesPerSec: 120.0,
              isDownloading: true,
              fileName: 'model-1.gguf',
            ),
          ]);

          final syncCall = recordedMethodCalls.lastWhere(
            (c) => c.method == 'syncDownloadNotifications',
          );
          final args = syncCall.arguments as Map<Object?, Object?>;
          final downloads = args['downloads'] as List<Object?>;
          expect(downloads.length, 1);
          final item = downloads.first as Map<Object?, Object?>;
          expect(item['modelId'], 'owner/model-1');
          expect(item['title'], 'Model One');
          expect(item['isDownloading'], isTrue);

          await service.cancelNotification('owner/model-1');
          expect(
            recordedMethodCalls.any(
              (c) =>
                  c.method == 'cancelDownloadNotification' &&
                  (c.arguments as Map<Object?, Object?>)['modelId'] ==
                      'owner/model-1',
            ),
            isTrue,
          );

          await service.moveToBackground();
          expect(
            recordedMethodCalls.any((c) => c.method == 'moveToBackground'),
            isTrue,
          );

          await emitNativeEvent({'action': 'pause', 'modelId': 'owner/m1'});
          await emitNativeEvent({'action': 'resume', 'modelId': 'owner/m2'});
          await emitNativeEvent({'action': 'cancel', 'modelId': 'owner/m3'});
          await emitNativeEvent({'action': 'open_downloads', 'modelId': null});
          await emitNativeEvent({'action': 'force_close', 'modelId': null});
          await Future<void>.delayed(Duration.zero);

          expect(pausedIds, ['owner/m1']);
          expect(resumedIds, ['owner/m2']);
          expect(cancelledIds, ['owner/m3']);
          expect(openDownloadsEvents, 2);
          expect(forceCloseCount, 1);

          // Inactive, paused, and hidden must NEVER trigger force-close pause.
          final binding = TestWidgetsFlutterBinding.instance;
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await Future<void>.delayed(Duration.zero);
          expect(forceCloseCount, 1);

          // Standard engine sequence paused -> hidden -> inactive -> resumed
          // consumes any pending native action.
          recordedMethodCalls.clear();
          binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await Future<void>.delayed(Duration.zero);
          expect(
            recordedMethodCalls.any((c) => c.method == 'consumePendingAction'),
            isTrue,
          );

          // Standard engine sequence to detached triggers force-close flush.
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
          await Future<void>.delayed(Duration.zero);
          expect(forceCloseCount, 2);
        } finally {
          // Restore resumed lifecycle so SchedulerBinding frames stay enabled
          // for subsequent widget tests.
          TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await openSub.cancel();
        }
      },
    );
  });

  group('DownloadIndicatorButton & active downloads UI', () {
    testWidgets(
      'DownloadIndicatorButton is hidden when idle, shows count when active/paused, and opens sheet with Pause/Resume/Cancel controls',
      (WidgetTester tester) async {
        const totalSize = 128 * 1024;
        final payload = _buildFakeGgufPayload(totalSize);
        final activeStreamController = StreamController<Uint8List>();

        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((
          options,
          cancelFuture,
        ) async {
          if (options.uri.path.contains('active.gguf')) {
            cancelFuture?.whenComplete(() {
              if (!activeStreamController.isClosed) {
                activeStreamController.close();
              }
            });
            activeStreamController.add(
              Uint8List.sublistView(payload, 0, 32 * 1024),
            );
            return ResponseBody(
              activeStreamController.stream,
              200,
              headers: {
                Headers.contentLengthHeader: ['$totalSize'],
              },
            );
          }

          // Paused model stream if resumed in test
          final ctrl = StreamController<Uint8List>();
          cancelFuture?.whenComplete(() {
            if (!ctrl.isClosed) {
              ctrl.close();
            }
          });
          return ResponseBody(
            ctrl.stream,
            200,
            headers: {
              Headers.contentLengthHeader: ['$totalSize'],
            },
          );
        });

        final manager = ModelManagerService();
        manager.configureForTesting(downloadDio: dio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(actions: const [DownloadIndicatorButton()]),
              body: const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pump();

        // Idle: indicator is hidden.
        expect(find.byIcon(Icons.downloading_rounded), findsNothing);
        expect(find.byIcon(Icons.pause_circle_outline_rounded), findsNothing);

        // Seed 1 paused download via disk state + syncWithStorage (real I/O).
        await tester.runAsync(() async {
          final modelsDir = StorageService().modelsDirectory;
          final sep = Platform.pathSeparator;
          await modelsDir.create(recursive: true);
          await File(
            '${modelsDir.path}${sep}paused.gguf.part',
          ).writeAsBytes(Uint8List(16 * 1024));
          await File('${modelsDir.path}${sep}downloads_state.json')
              .writeAsString(
                jsonEncode([
                  {
                    'modelId': 'owner/paused-model',
                    'modelName': 'Paused Model',
                    'fileName': 'paused.gguf',
                    'sourceUrl':
                        'https://huggingface.co/owner/paused-model/resolve/main/paused.gguf',
                    'quantization': 'Q4_K_M',
                    'receivedBytes': 16 * 1024,
                    'totalBytes': totalSize,
                    'isPaused': true,
                  },
                ]),
              );
          await manager.syncWithStorage();
        });
        await tester.pump();

        // Paused only: shows pause icon + count 1.
        expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);
        expect(find.text('1'), findsOneWidget);

        // Start an active download alongside the paused one.
        final activeModel = _makeHfModel(
          id: 'owner/active-model',
          name: 'Active Model',
          fileName: 'active.gguf',
          sizeBytes: totalSize,
        );
        late Future<dynamic> activeFuture;
        await tester.runAsync(() async {
          activeFuture = manager.downloadModel(
            activeModel.id,
            model: activeModel,
          );
          for (var i = 0; i < 50; i++) {
            final st = manager.getDownloadState(activeModel.id);
            if (st != null && st.totalBytes > 0) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();

        // Active > 0: shows downloading icon + active count (1).
        expect(find.byIcon(Icons.downloading_rounded), findsOneWidget);
        expect(find.text('1'), findsOneWidget);

        // Apply strict filter that hides everything in catalog; sheet must still show both.
        manager.updateFilterCriteria(
          ModelFilterCriteria(selectedProviders: {'NoSuchProvider'}),
        );

        await tester.tap(find.byType(DownloadIndicatorButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Model Downloads'), findsOneWidget);
        expect(find.text('Active Model'), findsOneWidget);
        expect(find.text('Paused Model'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
        expect(find.byTooltip('Pause download'), findsOneWidget);
        expect(find.byTooltip('Resume download'), findsOneWidget);
        expect(find.byTooltip('Cancel download'), findsNWidgets(2));

        // Tap Pause on active model.
        await tester.tap(find.byTooltip('Pause download'));
        await tester.pump();
        await tester.runAsync(() async {
          await activeFuture.timeout(const Duration(seconds: 2));
        });
        await tester.pump();

        expect(manager.isModelPaused(activeModel.id), isTrue);
        expect(find.byTooltip('Resume download'), findsNWidgets(2));

        // Tap Resume on paused item and verify active download restarts.
        await tester.tap(find.byTooltip('Resume download').first);
        for (var i = 0; i < 20 && !manager.hasActiveDownloads; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
        }
        await tester.pump();
        expect(manager.hasActiveDownloads, isTrue);

        // Cancel both downloads inside the sheet and verify empty state appears.
        await tester.tap(find.byTooltip('Cancel download').first);
        for (
          var i = 0;
          i < 30 && find.byTooltip('Cancel download').evaluate().length > 1;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(find.byTooltip('Cancel download'), findsOneWidget);

        await tester.tap(find.byTooltip('Cancel download'));
        for (
          var i = 0;
          i < 30 && find.text('No active or paused downloads').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }

        expect(find.text('No active or paused downloads'), findsOneWidget);
        expect(manager.activeAndPausedDownloads, isEmpty);
      },
    );

    testWidgets(
      'HomeScreen PopScope moves to background when downloads are active and opens sheet once per notification tap',
      (WidgetTester tester) async {
        const totalSize = 64 * 1024;
        final payload = _buildFakeGgufPayload(totalSize);
        final controller = StreamController<Uint8List>();

        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((
          options,
          cancelFuture,
        ) async {
          cancelFuture?.whenComplete(() {
            if (!controller.isClosed) {
              controller.close();
            }
          });
          controller.add(Uint8List.sublistView(payload, 0, 8 * 1024));
          return ResponseBody(
            controller.stream,
            200,
            headers: {
              Headers.contentLengthHeader: ['$totalSize'],
            },
          );
        });

        final manager = ModelManagerService();
        manager.configureForTesting(downloadDio: dio);
        await tester.runAsync(
          () => DownloadNotificationService().initialize(
            onPause: manager.pauseDownload,
            onResume: (id) async => manager.resumeDownload(id),
            onCancel: manager.cancelDownload,
            onForceClose: manager.pauseAllActiveDownloads,
          ),
        );

        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pump();

        // Idle: PopScope allows pop (canPop == true).
        final idlePopScope = tester.widget<PopScope<Object?>>(
          find.byWidgetPredicate((w) => w is PopScope),
        );
        expect(idlePopScope.canPop, isTrue);

        // Start active download.
        final model = _makeHfModel(
          id: 'owner/home-dl',
          name: 'Home Active Model',
          fileName: 'home-dl.gguf',
          sizeBytes: totalSize,
        );
        late Future<dynamic> dlFuture;
        await tester.runAsync(() async {
          dlFuture = manager.downloadModel(model.id, model: model);
          for (var i = 0; i < 50; i++) {
            final st = manager.getDownloadState(model.id);
            if (st != null && st.totalBytes > 0) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();

        final activePopScope = tester.widget<PopScope<Object?>>(
          find.byWidgetPredicate((w) => w is PopScope),
        );
        expect(activePopScope.canPop, isFalse);

        // Simulate system back invocation while active download is running.
        activePopScope.onPopInvokedWithResult?.call(false, null);
        await tester.pump();
        expect(
          recordedMethodCalls.any((c) => c.method == 'moveToBackground'),
          isTrue,
        );

        // Simulate duplicate notification tap events; only one sheet opens.
        await tester.runAsync(() async {
          await emitNativeEvent({'action': 'open_downloads', 'modelId': null});
          await emitNativeEvent({'action': 'open_downloads', 'modelId': null});
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Model Downloads'), findsOneWidget);
        expect(find.text('Home Active Model'), findsOneWidget);

        await tester.runAsync(() async {
          await manager.cancelDownload(model.id);
          await dlFuture;
        });
      },
    );
  });
}
