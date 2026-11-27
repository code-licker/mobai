import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/hf_url_parser.dart';
import 'package:mobai/services/storage_service.dart';

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
    int limit = 100,
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
    int limit = 100,
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

  Options? _hfAuthOptionsForUrl(String url) {
    final token = StorageService().hfToken;
    if (token != null && StorageService.isHuggingFaceHost(url)) {
      return Options(headers: {'Authorization': 'Bearer $token'});
    }
    return null;
  }

  Options _hfRequestOptions(String url, {bool multiList = false}) {
    final auth = _hfAuthOptionsForUrl(url);
    return Options(
      headers: auth?.headers,
      listFormat: multiList ? ListFormat.multi : null,
    );
  }

  Future<ModelCatalogPage> _fetchModelsPageFromHuggingFace({
    String? searchQuery,
    ModelSortOption sortOption = ModelSortOption.popular,
    String? pageUrl,
    int limit = 100,
  }) async {
    final Response<dynamic> response;
    if (pageUrl != null && pageUrl.isNotEmpty) {
      response = await _dio.get(pageUrl, options: _hfAuthOptionsForUrl(pageUrl));
    } else {
      final serverSort =
          sortOption == ModelSortOption.latest ? 'createdAt' : 'downloads';
      final Map<String, dynamic> queryParams = {
        'filter': 'gguf',
        'pipeline_tag': 'text-generation',
        'sort': serverSort,
        'direction': -1,
        'limit': limit,
        'expand[]': const [
          'author',
          'baseModels',
          'cardData',
          'createdAt',
          'downloads',
          'gated',
          'gguf',
          'likes',
          'safetensors',
          'siblings',
          'tags',
        ],
      };

      if (searchQuery != null && searchQuery.isNotEmpty) {
        queryParams['search'] = searchQuery;
      }

      response = await _dio.get(
        apiBaseUrl,
        queryParameters: queryParams,
        options: _hfRequestOptions(apiBaseUrl, multiList: true),
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

  /// Fetches and parses a human-readable model description from the
  /// Hugging Face repository's `README.md`.
  Future<String?> fetchModelDescription(String repoId) async {
    final cleanRepo = repoId.trim();
    if (cleanRepo.isEmpty || !cleanRepo.contains('/')) return null;

    final baseUri = Uri.tryParse(apiBaseUrl);
    final origin = (baseUri != null && baseUri.hasScheme && baseUri.host.isNotEmpty)
        ? '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}'
        : 'https://huggingface.co';
    final readmeUrl = '$origin/$cleanRepo/raw/main/README.md';

    try {
      final auth = _hfAuthOptionsForUrl(readmeUrl);
      final response = await _dio.get<String>(
        readmeUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: auth?.headers,
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final raw = response.data;
      if (raw == null || raw.trim().isEmpty) return null;
      return parseReadmeDescription(raw);
    } catch (_) {
      return null;
    }
  }

  /// Strips YAML frontmatter, HTML badges/tags, and Markdown syntax from a
  /// Hugging Face `README.md` into readable prose for catalog cards and details.
  static String? parseReadmeDescription(String rawMarkdown) {
    var text = rawMarkdown;
    // Strip YAML frontmatter at top of README.md
    text = text.replaceFirst(
      RegExp(r'^\s*---\s*\r?\n[\s\S]*?\r?\n---\s*(?:\r?\n|$)'),
      '',
    );
    // Strip HTML comments, <style>, <script>, and image/media blocks
    text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    text = text.replaceAll(
      RegExp(r'<(style|script|picture)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
      '',
    );
    // Replace list items / line breaks cleanly before stripping HTML tags
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(
      RegExp(r'</(p|div|li|tr|h[1-6])>', caseSensitive: false),
      '\n',
    );
    text = text.replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ');
    // Strip Markdown linked badges [![alt](img)](link) and standalone images ![alt](img)
    text = text.replaceAll(RegExp(r'\[!\[[^\]]*\]\([^\)]*\)\]\([^\)]*\)'), '');
    text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^\)]*\)'), '');
    // Convert Markdown links [label](url) -> label
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^\)]+\)'),
      (m) => m.group(1) ?? '',
    );
    // Strip any remaining HTML tags
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    // Decode common HTML entities
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&middot;', '•')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    final lines = text.split(RegExp(r'\r?\n'));
    final cleanedLines = <String>[];
    for (final rawLine in lines) {
      var line = rawLine.trim();
      if (line.isEmpty) {
        if (cleanedLines.isNotEmpty && cleanedLines.last.isNotEmpty) {
          cleanedLines.add('');
        }
        continue;
      }
      // Skip Markdown horizontal rules and table divider rows (| --- | --- |)
      if (RegExp(r'^[-*_=\s|]+$').hasMatch(line)) continue;
      if (line.startsWith('|') && line.endsWith('|')) continue;
      // Strip leading blockquote / heading hashes / bold markers
      line = line.replaceFirst(RegExp(r'^[>#\s]+'), '');
      line = line.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
      line = line.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      if (line.isEmpty) continue;
      cleanedLines.add(line);
    }

    final joined = cleanedLines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (joined.isEmpty) return null;
    if (joined.length > 3500) {
      return '${joined.substring(0, 3500).trimRight()}...';
    }
    return joined;
  }

  /// Fetches available `.gguf` files and sizes for a Hugging Face repository.
  Future<List<GgufVariant>> fetchRepoGgufVariants(String repoId) async {
    final cleanRepo = repoId.trim();
    if (cleanRepo.isEmpty) return const [];
    final response = await _dio.get(
      '$apiBaseUrl/$cleanRepo',
      queryParameters: const {'blobs': true},
      options: _hfAuthOptionsForUrl(apiBaseUrl),
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
          options: _hfAuthOptionsForUrl(apiBaseUrl),
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
              v.fileName.split('/').last.toLowerCase() == targetLower ||
              v.parts.any(
                (p) =>
                    p.fileName.toLowerCase() == targetLower ||
                    p.fileName.split('/').last.toLowerCase() == targetLower,
              ),
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
            resolvedSizeMb = (headSize / (1024 * 1024)).round().clamp(1, 10000000);
          }
        }

        final quant = variant?.quantization ??
            HfUrlParser.extractQuantization(parsed.fileName!);
        final resolvedUrl = (variant != null && variant.downloadUrl.isNotEmpty)
            ? variant.downloadUrl
            : parsed.directDownloadUrl!;
        final reorderedVariants = variant != null
            ? [
                variant,
                ...baseModel.variants.where((v) => v != variant),
              ]
            : baseModel.variants;
        return baseModel.copyWith(
          downloadUrl: resolvedUrl,
          quantization: quant,
          downloadSizeMb: resolvedSizeMb,
          minRamGb: (((resolvedSizeMb / 1024) * 1.5).ceil() + 1).clamp(2, 2048),
          variants: reorderedVariants,
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
