import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/hf_url_parser.dart';

enum ModelSortOption {
  popular('Popular'),
  latest('Latest'),
  sizeAsc('Smallest size'),
  sizeDesc('Largest size'),
  paramsAsc('Smallest params'),
  paramsDesc('Largest params');

  final String label;
  const ModelSortOption(this.label);
}

class ModelCatalogPage {
  final List<OpenModel> models;
  final String? nextPageUrl;

  const ModelCatalogPage({
    required this.models,
    this.nextPageUrl,
  });
}

class ModelCatalogService {
  static const String _huggingFaceApiUrl = "https://huggingface.co/api/models";
  static const String _localAssetPath = "assets/json/supported_models.json";

  final String apiBaseUrl;
  final Dio _dio;

  ModelCatalogService({
    Dio? dio,
    this.apiBaseUrl = _huggingFaceApiUrl,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 10),
               headers: {'User-Agent': 'MobAI-App/1.0.0'},
             ),
           );

  /// Fetches a single page of text-generation GGUF models from Hugging Face
  /// (or follows a `Link` rel="next" cursor URL in [pageUrl]).
  Future<ModelCatalogPage> fetchModelsPage({
    String? searchQuery,
    ModelSortOption sortOption = ModelSortOption.popular,
    String? pageUrl,
    int limit = 35,
  }) async {
    try {
      return await _fetchModelsPageFromHuggingFace(
        searchQuery: searchQuery?.trim(),
        sortOption: sortOption,
        pageUrl: pageUrl,
        limit: limit,
      );
    } catch (e) {
      if ((searchQuery != null && searchQuery.trim().isNotEmpty) ||
          pageUrl != null) {
        rethrow;
      }
      final fallback = await _fetchModelsFromLocal();
      return ModelCatalogPage(models: fallback);
    }
  }

  /// Fetches models directly from Hugging Face API.
  /// If [searchQuery] is provided, searches models matching the query on Hugging Face.
  /// Falls back to local bundled models only if offline and no query was specified.
  Future<List<OpenModel>> fetchModels({
    String? searchQuery,
    ModelSortOption sortOption = ModelSortOption.popular,
    int limit = 35,
  }) async {
    final page = await fetchModelsPage(
      searchQuery: searchQuery,
      sortOption: sortOption,
      limit: limit,
    );
    return page.models;
  }

  static String? parseNextLinkHeader(Headers headers) {
    final linkValues = headers['link'] ?? headers['Link'];
    if (linkValues == null || linkValues.isEmpty) return null;
    final joined = linkValues.join(', ');
    final match = RegExp(
      r'<([^>]+)>\s*;\s*rel="?next"?',
      caseSensitive: false,
    ).firstMatch(joined);
    return match?.group(1);
  }

  Future<ModelCatalogPage> _fetchModelsPageFromHuggingFace({
    String? searchQuery,
    ModelSortOption sortOption = ModelSortOption.popular,
    String? pageUrl,
    int limit = 35,
  }) async {
    final Response<dynamic> response;
    if (pageUrl != null && pageUrl.isNotEmpty) {
      response = await _dio.get(pageUrl);
    } else {
      final serverSort =
          sortOption == ModelSortOption.latest ? 'createdAt' : 'downloads';
      final Map<String, dynamic> queryParams = {
        'filter': 'gguf',
        'pipeline_tag': 'text-generation',
        'sort': serverSort,
        'direction': -1,
        'limit': limit,
        'full': true,
      };

      if (searchQuery != null && searchQuery.isNotEmpty) {
        queryParams['search'] = searchQuery;
      }

      response = await _dio.get(
        apiBaseUrl,
        queryParameters: queryParams,
      );
    }

    if (response.statusCode == 200) {
      final dynamic rawData = response.data;
      final List<dynamic> data = rawData is String ? jsonDecode(rawData) : rawData;

      final models = <OpenModel>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          try {
            final model = OpenModel.fromHuggingFace(item);
            if (model.id.isNotEmpty) {
              models.add(model);
            }
          } catch (_) {
            // Ignore single malformed entry and continue
          }
        }
      }
      return ModelCatalogPage(
        models: models,
        nextPageUrl: parseNextLinkHeader(response.headers),
      );
    } else {
      throw Exception(
        'Failed to load models from Hugging Face (Status: ${response.statusCode})',
      );
    }
  }

  /// Fetches available `.gguf` files and sizes for a Hugging Face repository.
  Future<List<GgufVariant>> fetchRepoGgufVariants(String repoId) async {
    final cleanRepo = repoId.trim();
    if (cleanRepo.isEmpty) return const [];
    final response = await _dio.get(
      '$apiBaseUrl/$cleanRepo',
      queryParameters: const {'blobs': true},
    );
    if (response.statusCode == 200) {
      final dynamic rawData = response.data;
      final Map<String, dynamic> data = rawData is String
          ? jsonDecode(rawData) as Map<String, dynamic>
          : rawData as Map<String, dynamic>;
      return OpenModel.parseGgufVariantsFromSiblings(cleanRepo, data['siblings']);
    }
    throw Exception(
      'Failed to inspect repository $cleanRepo (Status: ${response.statusCode})',
    );
  }

  /// Resolves metadata and `.gguf` variants from a custom Hugging Face or
  /// direct `.gguf` download URL.
  Future<OpenModel> resolveCustomModelFromUrl(String rawUrl) async {
    final parsed = HfUrlParser.parse(rawUrl);

    if (parsed.isHuggingFace && parsed.repoId != null) {
      final repoId = parsed.repoId!;
      OpenModel baseModel;
      try {
        final response = await _dio.get(
          '$apiBaseUrl/$repoId',
          queryParameters: const {'blobs': true},
        );
        if (response.statusCode == 200) {
          final dynamic rawData = response.data;
          final Map<String, dynamic> data = rawData is String
              ? jsonDecode(rawData) as Map<String, dynamic>
              : rawData as Map<String, dynamic>;
          baseModel = OpenModel.fromHuggingFace(data);
        } else {
          baseModel = _fallbackModelFromParsed(parsed);
        }
      } catch (_) {
        baseModel = _fallbackModelFromParsed(parsed);
      }

      if (parsed.hasDirectFile && parsed.fileName != null) {
        final targetLower = parsed.fileName!.toLowerCase();
        final matchedVariant = baseModel.variants.where(
          (v) =>
              v.fileName.toLowerCase() == targetLower ||
              v.fileName.split('/').last.toLowerCase() == targetLower,
        );
        final variant = matchedVariant.isNotEmpty ? matchedVariant.first : null;

        int resolvedSizeMb = variant != null && variant.sizeMb > 0
            ? variant.sizeMb
            : baseModel.downloadSizeMb;
        if (variant == null || variant.sizeBytes == null) {
          final headSize = await _probeHeadContentLength(
            parsed.directDownloadUrl!,
          );
          if (headSize != null && headSize > 0) {
            resolvedSizeMb = (headSize / (1024 * 1024)).round().clamp(1, 100000);
          }
        }

        final quant = variant?.quantization ??
            HfUrlParser.extractQuantization(parsed.fileName!);
        return baseModel.copyWith(
          downloadUrl: parsed.directDownloadUrl,
          quantization: quant,
          downloadSizeMb: resolvedSizeMb,
          minRamGb: ((resolvedSizeMb / 1024) * 1.5).ceil().clamp(2, 64),
        );
      }

      return baseModel;
    }

    // Direct non-Hugging Face HTTP(S) URL
    final directUrl = parsed.directDownloadUrl ?? parsed.originalUrl;
    final headBytes = await _probeHeadContentLength(directUrl);
    final sizeMb = headBytes != null && headBytes > 0
        ? (headBytes / (1024 * 1024)).round().clamp(1, 100000)
        : 500;
    final fileName = parsed.fileName ?? 'model.gguf';
    final quant = HfUrlParser.extractQuantization(fileName);

    return OpenModel(
      id: 'custom-${directUrl.hashCode.abs()}',
      name: HfUrlParser.inferDisplayName(fileName: fileName),
      publisher: 'Custom',
      parameterSizeB: '1.0',
      format: 'GGUF',
      quantization: quant,
      downloadSizeMb: sizeMb,
      minRamGb: ((sizeMb / 1024) * 1.5).ceil().clamp(2, 64),
      downloadUrl: directUrl,
      description: 'Custom model imported from URL.',
      repoUrl: parsed.repoUrl ?? directUrl,
    );
  }

  OpenModel _fallbackModelFromParsed(ParsedModelUrl parsed) {
    final repoId = parsed.repoId ?? 'custom/model';
    final parts = repoId.split('/');
    final author = parts.isNotEmpty ? parts[0] : 'Community';
    final fileName = parsed.fileName;
    final name = HfUrlParser.inferDisplayName(
      fileName: fileName,
      repoId: repoId,
    );
    final quant = fileName != null
        ? HfUrlParser.extractQuantization(fileName)
        : 'Q4_K_M';

    return OpenModel(
      id: repoId,
      name: name,
      publisher: author,
      parameterSizeB: '1.0',
      format: 'GGUF',
      quantization: quant,
      downloadSizeMb: 500,
      minRamGb: 4,
      downloadUrl: parsed.directDownloadUrl ?? '',
      description: 'Custom Hugging Face model ($repoId).',
      repoUrl: parsed.repoUrl ?? 'https://huggingface.co/$repoId',
    );
  }

  Future<int?> _probeHeadContentLength(String url) async {
    try {
      final response = await _dio.head<void>(
        url,
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final raw = response.headers.value(Headers.contentLengthHeader);
      return raw != null ? int.tryParse(raw) : null;
    } catch (_) {
      return null;
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
