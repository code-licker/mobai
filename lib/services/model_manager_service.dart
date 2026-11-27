import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobai/models/downloaded_model.dart';
import 'package:mobai/models/model_filter_criteria.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/download_notification_service.dart';
import 'package:mobai/services/model_catalog_service.dart';
import 'package:mobai/services/storage_service.dart';

class ModelDownloadState {
  final String modelId;
  final String? modelName;
  final double progress;
  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSec;
  final bool isDownloading;
  final bool isPaused;
  final bool isGatedError;
  final String? errorMessage;
  final String? fileName;
  final String? sourceUrl;
  final String? quantization;
  final int currentPartIndex;
  final int totalParts;
  final List<GgufPart> parts;
  final CancelToken? cancelToken;

  const ModelDownloadState({
    required this.modelId,
    this.modelName,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.isDownloading = false,
    this.isPaused = false,
    this.isGatedError = false,
    this.errorMessage,
    this.fileName,
    this.sourceUrl,
    this.quantization,
    this.currentPartIndex = 0,
    this.totalParts = 1,
    this.parts = const [],
    this.cancelToken,
  });

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    if (modelName != null) 'modelName': modelName,
    'progress': progress,
    'receivedBytes': receivedBytes,
    'totalBytes': totalBytes,
    'isPaused': isPaused,
    if (fileName != null) 'fileName': fileName,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (quantization != null) 'quantization': quantization,
    if (currentPartIndex > 0) 'currentPartIndex': currentPartIndex,
    if (totalParts > 1) 'totalParts': totalParts,
    if (parts.isNotEmpty) 'parts': parts.map((p) => p.toJson()).toList(),
  };

  factory ModelDownloadState.fromJson(Map<String, dynamic> json) {
    final received = (json['receivedBytes'] as num?)?.toInt() ?? 0;
    final total = (json['totalBytes'] as num?)?.toInt() ?? 0;
    final rawParts = json['parts'];
    final parsedParts = rawParts is List
        ? rawParts
            .whereType<Map<String, dynamic>>()
            .map(GgufPart.fromJson)
            .toList()
        : const <GgufPart>[];
    final totalParts = (json['totalParts'] as num?)?.toInt() ??
        (parsedParts.isNotEmpty ? parsedParts.length : 1);
    return ModelDownloadState(
      modelId: (json['modelId'] ?? '').toString(),
      modelName: json['modelName'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ??
          (total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0),
      receivedBytes: received,
      totalBytes: total,
      isDownloading: false,
      isPaused: (json['isPaused'] as bool?) ?? true,
      fileName: json['fileName'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      quantization: json['quantization'] as String?,
      currentPartIndex: (json['currentPartIndex'] as num?)?.toInt() ?? 0,
      totalParts: totalParts,
      parts: parsedParts,
    );
  }

  ModelDownloadState copyWith({
    String? modelName,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    double? speedBytesPerSec,
    bool? isDownloading,
    bool? isPaused,
    bool? isGatedError,
    String? errorMessage,
    bool clearError = false,
    String? fileName,
    String? sourceUrl,
    String? quantization,
    int? currentPartIndex,
    int? totalParts,
    List<GgufPart>? parts,
    CancelToken? cancelToken,
  }) {
    return ModelDownloadState(
      modelId: modelId,
      modelName: modelName ?? this.modelName,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      isDownloading: isDownloading ?? this.isDownloading,
      isPaused: isPaused ?? this.isPaused,
      isGatedError: isGatedError ?? this.isGatedError,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fileName: fileName ?? this.fileName,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      quantization: quantization ?? this.quantization,
      currentPartIndex: currentPartIndex ?? this.currentPartIndex,
      totalParts: totalParts ?? this.totalParts,
      parts: parts ?? this.parts,
      cancelToken: cancelToken ?? this.cancelToken,
    );
  }
}

class ModelManagerService extends ChangeNotifier {
  static final ModelManagerService _instance = ModelManagerService._internal();
  factory ModelManagerService() => _instance;
  ModelManagerService._internal();

  static const String _indexFileName = 'models_index.json';
  static const String _customModelsFileName = 'custom_models.json';
  static const String _downloadsStateFileName = 'downloads_state.json';
  static const int _writeBufferBytes = 1024 * 1024; // 1 MB
  static const int _progressThrottleMs = 1000; // ~1 second UI updates

  ModelCatalogService _catalogService = ModelCatalogService();
  final StorageService _storageService = StorageService();
  final DownloadNotificationService _notificationService =
      DownloadNotificationService();
  Dio _downloadDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 30),
      followRedirects: true,
      maxRedirects: 8,
      headers: {'User-Agent': 'MobAI-App/1.0.0'},
    ),
  );

  /// Optional callback invoked before deleting a downloaded model file
  /// (e.g. to unload it from native inference memory).
  Future<void> Function(String filePath)? onBeforeDeleteModel;

  List<OpenModel> _models = [];
  final List<OpenModel> _customModels = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _nextPageUrl;
  String? _error;
  String _searchQuery = '';
  ModelFilterCriteria _filterCriteria = ModelFilterCriteria.initial();
  ModelSortOption _sortOption = ModelSortOption.popular;

  // Downloaded models indexed by modelId
  final Map<String, DownloadedModel> _downloadedModels = {};

  // Active, paused, and errored download states by modelId
  final Map<String, ModelDownloadState> _downloadStates = {};
  final Set<String> _pauseRequestedIds = {};
  final Map<String, OpenModel> _activeModelsById = {};
  final Map<String, Completer<void>> _activeDownloadCompleters = {};
  final Set<String> _enrichedModelIds = {};
  final Set<String> _inFlightEnrichmentIds = {};
  int _enrichmentEpoch = 0;
  Future<void>? _pauseAllInFlight;
  double _deviceRamGb = 8.0;

  double get deviceRamGb => _deviceRamGb;

  void setDeviceRamGbForTesting(double ramGb) {
    _deviceRamGb = ramGb;
    notifyListeners();
  }

  Future<void> refreshDeviceRam() async {
    _deviceRamGb = await _notificationService.getDeviceRamGb(fallbackGb: 8.0);
  }

  List<OpenModel> get models => List.unmodifiable(_models);

  double get effectiveMaxSizeMb =>
      ModelFilterCriteria.effectiveMaxSizeMbFor(_models);
  double get effectiveMaxParamsB =>
      ModelFilterCriteria.effectiveMaxParamsBFor(_models);
  double get effectiveMaxRamGb =>
      ModelFilterCriteria.effectiveMaxRamGbFor(_models);

  List<OpenModel> get filteredModels {
    final maxS = effectiveMaxSizeMb;
    final maxP = effectiveMaxParamsB;
    final maxR = effectiveMaxRamGb;
    final list = _models
        .where(
          (m) => _filterCriteria.matches(
            m,
            maxSizeMb: maxS,
            maxParamsB: maxP,
            maxRamGb: maxR,
            deviceRamGb: _deviceRamGb,
          ),
        )
        .toList();
    return _applyClientSort(list);
  }

  /// Models that are either downloaded in `MobAI/models` or added as custom URLs.
  List<OpenModel> get myModels {
    final result = <OpenModel>[];
    final seenIds = <String>{};

    for (final c in _customModels) {
      if (seenIds.add(c.id)) {
        result.add(c);
      }
    }

    for (final entry in _downloadedModels.values) {
      if (seenIds.contains(entry.modelId)) continue;
      final existing = _findModelById(entry.modelId);
      if (existing != null) {
        seenIds.add(existing.id);
        result.add(existing);
      } else {
        seenIds.add(entry.modelId);
        result.add(_openModelFromDownloaded(entry));
      }
    }

    final maxS = ModelFilterCriteria.effectiveMaxSizeMbFor(result);
    final maxP = ModelFilterCriteria.effectiveMaxParamsBFor(result);
    final maxR = ModelFilterCriteria.effectiveMaxRamGbFor(result);
    final filtered = result
        .where(
          (m) => _filterCriteria.matches(
            m,
            maxSizeMb: maxS,
            maxParamsB: maxP,
            maxRamGb: maxR,
            deviceRamGb: _deviceRamGb,
          ),
        )
        .toList();
    return _applyClientSort(filtered);
  }

  bool isCustomModel(String modelId) =>
      _customModels.any((m) => m.id == modelId && !m.id.startsWith('local:'));

  List<DownloadedModel> get downloadedModels =>
      List.unmodifiable(_downloadedModels.values);

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreModels => _nextPageUrl != null;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  ModelFilterCriteria get filterCriteria => _filterCriteria;
  ModelSortOption get sortOption => _sortOption;

  List<String> get availableProviders {
    final providers = <String>{};
    for (final m in _models) {
      if (m.publisher.isNotEmpty) {
        providers.add(m.publisher);
      }
    }
    final sorted = providers.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  bool isModelDownloaded(String modelId) {
    final entry = _downloadedModels[modelId];
    if (entry == null) return false;
    return File(entry.filePath).existsSync();
  }

  bool isModelDownloading(String modelId) =>
      _downloadStates[modelId]?.isDownloading ?? false;

  bool isModelPaused(String modelId) =>
      _downloadStates[modelId]?.isPaused ?? false;

  bool get hasActiveDownloads =>
      _downloadStates.values.any((s) => s.isDownloading);

  int get activeDownloadCount =>
      _downloadStates.values.where((s) => s.isDownloading).length;

  int get pausedDownloadCount =>
      _downloadStates.values.where((s) => s.isPaused && !s.isDownloading).length;

  List<ModelDownloadState> get activeAndPausedDownloads {
    final active = <ModelDownloadState>[];
    final paused = <ModelDownloadState>[];
    for (final state in _downloadStates.values) {
      if (state.isDownloading) {
        active.add(state);
      } else if (state.isPaused) {
        paused.add(state);
      }
    }
    return List.unmodifiable([...active, ...paused]);
  }

  double getDownloadProgress(String modelId) =>
      _downloadStates[modelId]?.progress ?? 0.0;

  ModelDownloadState? getDownloadState(String modelId) =>
      _downloadStates[modelId];

  String? getDownloadError(String modelId) =>
      _downloadStates[modelId]?.errorMessage;

  DownloadedModel? getDownloadedModel(String modelId) =>
      _downloadedModels[modelId];

  String? getLocalModelPath(String modelId) {
    final entry = _downloadedModels[modelId];
    if (entry == null) return null;
    if (File(entry.filePath).existsSync()) {
      return entry.filePath;
    }
    return null;
  }

  @visibleForTesting
  void configureForTesting({
    Dio? downloadDio,
    ModelCatalogService? catalogService,
  }) {
    if (downloadDio != null) _downloadDio = downloadDio;
    if (catalogService != null) _catalogService = catalogService;
    _downloadedModels.clear();
    _downloadStates.clear();
    _pauseRequestedIds.clear();
    _activeModelsById.clear();
    _activeDownloadCompleters.clear();
    _enrichedModelIds.clear();
    _inFlightEnrichmentIds.clear();
    _enrichmentEpoch++;
    _pauseAllInFlight = null;
    _customModels.clear();
    _models = [];
    _nextPageUrl = null;
    _isLoadingMore = false;
    _sortOption = ModelSortOption.popular;
  }

  File get _indexFile => File(
    '${_storageService.modelsPath}${Platform.pathSeparator}$_indexFileName',
  );

  File get _customModelsFile => File(
    '${_storageService.modelsPath}${Platform.pathSeparator}$_customModelsFileName',
  );

  File get _downloadsStateFile => File(
    '${_storageService.modelsPath}${Platform.pathSeparator}$_downloadsStateFileName',
  );

  /// Synchronizes downloaded and custom model metadata with `MobAI/models/`.
  /// Any unmanaged `.gguf` files found in `MobAI/models/` are auto-detected.
  Future<void> syncWithStorage() async {
    if (!_storageService.isInitialized) return;

    final modelsDir = _storageService.modelsDirectory;
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    await _loadCustomModelsFromDisk();

    _downloadedModels.clear();
    final trackedPaths = <String>{};

    // 1. Load models_index.json and drop entries whose files no longer exist.
    if (await _indexFile.exists()) {
      try {
        final raw = await _indexFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final entry = DownloadedModel.fromJson(item);
              if (entry.modelId.isNotEmpty &&
                  entry.filePath.isNotEmpty &&
                  await File(entry.filePath).exists()) {
                final entryDir = File(entry.filePath).parent.path;
                bool allPartsPresent = true;
                final candidateTracked = <String>[
                  File(entry.filePath).absolute.path,
                ];
                if (entry.partFileNames.isNotEmpty) {
                  for (final partName in entry.partFileNames) {
                    final partPath =
                        '$entryDir${Platform.pathSeparator}$partName';
                    final partFile = File(partPath);
                    if (!await partFile.exists()) {
                      allPartsPresent = false;
                      break;
                    }
                    candidateTracked.add(partFile.absolute.path);
                  }
                }
                if (!allPartsPresent) continue;

                _downloadedModels[entry.modelId] = entry;
                trackedPaths.addAll(candidateTracked);
                if (entry.modelId.startsWith('local:') &&
                    !_customModels.any((m) => m.id == entry.modelId)) {
                  final localModel = _openModelFromDownloaded(entry);
                  _customModels.insert(0, localModel);
                }
              }
            }
          }
        }
      } catch (_) {
        // Corrupt index will be rebuilt from disk scan below.
      }
    }

    // 2. Scan MobAI/models for any .gguf files not yet indexed.
    await for (final entity in modelsDir.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
        final absPath = entity.absolute.path;
        if (trackedPaths.contains(absPath)) continue;

        final fileName = _basename(entity.path);
        final splitInfo = OpenModel.parseSplitShard(fileName);
        if (splitInfo != null && splitInfo.partNumber > 1) {
          // Secondary shards are grouped under part 1 when complete.
          continue;
        }

        int totalSizeBytes = await entity.length();
        List<String> partFileNames = const [];
        if (splitInfo != null && splitInfo.partNumber == 1) {
          final padTotal = splitInfo.totalParts.toString().padLeft(5, '0');
          final sep = Platform.pathSeparator;
          bool complete = true;
          int combinedSize = 0;
          final partsList = <String>[];
          final partPaths = <String>[];
          for (var k = 1; k <= splitInfo.totalParts; k++) {
            final padIdx = k.toString().padLeft(5, '0');
            final shardName = '${splitInfo.prefix}-$padIdx-of-$padTotal.gguf';
            final shardFile = File('${modelsDir.path}$sep$shardName');
            if (!await shardFile.exists()) {
              complete = false;
              break;
            }
            combinedSize += await shardFile.length();
            partsList.add(shardName);
            partPaths.add(shardFile.absolute.path);
          }
          if (!complete) {
            // Incomplete manual split drop: do not mark as ready.
            continue;
          }
          totalSizeBytes = combinedSize;
          partFileNames = partsList;
          trackedPaths.addAll(partPaths);
        }

        final matchedCatalogModel = _findCatalogModelByFileName(fileName);
        final quant = _extractQuantFromFileName(fileName);
        final modelId = matchedCatalogModel?.id ?? 'local:$fileName';
        final cleanName = matchedCatalogModel?.name ??
            fileName
                .replaceAll(
                  RegExp(r'-\d{5}-of-\d{5}\.gguf$', caseSensitive: false),
                  '',
                )
                .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '')
                .replaceAll('-', ' ')
                .replaceAll('_', ' ')
                .trim();

        final localEntry = DownloadedModel(
          modelId: modelId,
          name: cleanName.isEmpty ? fileName : cleanName,
          publisher: matchedCatalogModel?.publisher ?? 'Local',
          fileName: fileName,
          filePath: entity.path,
          quantization: quant,
          sizeBytes: totalSizeBytes,
          downloadedAt: await entity.lastModified(),
          sourceUrl: matchedCatalogModel?.downloadUrl ?? '',
          partFileNames: partFileNames,
        );

        _downloadedModels[modelId] = localEntry;
        trackedPaths.add(absPath);

        if (matchedCatalogModel == null &&
            !_customModels.any((m) => m.id == modelId)) {
          final customModel = _openModelFromDownloaded(localEntry);
          _customModels.insert(0, customModel);
        }
      }
    }

    for (final c in _customModels) {
      if (!_models.any((m) => m.id == c.id)) {
        _models = [c, ..._models];
      }
    }

    await _saveIndex();
    await _saveCustomModels();
    await _loadPausedDownloadsFromDisk();
    await refreshDeviceRam();
    _syncDownloadNotifications();
    notifyListeners();
  }

  Future<void> _loadPausedDownloadsFromDisk() async {
    if (!await _downloadsStateFile.exists()) return;
    try {
      final raw = await _downloadsStateFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      bool changed = false;
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final parsed = ModelDownloadState.fromJson(item);
          if (parsed.modelId.isEmpty || isModelDownloaded(parsed.modelId)) {
            changed = true;
            continue;
          }
          if (isModelDownloading(parsed.modelId)) {
            continue;
          }
          if (parsed.parts.isNotEmpty) {
            int restoredBytes = 0;
            int activePartIndex = 0;
            bool hasPartialOrCompleted = false;
            final sep = Platform.pathSeparator;
            for (var i = 0; i < parsed.parts.length; i++) {
              final safePart = _sanitizeFileName(parsed.parts[i].fileName);
              final finalPartFile = File('${_storageService.modelsPath}$sep$safePart');
              if (await finalPartFile.exists()) {
                restoredBytes += await finalPartFile.length();
                activePartIndex = i + 1;
                hasPartialOrCompleted = true;
                continue;
              }
              final inProgressPartFile = File(
                '${_storageService.modelsPath}$sep$safePart.part',
              );
              if (await inProgressPartFile.exists()) {
                final partBytes = await inProgressPartFile.length();
                if (partBytes > 0) {
                  restoredBytes += partBytes;
                  hasPartialOrCompleted = true;
                }
              }
              activePartIndex = i;
              break;
            }
            if (hasPartialOrCompleted && restoredBytes > 0) {
              final total = parsed.totalBytes;
              _downloadStates[parsed.modelId] = parsed.copyWith(
                receivedBytes: restoredBytes,
                progress: total > 0
                    ? (restoredBytes / total).clamp(0.0, 1.0)
                    : 0.0,
                currentPartIndex: activePartIndex,
                isPaused: true,
                isDownloading: false,
              );
              continue;
            }
            changed = true;
            continue;
          }
          final fname = parsed.fileName;
          if (fname == null || fname.isEmpty) continue;
          final partFile = File(
            '${_storageService.modelsPath}${Platform.pathSeparator}$fname.part',
          );
          if (await partFile.exists()) {
            final bytesOnDisk = await partFile.length();
            if (bytesOnDisk > 0) {
              final total = parsed.totalBytes;
              _downloadStates[parsed.modelId] = parsed.copyWith(
                receivedBytes: bytesOnDisk,
                progress: total > 0 ? (bytesOnDisk / total).clamp(0.0, 1.0) : 0.0,
                isPaused: true,
                isDownloading: false,
              );
              continue;
            }
          }
          changed = true;
        }
      }
      if (changed) {
        await _saveDownloadsState();
      }
    } catch (_) {}
  }

  Future<void> _saveDownloadsState() async {
    if (!_storageService.isInitialized) return;
    final dir = _storageService.modelsDirectory;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final resumable = _downloadStates.values
        .where((s) => (s.isPaused || s.isDownloading) && s.fileName != null)
        .map((s) {
          final json = s.toJson();
          // Persist active downloads as paused/resumable on disk so an abrupt
          // OS force-close leaves .part + metadata ready to resume on launch.
          json['isPaused'] = true;
          return json;
        })
        .toList();
    if (resumable.isEmpty) {
      if (await _downloadsStateFile.exists()) {
        await _downloadsStateFile.delete();
      }
      return;
    }
    await _downloadsStateFile.writeAsString(jsonEncode(resumable), flush: true);
  }

  void _syncDownloadNotifications() {
    unawaited(
      _notificationService.syncNotifications(activeAndPausedDownloads),
    );
  }

  OpenModel _openModelFromDownloaded(DownloadedModel entry) {
    final sizeMb = (entry.sizeBytes / (1024 * 1024)).round().clamp(1, 10000000);
    return OpenModel(
      id: entry.modelId,
      name: entry.name,
      publisher: entry.publisher,
      parameterSizeB: '1.0',
      format: 'GGUF',
      quantization: entry.quantization,
      downloadSizeMb: sizeMb,
      minRamGb: (((sizeMb / 1024) * 1.5).ceil() + 1).clamp(2, 2048),
      downloadUrl: entry.sourceUrl,
      description: entry.partCount > 1
          ? 'Local split GGUF model (${entry.partCount} parts) stored in MobAI/models (${entry.fileName}).'
          : 'Local GGUF model stored in MobAI/models (${entry.fileName}).',
      repoUrl: entry.sourceUrl,
    );
  }

  Future<void> _loadCustomModelsFromDisk() async {
    if (!await _customModelsFile.exists()) return;
    try {
      final raw = await _customModelsFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final model = OpenModel.fromJson(item);
            if (model.id.isNotEmpty &&
                !_customModels.any((m) => m.id == model.id)) {
              _customModels.add(model);
            }
          }
        }
      }
    } catch (_) {
      // Ignore corrupt custom_models.json
    }
  }

  Future<void> _saveCustomModels() async {
    if (!_storageService.isInitialized) return;
    final dir = _storageService.modelsDirectory;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final persistable = _customModels
        .where((m) => !m.id.startsWith('local:'))
        .map((m) => m.toJson())
        .toList();
    await _customModelsFile.writeAsString(jsonEncode(persistable), flush: true);
  }

  OpenModel? _findCatalogModelByFileName(String fileName) {
    final lower = fileName.toLowerCase();
    for (final m in [..._customModels, ..._models]) {
      if (m.downloadUrl.isNotEmpty &&
          _basename(m.downloadUrl).toLowerCase() == lower) {
        return m;
      }
      for (final v in m.variants) {
        if (_basename(v.fileName).toLowerCase() == lower) {
          return m;
        }
      }
    }
    return null;
  }

  Future<void> _saveIndex() async {
    if (!_storageService.isInitialized) return;
    final dir = _storageService.modelsDirectory;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final payload = _downloadedModels.values.map((m) => m.toJson()).toList();
    await _indexFile.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<void> loadModels() async {
    await searchModels('');
  }

  Future<void> searchModels(String query) async {
    _searchQuery = query.trim();
    _isLoading = true;
    _error = null;
    _nextPageUrl = null;
    notifyListeners();

    try {
      final page = await _catalogService.fetchModelsPage(
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        sortOption: _sortOption,
      );
      _nextPageUrl = page.nextPageUrl;

      // Preserve custom & locally detected models that match query
      final relevantCustom = _customModels.where((c) {
        if (_searchQuery.isEmpty) return true;
        final q = _searchQuery.toLowerCase();
        return c.name.toLowerCase().contains(q) ||
            c.publisher.toLowerCase().contains(q) ||
            c.id.toLowerCase().contains(q);
      }).toList();

      final combined = <OpenModel>[...relevantCustom];
      final seenIds = combined.map((m) => m.id).toSet();
      for (final m in page.models) {
        if (seenIds.add(m.id)) {
          combined.add(m);
        }
      }
      _models = combined;
      _scheduleCatalogSizeEnrichment(page.models);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads the next cursor page of Hugging Face models if available.
  Future<void> loadMoreModels() async {
    if (_isLoading || _isLoadingMore || _nextPageUrl == null) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final page = await _catalogService.fetchModelsPage(
        pageUrl: _nextPageUrl,
        sortOption: _sortOption,
      );
      _nextPageUrl = page.nextPageUrl;
      final existingIds = _models.map((m) => m.id).toSet();
      final additions = page.models
          .where((m) => existingIds.add(m.id))
          .toList();
      if (additions.isNotEmpty) {
        _models = [..._models, ...additions];
        _scheduleCatalogSizeEnrichment(additions);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void _scheduleCatalogSizeEnrichment(List<OpenModel> candidates) {
    final epoch = _enrichmentEpoch;
    final pending = candidates
        .where(
          (m) =>
              !m.id.startsWith('local:') &&
              m.repoUrl.contains('huggingface.co') &&
              m.id.contains('/') &&
              !m.hasExactSizes &&
              !_enrichedModelIds.contains(m.id) &&
              !_inFlightEnrichmentIds.contains(m.id),
        )
        .take(40)
        .toList();
    if (pending.isEmpty) return;

    for (final m in pending) {
      _inFlightEnrichmentIds.add(m.id);
    }
    unawaited(_runCatalogSizeEnrichment(pending, epoch));
  }

  Future<void> _runCatalogSizeEnrichment(
    List<OpenModel> queue,
    int epoch,
  ) async {
    var cursor = 0;
    const workerCount = 4;

    Future<void> worker() async {
      while (cursor < queue.length && epoch == _enrichmentEpoch) {
        final model = queue[cursor++];
        try {
          final fetched = await _catalogService.fetchRepoGgufVariants(model.id);
          if (epoch != _enrichmentEpoch) return;
          _enrichedModelIds.add(model.id);
          if (fetched.isNotEmpty) {
            final changed = _applyVariantsToCatalogModel(model.id, fetched);
            if (changed) {
              notifyListeners();
            }
          }
        } catch (_) {
          // Leave estimated catalog size intact on network/rate-limit errors.
        } finally {
          _inFlightEnrichmentIds.remove(model.id);
        }
      }
    }

    await Future.wait(
      List.generate(
        queue.length < workerCount ? queue.length : workerCount,
        (_) => worker(),
      ),
    );
  }

  bool _applyVariantsToCatalogModel(
    String modelId,
    List<GgufVariant> fetched,
  ) {
    if (fetched.isEmpty) return false;
    final primary = fetched.first;
    bool updated = false;

    OpenModel applyUpdate(OpenModel m) {
      final newSizeMb = primary.sizeMb > 0 ? primary.sizeMb : m.downloadSizeMb;
      final newMinRamGb = primary.sizeMb > 0
          ? (((newSizeMb / 1024) * 1.5).ceil() + 1).clamp(2, 2048)
          : m.minRamGb;
      return m.copyWith(
        variants: fetched,
        downloadUrl: primary.downloadUrl.isNotEmpty
            ? primary.downloadUrl
            : m.downloadUrl,
        quantization: primary.quantization,
        downloadSizeMb: newSizeMb,
        minRamGb: newMinRamGb,
      );
    }

    final idx = _models.indexWhere((m) => m.id == modelId);
    if (idx != -1) {
      _models[idx] = applyUpdate(_models[idx]);
      updated = true;
    }
    final customIdx = _customModels.indexWhere((m) => m.id == modelId);
    if (customIdx != -1) {
      _customModels[customIdx] = applyUpdate(_customModels[customIdx]);
      updated = true;
    }
    return updated;
  }

  void _applyExactBytesToCatalogModel(String modelId, int totalBytes) {
    if (totalBytes <= 0) return;
    final newSizeMb = (totalBytes / (1024 * 1024)).round().clamp(1, 10000000);
    final newMinRamGb = (((newSizeMb / 1024) * 1.5).ceil() + 1).clamp(2, 2048);

    final idx = _models.indexWhere((m) => m.id == modelId);
    if (idx != -1 && (_models[idx].downloadSizeMb - newSizeMb).abs() >= 2) {
      _models[idx] = _models[idx].copyWith(
        downloadSizeMb: newSizeMb,
        minRamGb: newMinRamGb,
      );
    }
    final customIdx = _customModels.indexWhere((m) => m.id == modelId);
    if (customIdx != -1 &&
        (_customModels[customIdx].downloadSizeMb - newSizeMb).abs() >= 2) {
      _customModels[customIdx] = _customModels[customIdx].copyWith(
        downloadSizeMb: newSizeMb,
        minRamGb: newMinRamGb,
      );
    }
  }

  Future<void> setSortOption(ModelSortOption option) async {
    if (_sortOption == option) return;
    final previous = _sortOption;
    _sortOption = option;

    // Server-side HF sorts re-fetch from page 1 unless switching within client sorts
    final needsServerFetch =
        option == ModelSortOption.latest ||
        (option == ModelSortOption.popular &&
            previous != ModelSortOption.popular);

    if (needsServerFetch) {
      await searchModels(_searchQuery);
    } else {
      notifyListeners();
    }
  }

  Future<void> updateSortOption(ModelSortOption option) => setSortOption(option);

  void toggleHideNotRecommended() {
    _filterCriteria = _filterCriteria.copyWith(
      hideNotRecommended: !_filterCriteria.hideNotRecommended,
    );
    notifyListeners();
  }

  void setDownloadedOnly(bool value) {
    if (_filterCriteria.downloadedOnly == value) return;
    _filterCriteria = _filterCriteria.copyWith(downloadedOnly: value);
    notifyListeners();
  }

  List<OpenModel> _applyClientSort(List<OpenModel> input) {
    final list = List<OpenModel>.from(input);
    switch (_sortOption) {
      case ModelSortOption.popular:
        return list;
      case ModelSortOption.latest:
        list.sort((a, b) {
          final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
        return list;
      case ModelSortOption.sizeAsc:
        list.sort((a, b) => a.downloadSizeMb.compareTo(b.downloadSizeMb));
        return list;
      case ModelSortOption.sizeDesc:
        list.sort((a, b) => b.downloadSizeMb.compareTo(a.downloadSizeMb));
        return list;
      case ModelSortOption.paramsAsc:
        list.sort((a, b) => a.paramSizeNum.compareTo(b.paramSizeNum));
        return list;
      case ModelSortOption.paramsDesc:
        list.sort((a, b) => b.paramSizeNum.compareTo(a.paramSizeNum));
        return list;
    }
  }

  void updateFilterCriteria(ModelFilterCriteria criteria) {
    _filterCriteria = criteria;
    notifyListeners();
  }

  void clearFilters() {
    _filterCriteria = ModelFilterCriteria.initial();
    notifyListeners();
  }

  void addCustomModel(OpenModel model) {
    final existingCustomIdx = _customModels.indexWhere((m) => m.id == model.id);
    if (existingCustomIdx != -1) {
      _customModels[existingCustomIdx] = model;
    } else {
      _customModels.insert(0, model);
    }

    final existingIdx = _models.indexWhere((m) => m.id == model.id);
    if (existingIdx != -1) {
      _models[existingIdx] = model;
    } else {
      _models = [model, ..._models];
    }

    if (!model.id.startsWith('local:')) {
      unawaited(_saveCustomModels());
    }
    notifyListeners();
  }

  /// Removes a custom URL model from `custom_models.json` (and deletes its
  /// downloaded file if present).
  Future<void> removeCustomModel(String modelId) async {
    if (isModelDownloaded(modelId)) {
      await deleteDownloadedModel(modelId);
    }
    _customModels.removeWhere((m) => m.id == modelId);
    _models.removeWhere((m) => m.id == modelId);
    await _saveCustomModels();
    notifyListeners();
  }

  /// Copies an external `.gguf` file from [sourcePath] into `MobAI/models/`,
  /// validates its `GGUF` magic header, and registers it for immediate chat.
  Future<DownloadedModel> importLocalGgufFile(
    String sourcePath, {
    void Function(double progress)? onProgress,
  }) async {
    if (!_storageService.isInitialized) {
      await _storageService.init();
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Selected file does not exist.', sourcePath);
    }

    final isValidGguf = await _hasGgufMagicHeader(sourceFile);
    if (!isValidGguf) {
      throw const FormatException(
        'Selected file is not a valid GGUF model (missing GGUF header).',
      );
    }

    final rawBaseName = _basename(sourcePath);
    if (OpenModel.isAuxiliaryGgufFile(rawBaseName)) {
      throw FormatException(
        '"$rawBaseName" is an auxiliary MTP/projector/draft file and cannot run standalone chat.',
      );
    }

    final safeFileName = _sanitizeFileName(_basename(sourcePath));
    final modelsDir = _storageService.modelsDirectory;
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final destPath = '${modelsDir.path}${Platform.pathSeparator}$safeFileName';
    final totalBytes = await sourceFile.length();

    if (sourceFile.absolute.path != File(destPath).absolute.path) {
      final partPath = '$destPath.part';
      final partFile = File(partPath);
      if (await partFile.exists()) {
        await partFile.delete();
      }

      final sink = partFile.openWrite();
      int copied = 0;
      try {
        await for (final chunk in sourceFile.openRead()) {
          sink.add(chunk);
          copied += chunk.length;
          if (totalBytes > 0) {
            onProgress?.call((copied / totalBytes).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final destFile = File(destPath);
      if (await destFile.exists()) {
        await destFile.delete();
      }
      await partFile.rename(destPath);
    }

    onProgress?.call(1.0);
    final actualSize = await File(destPath).length();
    final quant = _extractQuantFromFileName(safeFileName);
    final modelId = 'local:$safeFileName';
    final cleanName = safeFileName
        .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();

    final downloaded = DownloadedModel(
      modelId: modelId,
      name: cleanName.isEmpty ? safeFileName : cleanName,
      publisher: 'Local',
      fileName: safeFileName,
      filePath: destPath,
      quantization: quant,
      sizeBytes: actualSize,
      downloadedAt: DateTime.now(),
      sourceUrl: '',
    );

    _downloadedModels[modelId] = downloaded;
    addCustomModel(_openModelFromDownloaded(downloaded));
    await _saveIndex();
    notifyListeners();
    return downloaded;
  }

  /// Resolves available `.gguf` variants for [model], fetching repo details
  /// from Hugging Face if [model.variants] is empty or lacks byte sizes.
  Future<List<GgufVariant>> getVariantsForModel(OpenModel model) async {
    if (model.variants.isNotEmpty && model.hasExactSizes) {
      return model.variants;
    }
    final isHuggingFaceRepo =
        model.repoUrl.contains('huggingface.co') &&
        !model.id.startsWith('local:') &&
        model.id.contains('/');
    if (!isHuggingFaceRepo) {
      if (model.variants.isNotEmpty) return model.variants;
      if (model.downloadUrl.isNotEmpty &&
          _looksLikeDirectBinaryUrl(model.downloadUrl)) {
        return [
          GgufVariant(
            fileName: _basename(model.downloadUrl),
            quantization: model.quantization,
            sizeBytes: model.downloadSizeMb > 0
                ? model.downloadSizeMb * 1024 * 1024
                : null,
            downloadUrl: model.downloadUrl,
          ),
        ];
      }
      return const [];
    }

    try {
      final fetched = await _catalogService.fetchRepoGgufVariants(model.id);
      _enrichedModelIds.add(model.id);
      if (fetched.isNotEmpty) {
        if (_applyVariantsToCatalogModel(model.id, fetched)) {
          notifyListeners();
        }
        return fetched;
      }
    } catch (_) {
      if (model.variants.isNotEmpty) return model.variants;
      rethrow;
    }
    return model.variants;
  }

  /// Resumes a paused download from its `.part` byte offset on disk.
  Future<DownloadedModel?> resumeDownload(
    String modelId, {
    OpenModel? model,
    void Function(double progress)? onProgress,
  }) {
    return downloadModel(modelId, model: model, onProgress: onProgress);
  }

  /// Pauses an active download while preserving the `.part` file on disk.
  Future<void> pauseDownload(String modelId) async {
    final state = _downloadStates[modelId];
    if (state == null || !state.isDownloading) return;
    _pauseRequestedIds.add(modelId);
    state.cancelToken?.cancel('Paused by user');
  }

  /// Pauses every currently active download and waits for buffered bytes and
  /// `downloads_state.json` to flush cleanly to disk.
  Future<void> pauseAllActiveDownloads() {
    final existing = _pauseAllInFlight;
    if (existing != null) return existing;
    final future = _doPauseAllActiveDownloads().whenComplete(() {
      _pauseAllInFlight = null;
    });
    _pauseAllInFlight = future;
    return future;
  }

  Future<void> _doPauseAllActiveDownloads() async {
    final activeIds = _downloadStates.entries
        .where((e) => e.value.isDownloading)
        .map((e) => e.key)
        .toList();
    if (activeIds.isEmpty) return;

    final futuresToAwait = <Future<void>>[];
    for (final id in activeIds) {
      final completer = _activeDownloadCompleters[id];
      if (completer != null && !completer.isCompleted) {
        futuresToAwait.add(completer.future);
      }
      await pauseDownload(id);
    }

    if (futuresToAwait.isNotEmpty) {
      await Future.wait(futuresToAwait).timeout(
        const Duration(seconds: 5),
        onTimeout: () => const <void>[],
      );
    }

    await _saveDownloadsState();
    _syncDownloadNotifications();
  }

  /// Downloads a model `.gguf` into `MobAI/models/` using a 1 MB write buffer,
  /// ~1s UI progress throttling, and HTTP Range resume support.
  Future<DownloadedModel?> downloadModel(
    String modelId, {
    OpenModel? model,
    GgufVariant? variant,
    void Function(double progress)? onProgress,
  }) async {
    final existing = getDownloadedModel(modelId);
    if (existing != null && await File(existing.filePath).exists()) {
      onProgress?.call(1.0);
      return existing;
    }

    if (isModelDownloading(modelId)) {
      return null;
    }

    final previousState = _downloadStates[modelId];
    final targetModel =
        model ??
        _findModelById(modelId) ??
        _openModelFromDownloadState(previousState);
    if (targetModel == null) {
      _setDownloadError(modelId, 'Model metadata not found.');
      return null;
    }

    if (!_storageService.isInitialized) {
      await _storageService.init();
    }

    _activeModelsById[modelId] = targetModel;
    unawaited(_notificationService.ensureNotificationPermission());

    final prevSourceUrl = previousState?.sourceUrl;
    final prevFileName = previousState?.fileName;
    final prevParts = previousState?.parts ?? const <GgufPart>[];
    final effectiveVariant = variant ??
        (prevParts.isNotEmpty
            ? GgufVariant(
                fileName: prevFileName ?? prevParts.first.fileName,
                quantization:
                    previousState?.quantization ?? targetModel.quantization,
                sizeBytes: (previousState?.totalBytes ?? 0) > 0
                    ? previousState?.totalBytes
                    : null,
                downloadUrl: prevSourceUrl ?? prevParts.first.downloadUrl,
                parts: prevParts,
                expectedParts: previousState?.totalParts ?? prevParts.length,
              )
            : (prevSourceUrl != null && prevFileName != null
                ? GgufVariant(
                    fileName: prevFileName,
                    quantization:
                        previousState?.quantization ?? targetModel.quantization,
                    sizeBytes: (previousState?.totalBytes ?? 0) > 0
                        ? previousState?.totalBytes
                        : null,
                    downloadUrl: prevSourceUrl,
                  )
                : null));

    _pauseRequestedIds.remove(modelId);
    final cancelToken = CancelToken();
    final downloadCompleter = Completer<void>();
    _activeDownloadCompleters[modelId] = downloadCompleter;

    _downloadStates[modelId] = ModelDownloadState(
      modelId: modelId,
      modelName: targetModel.name,
      progress: previousState?.progress ?? 0.0,
      receivedBytes: previousState?.receivedBytes ?? 0,
      totalBytes: previousState?.totalBytes ?? 0,
      isDownloading: true,
      isPaused: false,
      fileName: previousState?.fileName,
      sourceUrl: previousState?.sourceUrl,
      quantization: previousState?.quantization ?? targetModel.quantization,
      currentPartIndex: previousState?.currentPartIndex ?? 0,
      totalParts: previousState?.totalParts ?? 1,
      parts: prevParts,
      cancelToken: cancelToken,
    );
    _syncDownloadNotifications();
    notifyListeners();

    String? activePartFilePath;
    int totalExpectedBytes = previousState?.totalBytes ?? 0;
    String? resolvedFileName = previousState?.fileName;
    String? resolvedSourceUrl = previousState?.sourceUrl;
    String resolvedQuant = previousState?.quantization ?? targetModel.quantization;
    List<GgufPart> downloadParts = prevParts;
    int activePartIdx = previousState?.currentPartIndex ?? 0;
    int completedBeforePart = 0;
    final completedPartPaths = <String>[];
    final completedPartNames = <String>[];

    try {
      final resolved = await _resolveDownloadTarget(
        targetModel,
        effectiveVariant,
      );
      if (resolved == null) {
        if (cancelToken.isCancelled) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: targetModel.downloadUrl),
            reason: cancelToken.cancelError?.message ?? 'Cancelled',
          );
        }
        _setDownloadError(
          modelId,
          'No downloadable .gguf file found for ${targetModel.name}.',
        );
        return null;
      }

      if (resolved.hasMissingParts) {
        _setDownloadError(
          modelId,
          'Incomplete split model on Hugging Face: found ${resolved.parts.length} of ${resolved.partCount} parts.',
        );
        return null;
      }

      downloadParts = resolved.resolvedParts;
      final primarySafeFileName = _sanitizeFileName(downloadParts.first.fileName);
      resolvedFileName = primarySafeFileName;
      resolvedSourceUrl = downloadParts.first.downloadUrl;
      resolvedQuant = resolved.quantization;

      final modelsDir = _storageService.modelsDirectory;
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final sep = Platform.pathSeparator;
      final knownSumBytes = downloadParts.fold<int>(
        0,
        (sum, p) => sum + ((p.sizeBytes != null && p.sizeBytes! > 0) ? p.sizeBytes! : 0),
      );
      totalExpectedBytes = knownSumBytes > 0
          ? knownSumBytes
          : (resolved.sizeBytes ?? targetModel.downloadSizeMb * 1024 * 1024);

      for (var partIdx = 0; partIdx < downloadParts.length; partIdx++) {
        activePartIdx = partIdx;
        final part = downloadParts[partIdx];
        final safePartName = _sanitizeFileName(part.fileName);
        final finalPartPath = '${modelsDir.path}$sep$safePartName';
        final finalPartFile = File(finalPartPath);

        if (await finalPartFile.exists()) {
          final existingFinalLen = await finalPartFile.length();
          final expectedPartLen = part.sizeBytes;
          final sizeMatches =
              expectedPartLen == null || existingFinalLen == expectedPartLen;
          final headerOk =
              partIdx > 0 || await _hasGgufMagicHeader(finalPartFile);
          if (sizeMatches && headerOk && existingFinalLen > 0) {
            completedBeforePart += existingFinalLen;
            completedPartPaths.add(finalPartPath);
            completedPartNames.add(safePartName);
            continue;
          }
          await finalPartFile.delete();
        }

        activePartFilePath = '$finalPartPath.part';

        if (cancelToken.isCancelled) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: part.downloadUrl),
            reason: cancelToken.cancelError?.message ?? 'Cancelled',
          );
        }

        final partFile = File(activePartFilePath);
        int existingBytes =
            await partFile.exists() ? await partFile.length() : 0;

        Response<ResponseBody> response = await _openDownloadStream(
          url: part.downloadUrl,
          offsetBytes: existingBytes,
          cancelToken: cancelToken,
        );

        if (response.statusCode == 416) {
          final contentRangeTotal = _parseTotalFromContentRange(
            response.headers.value('content-range'),
          );
          await response.data?.stream.drain<void>().catchError((_) {});
          final headerOk = partIdx > 0 || await _hasGgufMagicHeader(partFile);
          if (existingBytes >= 4 &&
              contentRangeTotal != null &&
              existingBytes == contentRangeTotal &&
              headerOk) {
            await finalPartFile.parent.create(recursive: true);
            if (await finalPartFile.exists()) {
              await finalPartFile.delete();
            }
            await partFile.rename(finalPartPath);
            activePartFilePath = null;
            completedBeforePart += await finalPartFile.length();
            completedPartPaths.add(finalPartPath);
            completedPartNames.add(safePartName);
            continue;
          }
          await _cleanupPartFile(activePartFilePath);
          existingBytes = 0;
          response = await _openDownloadStream(
            url: part.downloadUrl,
            offsetBytes: 0,
            cancelToken: cancelToken,
          );
        }

        final contentType =
            response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
                '';
        if (contentType.contains('text/html')) {
          await response.data?.stream.drain<void>().catchError((_) {});
          await _cleanupPartFile(activePartFilePath);
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            message:
                'Hugging Face returned a web page instead of a GGUF binary (the model may be gated or require authentication).',
          );
        }

        final isPartial = response.statusCode == 206 && existingBytes > 0;
        if (!isPartial && existingBytes > 0) {
          await _cleanupPartFile(activePartFilePath);
          existingBytes = 0;
        }

        final contentRangeTotal = _parseTotalFromContentRange(
          response.headers.value('content-range'),
        );
        final contentLen = int.tryParse(
              response.headers.value(Headers.contentLengthHeader) ?? '',
            ) ??
            0;
        final currentPartTotal = contentRangeTotal ??
            (isPartial && contentLen > 0
                ? existingBytes + contentLen
                : (contentLen > 0 ? contentLen : (part.sizeBytes ?? 0)));
        if (downloadParts.length == 1 && currentPartTotal > 0) {
          totalExpectedBytes = currentPartTotal;
          _applyExactBytesToCatalogModel(modelId, totalExpectedBytes);
        } else if (totalExpectedBytes <= 0 && currentPartTotal > 0) {
          totalExpectedBytes = completedBeforePart + currentPartTotal;
          _applyExactBytesToCatalogModel(modelId, totalExpectedBytes);
        } else if (totalExpectedBytes > 0) {
          _applyExactBytesToCatalogModel(modelId, totalExpectedBytes);
        }

        int partReceived = existingBytes;
        int totalReceived = completedBeforePart + partReceived;
        int lastBytes = totalReceived;
        DateTime lastTick = DateTime.now();

        _downloadStates[modelId] = ModelDownloadState(
          modelId: modelId,
          modelName: targetModel.name,
          progress: totalExpectedBytes > 0
              ? (totalReceived / totalExpectedBytes).clamp(0.0, 1.0)
              : 0.0,
          receivedBytes: totalReceived,
          totalBytes: totalExpectedBytes,
          speedBytesPerSec: 0.0,
          isDownloading: true,
          isPaused: false,
          fileName: primarySafeFileName,
          sourceUrl: resolvedSourceUrl,
          quantization: resolvedQuant,
          currentPartIndex: partIdx,
          totalParts: downloadParts.length,
          parts: downloadParts,
          cancelToken: cancelToken,
        );
        await _saveDownloadsState();
        _syncDownloadNotifications();
        notifyListeners();

        final raf = await partFile.open(
          mode: isPartial ? FileMode.append : FileMode.write,
        );
        final buffer = BytesBuilder(copy: false);

        try {
          final stream = response.data?.stream;
          if (stream != null) {
            await for (final chunk in stream) {
              buffer.add(chunk);
              partReceived += chunk.length;
              totalReceived = completedBeforePart + partReceived;

              if (buffer.length >= _writeBufferBytes) {
                await raf.writeFrom(buffer.takeBytes());
              }

              final now = DateTime.now();
              final elapsedMs = now.difference(lastTick).inMilliseconds;
              if (elapsedMs >= _progressThrottleMs) {
                final deltaBytes = totalReceived - lastBytes;
                final speed =
                    deltaBytes > 0 ? (deltaBytes * 1000.0) / elapsedMs : 0.0;
                lastBytes = totalReceived;
                lastTick = now;

                final progress = totalExpectedBytes > 0
                    ? (totalReceived / totalExpectedBytes).clamp(0.0, 1.0)
                    : 0.0;
                _downloadStates[modelId] = ModelDownloadState(
                  modelId: modelId,
                  modelName: targetModel.name,
                  progress: progress,
                  receivedBytes: totalReceived,
                  totalBytes: totalExpectedBytes,
                  speedBytesPerSec: speed,
                  isDownloading: true,
                  isPaused: false,
                  fileName: primarySafeFileName,
                  sourceUrl: resolvedSourceUrl,
                  quantization: resolvedQuant,
                  currentPartIndex: partIdx,
                  totalParts: downloadParts.length,
                  parts: downloadParts,
                  cancelToken: cancelToken,
                );
                onProgress?.call(progress);
                _syncDownloadNotifications();
                notifyListeners();
              }
            }
          }
        } finally {
          if (buffer.isNotEmpty) {
            await raf.writeFrom(buffer.takeBytes());
          }
          await raf.close();
        }

        if (!await partFile.exists()) {
          throw const FileSystemException('Downloaded file is missing on disk.');
        }

        // Only shard 1 contains the GGUF magic header; shards 2..N are raw tensor chunks.
        if (partIdx == 0) {
          final isValidGguf = await _hasGgufMagicHeader(partFile);
          if (!isValidGguf) {
            await partFile.delete();
            throw const FormatException(
              'Downloaded file is not a valid GGUF binary.',
            );
          }
        }

        if (await finalPartFile.exists()) {
          await finalPartFile.delete();
        }
        await partFile.rename(finalPartPath);
        activePartFilePath = null;

        completedBeforePart += await finalPartFile.length();
        completedPartPaths.add(finalPartPath);
        completedPartNames.add(safePartName);

        if (partIdx + 1 < downloadParts.length) {
          final progress = totalExpectedBytes > 0
              ? (completedBeforePart / totalExpectedBytes).clamp(0.0, 1.0)
              : (partIdx + 1) / downloadParts.length;
          _downloadStates[modelId] = ModelDownloadState(
            modelId: modelId,
            modelName: targetModel.name,
            progress: progress,
            receivedBytes: completedBeforePart,
            totalBytes: totalExpectedBytes,
            speedBytesPerSec: 0.0,
            isDownloading: true,
            isPaused: false,
            fileName: primarySafeFileName,
            sourceUrl: resolvedSourceUrl,
            quantization: resolvedQuant,
            currentPartIndex: partIdx + 1,
            totalParts: downloadParts.length,
            parts: downloadParts,
            cancelToken: cancelToken,
          );
          await _saveDownloadsState();
          onProgress?.call(progress);
          _syncDownloadNotifications();
          notifyListeners();
        }
      }

      return await _finalizePartFiles(
        modelId: modelId,
        targetModel: targetModel,
        finalPath: completedPartPaths.first,
        safeFileName: primarySafeFileName,
        totalSizeBytes: completedBeforePart,
        partFileNames: downloadParts.length > 1 ? completedPartNames : const [],
        quantization: resolvedQuant,
        sourceUrl: resolvedSourceUrl,
        onProgress: onProgress,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (_pauseRequestedIds.remove(modelId)) {
          final partFile =
              activePartFilePath != null ? File(activePartFilePath) : null;
          final diskBytes =
              partFile != null && await partFile.exists() ? await partFile.length() : 0;
          final totalDiskReceived = completedBeforePart + diskBytes;
          final progress = totalExpectedBytes > 0
              ? (totalDiskReceived / totalExpectedBytes).clamp(0.0, 1.0)
              : 0.0;
          _downloadStates[modelId] = ModelDownloadState(
            modelId: modelId,
            modelName: targetModel.name,
            progress: progress,
            receivedBytes: totalDiskReceived,
            totalBytes: totalExpectedBytes,
            isDownloading: false,
            isPaused: true,
            fileName: resolvedFileName,
            sourceUrl: resolvedSourceUrl,
            quantization: resolvedQuant,
            currentPartIndex: activePartIdx,
            totalParts: downloadParts.length,
            parts: downloadParts,
          );
          await _saveDownloadsState();
          _syncDownloadNotifications();
          notifyListeners();
          return null;
        }
        await _cleanupPartFile(activePartFilePath);
        await _cleanupCompletedSplitParts(completedPartPaths);
        _downloadStates.remove(modelId);
        _activeModelsById.remove(modelId);
        await _saveDownloadsState();
        _syncDownloadNotifications();
        unawaited(_notificationService.cancelNotification(modelId));
        notifyListeners();
        return null;
      }

      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403 || statusCode == 404) {
        await _cleanupPartFile(activePartFilePath);
        await _cleanupCompletedSplitParts(completedPartPaths);
      }
      final isGated = statusCode == 401 || statusCode == 403;
      String message;
      if (isGated) {
        message =
            'Access denied (HTTP $statusCode). This Hugging Face model may be gated.';
      } else if (statusCode == 404) {
        message = 'Model file not found on Hugging Face (HTTP 404).';
      } else {
        message = e.message ?? 'Network error during model download.';
      }
      _setDownloadError(modelId, message, isGatedError: isGated);
      return null;
    } catch (e) {
      await _cleanupPartFile(activePartFilePath);
      await _cleanupCompletedSplitParts(completedPartPaths);
      _setDownloadError(modelId, e.toString());
      return null;
    } finally {
      if (!downloadCompleter.isCompleted) {
        downloadCompleter.complete();
      }
      if (identical(_activeDownloadCompleters[modelId], downloadCompleter)) {
        _activeDownloadCompleters.remove(modelId);
      }
    }
  }

  Future<Response<ResponseBody>> _openDownloadStream({
    required String url,
    required int offsetBytes,
    required CancelToken cancelToken,
  }) {
    final headers = <String, dynamic>{};
    if (offsetBytes > 0) {
      headers['Range'] = 'bytes=$offsetBytes-';
    }
    final token = _storageService.hfToken;
    if (token != null && StorageService.isHuggingFaceHost(url)) {
      headers['Authorization'] = 'Bearer $token';
    }
    return _downloadDio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers.isEmpty ? null : headers,
        validateStatus: (status) =>
            status != null &&
            (status == 200 || status == 206 || status == 416),
      ),
    );
  }

  static int? _parseTotalFromContentRange(String? header) {
    if (header == null || !header.contains('/')) return null;
    final totalPart = header.split('/').last.trim();
    return int.tryParse(totalPart);
  }

  Future<void> _cleanupCompletedSplitParts(List<String> paths) async {
    for (final p in paths) {
      await _cleanupPartFile(p);
    }
  }

  Future<DownloadedModel> _finalizePartFiles({
    required String modelId,
    required OpenModel targetModel,
    required String finalPath,
    required String safeFileName,
    required int totalSizeBytes,
    required List<String> partFileNames,
    required String quantization,
    required String sourceUrl,
    void Function(double progress)? onProgress,
  }) async {
    final downloaded = DownloadedModel(
      modelId: modelId,
      name: targetModel.name,
      publisher: targetModel.publisher,
      fileName: safeFileName,
      filePath: finalPath,
      quantization: quantization,
      sizeBytes: totalSizeBytes,
      downloadedAt: DateTime.now(),
      sourceUrl: sourceUrl,
      partFileNames: partFileNames,
    );

    _downloadStates.remove(modelId);
    _activeModelsById.remove(modelId);
    _downloadedModels[modelId] = downloaded;
    await _saveIndex();
    await _saveDownloadsState();
    onProgress?.call(1.0);
    _syncDownloadNotifications();
    unawaited(_notificationService.cancelNotification(modelId));
    notifyListeners();
    return downloaded;
  }

  Future<void> cancelDownload(String modelId) async {
    final state = _downloadStates[modelId];
    if (state == null) return;
    _pauseRequestedIds.remove(modelId);
    if (state.isDownloading) {
      state.cancelToken?.cancel('Cancelled by user');
    }
    if (_storageService.isInitialized) {
      final sep = Platform.pathSeparator;
      if (state.parts.isNotEmpty) {
        for (final part in state.parts) {
          final safePart = _sanitizeFileName(part.fileName);
          await _cleanupPartFile('${_storageService.modelsPath}$sep$safePart.part');
          await _cleanupPartFile('${_storageService.modelsPath}$sep$safePart');
        }
      } else if (state.fileName != null) {
        await _cleanupPartFile(
          '${_storageService.modelsPath}$sep${state.fileName}.part',
        );
      }
    }
    _downloadStates.remove(modelId);
    _activeModelsById.remove(modelId);
    await _saveDownloadsState();
    _syncDownloadNotifications();
    unawaited(_notificationService.cancelNotification(modelId));
    notifyListeners();
  }

  void clearDownloadError(String modelId) {
    final state = _downloadStates[modelId];
    if (state != null && !state.isDownloading) {
      _downloadStates.remove(modelId);
      notifyListeners();
    }
  }

  Future<void> deleteDownloadedModel(String modelId) async {
    final entry = _downloadedModels[modelId];
    if (entry != null) {
      await onBeforeDeleteModel?.call(entry.filePath);
      final primaryFile = File(entry.filePath);
      final parentDir = primaryFile.parent.path;
      final sep = Platform.pathSeparator;
      for (final fname in entry.allFileNames) {
        await _cleanupPartFile('$parentDir$sep$fname');
      }
      if (await primaryFile.exists()) {
        await primaryFile.delete();
      }
      _downloadedModels.remove(modelId);
      if (modelId.startsWith('local:')) {
        _customModels.removeWhere((m) => m.id == modelId);
        _models.removeWhere((m) => m.id == modelId);
      }
      await _saveIndex();
      notifyListeners();
    }
  }

  Future<GgufVariant?> _resolveDownloadTarget(
    OpenModel model,
    GgufVariant? explicitVariant,
  ) async {
    if (explicitVariant != null && explicitVariant.downloadUrl.isNotEmpty) {
      return explicitVariant;
    }

    if (model.hasExactSizes && model.downloadUrl.isNotEmpty) {
      for (final v in model.variants) {
        if (v.downloadUrl == model.downloadUrl ||
            v.parts.any((p) => p.downloadUrl == model.downloadUrl)) {
          return v;
        }
      }
      if (_looksLikeDirectBinaryUrl(model.downloadUrl)) {
        return GgufVariant(
          fileName: _basename(model.downloadUrl),
          quantization: model.quantization,
          sizeBytes: model.downloadSizeMb > 0
              ? model.downloadSizeMb * 1024 * 1024
              : null,
          downloadUrl: model.downloadUrl,
        );
      }
    }

    final variants = await getVariantsForModel(model);
    if (variants.isNotEmpty) {
      return variants.first;
    }

    if (model.downloadUrl.isNotEmpty &&
        _looksLikeDirectBinaryUrl(model.downloadUrl)) {
      return GgufVariant(
        fileName: _basename(model.downloadUrl),
        quantization: model.quantization,
        sizeBytes: model.downloadSizeMb > 0
            ? model.downloadSizeMb * 1024 * 1024
            : null,
        downloadUrl: model.downloadUrl,
      );
    }
    return null;
  }

  bool _looksLikeDirectBinaryUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('huggingface.co/') &&
        !lower.contains('/resolve/') &&
        !lower.endsWith('.gguf') &&
        !lower.contains('.gguf?')) {
      return false;
    }
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  Future<bool> _hasGgufMagicHeader(File file) async {
    try {
      final length = await file.length();
      if (length < 4) return false;
      final raf = await file.open();
      try {
        final bytes = await raf.read(4);
        // GGUF magic bytes: 'G', 'G', 'U', 'F' (0x47, 0x47, 0x55, 0x46)
        return bytes.length == 4 &&
            bytes[0] == 0x47 &&
            bytes[1] == 0x47 &&
            bytes[2] == 0x55 &&
            bytes[3] == 0x46;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _cleanupPartFile(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  void _setDownloadError(
    String modelId,
    String message, {
    bool isGatedError = false,
  }) {
    _pauseRequestedIds.remove(modelId);
    final existingName =
        _downloadStates[modelId]?.modelName ??
        _activeModelsById[modelId]?.name ??
        _findModelById(modelId)?.name;
    _downloadStates[modelId] = ModelDownloadState(
      modelId: modelId,
      modelName: existingName,
      progress: 0.0,
      isDownloading: false,
      isGatedError: isGatedError,
      errorMessage: message,
    );
    unawaited(_saveDownloadsState());
    _syncDownloadNotifications();
    unawaited(_notificationService.cancelNotification(modelId));
    notifyListeners();
  }

  OpenModel? _findModelById(String modelId) {
    for (final m in _customModels) {
      if (m.id == modelId) return m;
    }
    for (final m in _models) {
      if (m.id == modelId) return m;
    }
    return _activeModelsById[modelId];
  }

  OpenModel? _openModelFromDownloadState(ModelDownloadState? state) {
    if (state == null) return null;
    final sourceUrl = state.sourceUrl;
    if (sourceUrl == null || sourceUrl.isEmpty) return null;
    final fileName = state.fileName ?? _basename(sourceUrl);
    final sizeMb = state.totalBytes > 0
        ? (state.totalBytes / (1024 * 1024)).round().clamp(1, 10000000)
        : 1;
    final publisher = state.modelId.contains('/')
        ? state.modelId.split('/').first
        : 'Resumed';
    final restoredVariants = state.parts.isNotEmpty
        ? [
            GgufVariant(
              fileName: fileName,
              quantization:
                  state.quantization ?? _extractQuantFromFileName(fileName),
              sizeBytes: state.totalBytes > 0 ? state.totalBytes : null,
              downloadUrl: sourceUrl,
              parts: state.parts,
              expectedParts: state.totalParts,
            ),
          ]
        : const <GgufVariant>[];
    return OpenModel(
      id: state.modelId,
      name: state.modelName ?? fileName,
      publisher: publisher,
      parameterSizeB: '1.0',
      format: 'GGUF',
      quantization: state.quantization ?? _extractQuantFromFileName(fileName),
      downloadSizeMb: sizeMb,
      minRamGb: (((sizeMb / 1024) * 1.5).ceil() + 1).clamp(2, 2048),
      downloadUrl: sourceUrl,
      description: 'Resumable model download (${state.fileName ?? fileName}).',
      repoUrl: sourceUrl,
      variants: restoredVariants,
    );
  }

  static String _basename(String pathOrUrl) {
    final clean = pathOrUrl.split('?').first;
    final parts = clean.split(RegExp(r'[/\\]'));
    return parts.isNotEmpty ? parts.last : clean;
  }

  static String _sanitizeFileName(String raw) {
    final base = _basename(Uri.decodeComponent(raw));
    final cleaned = base.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (cleaned.isEmpty) return 'model.gguf';
    if (!cleaned.toLowerCase().endsWith('.gguf')) {
      return '$cleaned.gguf';
    }
    return cleaned;
  }

  static String _extractQuantFromFileName(String fileName) {
    final m = RegExp(
      r'(Q[0-9]_[A-Z0-9_]+|IQ[0-9]_[A-Z0-9_]+|FP16|BF16)',
      caseSensitive: false,
    ).firstMatch(fileName);
    return m != null ? m.group(1)!.toUpperCase() : 'GGUF';
  }
}
