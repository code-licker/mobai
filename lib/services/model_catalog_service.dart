import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:mobai/models/open_model.dart';

class ModelCatalogService {
  static const String _primaryRemoteUrl =
      "https://raw.githubusercontent.com/code-licker/open-weight-models/refs/heads/master/models.json";
  static const String _fallbackRemoteUrl =
      "https://raw.githubusercontent.com/code-licker/open-weight-models/refs/heads/master/models_f.json";
  static const String _localAssetPath = "assets/json/supported_models.json";

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  Future<List<OpenModel>> fetchModels() async {
    try {
      return await _fetchModelsFromRemote(_primaryRemoteUrl);
    } catch (e) {
      try {
        return await _fetchModelsFromRemote(_fallbackRemoteUrl);
      } catch (_) {
        return await _fetchModelsFromLocal();
      }
    }
  }

  Future<List<OpenModel>> _fetchModelsFromRemote(String url) async {
    final response = await _dio.get(url);
    if (response.statusCode == 200) {
      final dynamic rawData = response.data;
      final List<dynamic> data = rawData is String ? jsonDecode(rawData) : rawData;
      return data.map((e) => OpenModel.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to load models (Status: ${response.statusCode})');
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
