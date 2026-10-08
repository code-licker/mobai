import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/model_catalog_service.dart';

class ModelManagerService extends ChangeNotifier {
  static final ModelManagerService _instance = ModelManagerService._internal();
  factory ModelManagerService() => _instance;
  ModelManagerService._internal();

  final ModelCatalogService _catalogService = ModelCatalogService();

  List<OpenModel> _models = [];
  bool _isLoading = false;
  String? _error;

  // Set of downloaded model IDs
  final Set<String> _downloadedModelIds = {'qwen2.5-0.5b-instruct-q4'};

  // Progress for downloading models: modelId -> progress (0.0 to 1.0)
  final Map<String, double> _downloadProgress = {};

  List<OpenModel> get models => List.unmodifiable(_models);
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool isModelDownloaded(String modelId) => _downloadedModelIds.contains(modelId);
  bool isModelDownloading(String modelId) => _downloadProgress.containsKey(modelId);
  double getDownloadProgress(String modelId) => _downloadProgress[modelId] ?? 0.0;

  Future<void> loadModels() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final fetched = await _catalogService.fetchModels();
      // Keep any user-added models that aren't in fetched
      final existingCustom = _models.where((m) => !fetched.any((f) => f.id == m.id)).toList();
      _models = [...fetched, ...existingCustom];
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addCustomModel(OpenModel model) {
    if (!_models.any((m) => m.id == model.id)) {
      _models = [model, ..._models];
      notifyListeners();
    }
  }

  Future<void> downloadModel(String modelId, {void Function(double progress)? onProgress}) async {
    if (_downloadedModelIds.contains(modelId)) {
      onProgress?.call(1.0);
      return;
    }

    _downloadProgress[modelId] = 0.05;
    notifyListeners();
    onProgress?.call(0.05);

    // Realistic stepped download simulation
    final steps = [0.15, 0.32, 0.54, 0.73, 0.88, 0.96, 1.0];
    for (final step in steps) {
      await Future.delayed(const Duration(milliseconds: 350));
      _downloadProgress[modelId] = step;
      onProgress?.call(step);
      notifyListeners();
    }

    _downloadProgress.remove(modelId);
    _downloadedModelIds.add(modelId);
    notifyListeners();
  }

  void deleteDownloadedModel(String modelId) {
    _downloadedModelIds.remove(modelId);
    notifyListeners();
  }
}
