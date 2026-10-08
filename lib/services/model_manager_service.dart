import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mobai/models/model_filter_criteria.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/model_catalog_service.dart';

class ModelManagerService extends ChangeNotifier {
  static final ModelManagerService _instance = ModelManagerService._internal();
  factory ModelManagerService() => _instance;
  ModelManagerService._internal();

  final ModelCatalogService _catalogService = ModelCatalogService();

  List<OpenModel> _models = [];
  final List<OpenModel> _customModels = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  ModelFilterCriteria _filterCriteria = ModelFilterCriteria.initial();

  // Set of downloaded model IDs
  final Set<String> _downloadedModelIds = {'qwen2.5-0.5b-instruct-q4'};

  // Progress for downloading models: modelId -> progress (0.0 to 1.0)
  final Map<String, double> _downloadProgress = {};

  List<OpenModel> get models => List.unmodifiable(_models);

  List<OpenModel> get filteredModels {
    return _models.where((m) => _filterCriteria.matches(m)).toList();
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  ModelFilterCriteria get filterCriteria => _filterCriteria;

  List<String> get availableProviders {
    final providers = <String>{};
    for (final m in _models) {
      if (m.publisher.isNotEmpty) {
        providers.add(m.publisher);
      }
    }
    final sorted = providers.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  bool isModelDownloaded(String modelId) => _downloadedModelIds.contains(modelId);
  bool isModelDownloading(String modelId) => _downloadProgress.containsKey(modelId);
  double getDownloadProgress(String modelId) => _downloadProgress[modelId] ?? 0.0;

  Future<void> loadModels() async {
    await searchModels('');
  }

  Future<void> searchModels(String query) async {
    _searchQuery = query.trim();
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final fetched = await _catalogService.fetchModels(
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

      // Preserve custom user-added models that match query
      final relevantCustom = _customModels.where((c) {
        if (_searchQuery.isEmpty) return true;
        return c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            c.publisher.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            c.id.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();

      _models = [...relevantCustom, ...fetched];
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
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
    if (!_customModels.any((m) => m.id == model.id)) {
      _customModels.insert(0, model);
      if (!_models.any((m) => m.id == model.id)) {
        _models = [model, ..._models];
      }
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

    // Stepped download simulation
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
