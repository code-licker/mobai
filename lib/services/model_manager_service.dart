import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobai/models/downloaded_model.dart';
import 'package:mobai/models/model_filter_criteria.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/model_catalog_service.dart';
import 'package:mobai/services/storage_service.dart';

class ModelDownloadState {
  final String modelId;
  final double progress;
  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSec;
  final bool isDownloading;
  final String? errorMessage;
  final CancelToken? cancelToken;

  const ModelDownloadState({
    required this.modelId,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.isDownloading = false,
    this.errorMessage,
    this.cancelToken,
  });

  ModelDownloadState copyWith({
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    double? speedBytesPerSec,
    bool? isDownloading,
    String? errorMessage,
    bool clearError = false,
    CancelToken? cancelToken,
  }) {
    return ModelDownloadState(
      modelId: modelId,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      isDownloading: isDownloading ?? this.isDownloading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
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

  ModelCatalogService _catalogService = ModelCatalogService();
  final StorageService _storageService = StorageService();
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

  // Active and errored download states by modelId
  final Map<String, ModelDownloadState> _downloadStates = {};

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
                _downloadedModels[entry.modelId] = entry;
                trackedPaths.add(File(entry.filePath).absolute.path);
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
        final matchedCatalogModel = _findCatalogModelByFileName(fileName);
        final sizeBytes = await entity.length();
        final quant = _extractQuantFromFileName(fileName);
        final modelId = matchedCatalogModel?.id ?? 'local:$fileName';
        final cleanName = matchedCatalogModel?.name ??
            fileName
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
          sizeBytes: sizeBytes,
          downloadedAt: await entity.lastModified(),
          sourceUrl: matchedCatalogModel?.downloadUrl ?? '',
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
    notifyListeners();
  }

  OpenModel _openModelFromDownloaded(DownloadedModel entry) {
    final sizeMb = (entry.sizeBytes / (1024 * 1024)).round().clamp(1, 100000);
    return OpenModel(
      id: entry.modelId,
      name: entry.name,
      publisher: entry.publisher,
      parameterSizeB: '1.0',
      format: 'GGUF',
      quantization: entry.quantization,
      downloadSizeMb: sizeMb,
      minRamGb: ((sizeMb / 1024) * 1.5).ceil().clamp(2, 64),
      downloadUrl: entry.sourceUrl,
      description: 'Local GGUF model stored in MobAI/models (${entry.fileName}).',
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
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
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

  void togglePhoneReadyOnly() {
    _filterCriteria = _filterCriteria.copyWith(
      phoneReadyOnly: !_filterCriteria.phoneReadyOnly,
    );
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
  /// from Hugging Face if [model.variants] is empty.
  Future<List<GgufVariant>> getVariantsForModel(OpenModel model) async {
    if (model.variants.isNotEmpty) return model.variants;
    final isHuggingFaceRepo =
        model.repoUrl.contains('huggingface.co') &&
        !model.id.startsWith('local:') &&
        model.id.contains('/');
    if (!isHuggingFaceRepo) {
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

    final fetched = await _catalogService.fetchRepoGgufVariants(model.id);
    if (fetched.isNotEmpty) {
      final idx = _models.indexWhere((m) => m.id == model.id);
      if (idx != -1) {
        final primary = fetched.first;
        _models[idx] = _models[idx].copyWith(
          variants: fetched,
          downloadUrl: primary.downloadUrl,
          quantization: primary.quantization,
          downloadSizeMb: primary.sizeMb > 0
              ? primary.sizeMb
              : _models[idx].downloadSizeMb,
        );
        notifyListeners();
      }
    }
    return fetched;
  }

  /// Downloads a model `.gguf` into `MobAI/models/`.
  /// Accepts either [model] directly or resolves it from [modelId].
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

    final targetModel = model ?? _findModelById(modelId);
    if (targetModel == null) {
      _setDownloadError(modelId, 'Model metadata not found.');
      return null;
    }

    if (!_storageService.isInitialized) {
      await _storageService.init();
    }

    final cancelToken = CancelToken();
    _downloadStates[modelId] = ModelDownloadState(
      modelId: modelId,
      progress: 0.0,
      isDownloading: true,
      cancelToken: cancelToken,
    );
    notifyListeners();

    String? partFilePath;
    try {
      final resolved = await _resolveDownloadTarget(targetModel, variant);
      if (resolved == null) {
        _setDownloadError(
          modelId,
          'No downloadable .gguf file found for ${targetModel.name}.',
        );
        return null;
      }

      final safeFileName = _sanitizeFileName(resolved.fileName);
      final modelsDir = _storageService.modelsDirectory;
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final finalPath =
          '${modelsDir.path}${Platform.pathSeparator}$safeFileName';
      partFilePath = '$finalPath.part';

      final partFile = File(partFilePath);
      if (await partFile.exists()) {
        await partFile.delete();
      }

      int lastBytes = 0;
      DateTime lastTick = DateTime.now();

      final response = await _downloadDio.download(
        resolved.downloadUrl,
        partFilePath,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          final effectiveTotal = total > 0
              ? total
              : (resolved.sizeBytes ?? targetModel.downloadSizeMb * 1024 * 1024);
          final progress = effectiveTotal > 0
              ? (received / effectiveTotal).clamp(0.0, 1.0)
              : 0.0;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastTick).inMilliseconds;
          double speed = _downloadStates[modelId]?.speedBytesPerSec ?? 0.0;
          if (elapsedMs >= 300) {
            final deltaBytes = received - lastBytes;
            speed = deltaBytes > 0 ? (deltaBytes * 1000.0) / elapsedMs : 0.0;
            lastBytes = received;
            lastTick = now;
          }

          _downloadStates[modelId] = ModelDownloadState(
            modelId: modelId,
            progress: progress,
            receivedBytes: received,
            totalBytes: effectiveTotal,
            speedBytesPerSec: speed,
            isDownloading: true,
            cancelToken: cancelToken,
          );
          onProgress?.call(progress);
          notifyListeners();
        },
      );

      final contentType =
          response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
      if (contentType.contains('text/html')) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message:
              'Hugging Face returned a web page instead of a GGUF binary (the model may be gated or require authentication).',
        );
      }

      if (!await partFile.exists()) {
        throw const FileSystemException('Downloaded file is missing on disk.');
      }

      final isValidGguf = await _hasGgufMagicHeader(partFile);
      if (!isValidGguf) {
        await partFile.delete();
        throw const FormatException(
          'Downloaded file is not a valid GGUF binary.',
        );
      }

      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(finalPath);

      final actualSize = await finalFile.length();
      final downloaded = DownloadedModel(
        modelId: modelId,
        name: targetModel.name,
        publisher: targetModel.publisher,
        fileName: safeFileName,
        filePath: finalPath,
        quantization: resolved.quantization,
        sizeBytes: actualSize,
        downloadedAt: DateTime.now(),
        sourceUrl: resolved.downloadUrl,
      );

      _downloadStates.remove(modelId);
      _downloadedModels[modelId] = downloaded;
      await _saveIndex();
      onProgress?.call(1.0);
      notifyListeners();
      return downloaded;
    } on DioException catch (e) {
      await _cleanupPartFile(partFilePath);
      if (CancelToken.isCancel(e)) {
        _downloadStates.remove(modelId);
        notifyListeners();
        return null;
      }
      final statusCode = e.response?.statusCode;
      String message;
      if (statusCode == 401 || statusCode == 403) {
        message =
            'Access denied (HTTP $statusCode). This Hugging Face model may be gated.';
      } else if (statusCode == 404) {
        message = 'Model file not found on Hugging Face (HTTP 404).';
      } else {
        message = e.message ?? 'Network error during model download.';
      }
      _setDownloadError(modelId, message);
      return null;
    } catch (e) {
      await _cleanupPartFile(partFilePath);
      _setDownloadError(modelId, e.toString());
      return null;
    }
  }

  Future<void> cancelDownload(String modelId) async {
    final state = _downloadStates[modelId];
    if (state == null) return;
    state.cancelToken?.cancel('Cancelled by user');
    _downloadStates.remove(modelId);
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
      final file = File(entry.filePath);
      if (await file.exists()) {
        await file.delete();
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

    final variants = await getVariantsForModel(model);
    if (variants.isNotEmpty) {
      return variants.first;
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

  void _setDownloadError(String modelId, String message) {
    _downloadStates[modelId] = ModelDownloadState(
      modelId: modelId,
      progress: 0.0,
      isDownloading: false,
      errorMessage: message,
    );
    notifyListeners();
  }

  OpenModel? _findModelById(String modelId) {
    for (final m in _customModels) {
      if (m.id == modelId) return m;
    }
    for (final m in _models) {
      if (m.id == modelId) return m;
    }
    return null;
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
