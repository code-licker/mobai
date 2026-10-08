import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:mobai/models/open_model.dart';

class ModelCatalogService {
  static const String _huggingFaceApiUrl = "https://huggingface.co/api/models";
  static const String _localAssetPath = "assets/json/supported_models.json";

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': 'MobAI-App/1.0.0',
    },
  ));

  /// Fetches models directly from Hugging Face API.
  /// If [searchQuery] is provided, searches models matching the query on Hugging Face.
  /// Falls back to local bundled models only if offline and no query was specified.
  Future<List<OpenModel>> fetchModels({String? searchQuery, int limit = 35}) async {
    try {
      return await _fetchModelsFromHuggingFace(
        searchQuery: searchQuery?.trim(),
        limit: limit,
      );
    } catch (e) {
      // If user performed an active search, rethrow so the UI can show the search error
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        rethrow;
      }
      // For initial catalog load when offline, fallback to local asset
      return await _fetchModelsFromLocal();
    }
  }

  Future<List<OpenModel>> _fetchModelsFromHuggingFace({
    String? searchQuery,
    int limit = 35,
  }) async {
    final Map<String, dynamic> queryParams = {
      'filter': 'gguf',
      'sort': 'downloads',
      'direction': -1,
      'limit': limit,
      'full': true,
    };

    if (searchQuery != null && searchQuery.isNotEmpty) {
      queryParams['search'] = searchQuery;
    }

    final response = await _dio.get(
      _huggingFaceApiUrl,
      queryParameters: queryParams,
    );

    if (response.statusCode == 200) {
      final dynamic rawData = response.data;
      final List<dynamic> data = rawData is String ? jsonDecode(rawData) : rawData;

      final models = <OpenModel>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          try {
            final model = OpenModel.fromHuggingFace(item);
            // Ensure valid model with an id
            if (model.id.isNotEmpty) {
              models.add(model);
            }
          } catch (_) {
            // Ignore single malformed entry and continue
          }
        }
      }
      return models;
    } else {
      throw Exception('Failed to load models from Hugging Face (Status: ${response.statusCode})');
    }
  }

  Future<List<OpenModel>> _fetchModelsFromLocal() async {
    try {
      final jsonString = await rootBundle.loadString(_localAssetPath);
      final List<dynamic> data = jsonDecode(jsonString);
      return data.map((e) => OpenModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw Exception('Failed to load local models: $e');
    }
  }
}
