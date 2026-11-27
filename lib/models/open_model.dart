class SplitShardInfo {
  final String prefix;
  final int partNumber;
  final int totalParts;

  const SplitShardInfo({
    required this.prefix,
    required this.partNumber,
    required this.totalParts,
  });
}

class GgufPart {
  final String fileName;
  final int partNumber;
  final int? sizeBytes;
  final String downloadUrl;

  const GgufPart({
    required this.fileName,
    required this.partNumber,
    this.sizeBytes,
    required this.downloadUrl,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'partNumber': partNumber,
    'sizeBytes': sizeBytes,
    'downloadUrl': downloadUrl,
  };

  factory GgufPart.fromJson(Map<String, dynamic> json) {
    return GgufPart(
      fileName: (json['fileName'] ?? '').toString(),
      partNumber: (json['partNumber'] as num?)?.toInt() ?? 1,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
    );
  }
}

class GgufVariant {
  final String fileName;
  final String quantization;
  final int? sizeBytes;
  final String downloadUrl;
  final bool isAuxiliary;
  final List<GgufPart> parts;
  final int expectedParts;

  const GgufVariant({
    required this.fileName,
    required this.quantization,
    this.sizeBytes,
    required this.downloadUrl,
    this.isAuxiliary = false,
    this.parts = const [],
    this.expectedParts = 1,
  });

  int get sizeMb =>
      sizeBytes != null ? (sizeBytes! / (1024 * 1024)).round() : 0;

  bool get isSplit => expectedParts > 1 || parts.length > 1;

  int get partCount => expectedParts > parts.length
      ? expectedParts
      : (parts.isNotEmpty ? parts.length : 1);

  bool get hasMissingParts => parts.isNotEmpty && parts.length < partCount;

  /// Ordered shard parts to download (1-element fallback for single-file GGUFs).
  List<GgufPart> get resolvedParts => parts.isNotEmpty
      ? parts
      : [
          GgufPart(
            fileName: fileName,
            partNumber: 1,
            sizeBytes: sizeBytes,
            downloadUrl: downloadUrl,
          ),
        ];

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'quantization': quantization,
    'sizeBytes': sizeBytes,
    'downloadUrl': downloadUrl,
    'isAuxiliary': isAuxiliary,
    if (parts.isNotEmpty) 'parts': parts.map((p) => p.toJson()).toList(),
    if (expectedParts > 1) 'expectedParts': expectedParts,
  };

  factory GgufVariant.fromJson(Map<String, dynamic> json) {
    final fileName = (json['fileName'] ?? '').toString();
    final rawParts = json['parts'];
    final parsedParts = rawParts is List
        ? rawParts
            .whereType<Map<String, dynamic>>()
            .map(GgufPart.fromJson)
            .toList()
        : const <GgufPart>[];
    return GgufVariant(
      fileName: fileName,
      quantization: (json['quantization'] ?? 'GGUF').toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
      isAuxiliary:
          (json['isAuxiliary'] as bool?) ??
          OpenModel.isAuxiliaryGgufFile(fileName),
      parts: parsedParts,
      expectedParts: (json['expectedParts'] as num?)?.toInt() ??
          (parsedParts.isNotEmpty ? parsedParts.length : 1),
    );
  }
}

class OpenModel {
  final String id;
  final String name;
  final String publisher;
  final String parameterSizeB;
  final String format; // GGUF, TFLite, ONNX, MediaPipe
  final String quantization; // Q4_K_M, int4, fp16
  final int downloadSizeMb;
  final int minRamGb;
  final String downloadUrl;
  final String description;
  final String repoUrl;
  final List<GgufVariant> variants;
  final DateTime? createdAt;
  final int downloads;
  final int likes;
  final bool isGated;
  final bool hasFetchedDescription;
  final String? baseModel;
  final String? license;

  OpenModel({
    required this.id,
    required this.name,
    required this.publisher,
    required this.parameterSizeB,
    required this.format,
    required this.quantization,
    required this.downloadSizeMb,
    required this.minRamGb,
    required this.downloadUrl,
    required this.description,
    required this.repoUrl,
    this.variants = const [],
    this.createdAt,
    this.downloads = 0,
    this.likes = 0,
    this.isGated = false,
    this.hasFetchedDescription = false,
    this.baseModel,
    this.license,
  });

  /// Returns true for auxiliary GGUFs (MTP speculative heads, mmproj vision
  /// projectors, draft weights) that cannot run standalone chat inference.
  static bool isAuxiliaryGgufFile(String fileName) {
    final lower = fileName.split(RegExp(r'[/\\]')).last.toLowerCase();
    return RegExp(r'(^|[-_.])(mmproj|mtp|draft)([-_.]|$)').hasMatch(lower);
  }

  /// Extracts split shard metadata from filenames formatted like
  /// `Model-IQ1_M-00001-of-00004.gguf`. Returns null for normal single GGUFs.
  static SplitShardInfo? parseSplitShard(String fileName) {
    final match = RegExp(
      r'^(.+?)-(\d{5})-of-(\d{5})\.gguf$',
      caseSensitive: false,
    ).firstMatch(fileName.trim());
    if (match == null) return null;
    final prefix = match.group(1);
    final part = int.tryParse(match.group(2) ?? '');
    final total = int.tryParse(match.group(3) ?? '');
    if (prefix == null ||
        part == null ||
        total == null ||
        total <= 1 ||
        part < 1 ||
        part > total) {
      return null;
    }
    return SplitShardInfo(prefix: prefix, partNumber: part, totalParts: total);
  }

  factory OpenModel.fromJson(Map<String, dynamic> json) {
    final name = json['name'] ?? '';
    final publisher = json['publisher'] ?? '';
    final paramSize = json['parameter_size_b']?.toString() ?? '1.0';

    String defaultDesc = '$name by $publisher is a ${paramSize}B parameter model optimized for mobile and edge inference.';
    if (publisher.toLowerCase().contains('qwen')) {
      defaultDesc = 'Ultra-compact multilingual language model designed for fast reasoning, assistant chat, and low-latency mobile inference.';
    } else if (publisher.toLowerCase().contains('meta')) {
      defaultDesc = 'High-efficiency instruct-tuned model by Meta, engineered for on-device summarization, multilingual chat, and task execution.';
    } else if (publisher.toLowerCase().contains('google')) {
      defaultDesc = 'Lightweight on-device instruction model built using Gemini technology, focused on fast conversational reasoning.';
    }

    final downloadUrl = json['download_url'] ?? '';
    String defaultRepo = 'https://huggingface.co';
    if (downloadUrl.contains('huggingface.co/')) {
      final parts = downloadUrl.split('/resolve/');
      if (parts.isNotEmpty) {
        defaultRepo = parts[0];
      }
    }

    final parsedVariants = (json['variants'] as List<dynamic>?)
            ?.map((e) => GgufVariant.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <GgufVariant>[];

    return OpenModel(
      id: json['id'] ?? '',
      name: name,
      publisher: publisher,
      parameterSizeB: paramSize,
      format: json['format'] ?? 'GGUF',
      quantization: json['quantization'] ?? 'Q4_K_M',
      downloadSizeMb: (json['download_size_mb'] as num?)?.toInt() ?? 0,
      minRamGb: (json['min_ram_gb'] as num?)?.toInt() ?? 0,
      downloadUrl: downloadUrl,
      description: json['description'] ?? defaultDesc,
      repoUrl: json['repo_url'] ?? defaultRepo,
      variants: parsedVariants,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      isGated: (json['is_gated'] as bool?) ?? false,
      hasFetchedDescription: (json['has_fetched_description'] as bool?) ?? false,
      baseModel: json['base_model'] as String?,
      license: json['license'] as String?,
    );
  }

  /// Extracts all downloadable `.gguf` variants from a Hugging Face `siblings` list.
  /// Multi-part shards (`...-00001-of-0000N.gguf`) are grouped into a single
  /// logical variant with summed byte size, ordered after single-file GGUFs.
  static List<GgufVariant> parseGgufVariantsFromSiblings(
    String repoId,
    dynamic siblings,
  ) {
    if (siblings is! List || siblings.isEmpty) return const [];

    final singleVariants = <GgufVariant>[];
    final splitGroups = <String, List<(int? size, String url, SplitShardInfo info, String fname)>>{};
    final quantRegex = RegExp(
      r'(Q[0-9]_[A-Z0-9_]+|IQ[0-9]_[A-Z0-9_]+|FP16|BF16|F16|F32)',
      caseSensitive: false,
    );

    for (final s in siblings) {
      if (s is Map && s['rfilename'] is String) {
        final fname = s['rfilename'] as String;
        if (!fname.toLowerCase().endsWith('.gguf')) continue;
        final size = (s['size'] as num?)?.toInt();
        final encodedPath = fname
            .split('/')
            .map(Uri.encodeComponent)
            .join('/');
        final url = 'https://huggingface.co/$repoId/resolve/main/$encodedPath';

        final splitInfo = parseSplitShard(fname);
        if (splitInfo != null) {
          final groupKey =
              '${splitInfo.prefix.toLowerCase()}::${splitInfo.totalParts}';
          splitGroups.putIfAbsent(groupKey, () => []).add((
            size,
            url,
            splitInfo,
            fname,
          ));
        } else {
          final m = quantRegex.firstMatch(fname);
          final quant = m != null ? m.group(1)!.toUpperCase() : 'GGUF';
          singleVariants.add(
            GgufVariant(
              fileName: fname,
              quantization: quant,
              sizeBytes: size,
              downloadUrl: url,
              isAuxiliary: isAuxiliaryGgufFile(fname),
            ),
          );
        }
      }
    }

    final groupedVariants = <GgufVariant>[...singleVariants];
    for (final entries in splitGroups.values) {
      entries.sort((a, b) => a.$3.partNumber.compareTo(b.$3.partNumber));
      final first = entries.first;
      final prefix = first.$3.prefix;
      final m = quantRegex.firstMatch(prefix);
      final quant = m != null ? m.group(1)!.toUpperCase() : 'GGUF';

      int sumBytes = 0;
      bool hasKnownSize = false;
      final parts = <GgufPart>[];
      for (final item in entries) {
        if (item.$1 != null && item.$1! > 0) {
          sumBytes += item.$1!;
          hasKnownSize = true;
        }
        parts.add(
          GgufPart(
            fileName: item.$4,
            partNumber: item.$3.partNumber,
            sizeBytes: item.$1,
            downloadUrl: item.$2,
          ),
        );
      }

      groupedVariants.add(
        GgufVariant(
          fileName: first.$4,
          quantization: quant,
          sizeBytes: hasKnownSize ? sumBytes : null,
          downloadUrl: first.$2,
          isAuxiliary: isAuxiliaryGgufFile(prefix),
          parts: parts,
          expectedParts: first.$3.totalParts,
        ),
      );
    }

    if (groupedVariants.isEmpty) return const [];

    // Filter out auxiliary files (mmproj, mtp-, draft-) if main model weights exist
    final primaryWeights = groupedVariants
        .where((v) => !v.isAuxiliary)
        .toList();
    final candidates = primaryWeights.isNotEmpty ? primaryWeights : groupedVariants;

    const preferredOrder = [
      'Q4_K_M',
      'Q4_0',
      'Q5_K_M',
      'Q4_K_S',
      'Q3_K_M',
      'Q8_0',
      'IQ4_XS',
    ];

    candidates.sort((a, b) {
      // Always prefer single-file GGUFs over multi-part splits by default.
      if (a.isSplit != b.isSplit) {
        return a.isSplit ? 1 : -1;
      }
      final idxA = preferredOrder.indexOf(a.quantization);
      final idxB = preferredOrder.indexOf(b.quantization);
      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;
      return a.fileName.compareTo(b.fileName);
    });

    return candidates;
  }

  factory OpenModel.fromHuggingFace(Map<String, dynamic> json) {
    final rawId = (json['id'] ?? json['modelId'] ?? '').toString();
    String author = (json['author'] ?? '').toString();
    String repoSlug = rawId;

    if (rawId.contains('/')) {
      final parts = rawId.split('/');
      if (author.isEmpty) author = parts[0];
      repoSlug = parts.sublist(1).join('/');
    }
    if (author.isEmpty) author = 'Community';

    // Clean human-friendly name
    String cleanName = repoSlug
        .replaceAll(RegExp(r'[-_]GGUF$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();
    if (cleanName.isEmpty) cleanName = rawId;

    // Detect canonical publisher brand
    final lowerId = rawId.toLowerCase();
    final lowerAuthor = author.toLowerCase();
    final List<dynamic> tags = (json['tags'] as List<dynamic>?) ?? [];
    final lowerTags = tags.map((t) => t.toString().toLowerCase()).toSet();

    String publisher = author;
    if (lowerId.contains('qwen') || lowerAuthor.contains('qwen') || lowerTags.contains('qwen')) {
      publisher = 'Qwen';
    } else if (lowerId.contains('llama') || lowerAuthor.contains('meta') || lowerTags.contains('meta') || lowerTags.contains('facebook')) {
      publisher = 'Meta';
    } else if (lowerId.contains('gemma') || lowerAuthor.contains('google') || lowerTags.contains('google')) {
      publisher = 'Google';
    } else if (lowerId.contains('mistral') || lowerAuthor.contains('mistral') || lowerTags.contains('mistral')) {
      publisher = 'Mistral';
    } else if (lowerId.contains('phi') || lowerAuthor.contains('microsoft') || lowerTags.contains('microsoft')) {
      publisher = 'Microsoft';
    } else if (lowerId.contains('deepseek') || lowerAuthor.contains('deepseek') || lowerTags.contains('deepseek')) {
      publisher = 'DeepSeek';
    } else if (lowerAuthor.contains('bartowski')) {
      publisher = 'Bartowski';
    } else if (lowerAuthor.contains('unsloth')) {
      publisher = 'Unsloth';
    } else if (lowerAuthor.contains('thebloke')) {
      publisher = 'TheBloke';
    }

    // Extract parameter size in billions (e.g. 0.5, 1, 3, 7, 8, 14, 70)
    String paramSize = '1.0';
    bool hasKnownParams = false;
    final safetensors = json['safetensors'];
    final ggufMeta = json['gguf'];
    if (safetensors is Map && safetensors['total'] is num) {
      final totalParams = safetensors['total'] as num;
      if (totalParams > 0) {
        paramSize = (totalParams / 1e9).toStringAsFixed(1);
        hasKnownParams = true;
      }
    } else if (ggufMeta is Map && ggufMeta['total'] is num) {
      final totalParams = ggufMeta['total'] as num;
      if (totalParams > 0) {
        paramSize = (totalParams / 1e9).toStringAsFixed(1);
        hasKnownParams = true;
      }
    }
    if (!hasKnownParams) {
      final paramMatch = RegExp(
        r'(?:^|[\s\-_])([0-9]+(?:\.[0-9]+)?)[bB](?:[\s\-_]|$)',
      ).firstMatch(rawId);
      if (paramMatch != null && paramMatch.group(1) != null) {
        paramSize = paramMatch.group(1)!;
        hasKnownParams = true;
      }
    }

    // Scan siblings for GGUF files and preferred quantization
    final variants = parseGgufVariantsFromSiblings(rawId, json['siblings']);
    final primaryVariant = variants.isNotEmpty ? variants.first : null;
    final String quantization = primaryVariant?.quantization ?? 'Q4_K_M';
    final int? detectedSizeBytes = primaryVariant?.sizeBytes;
    final int? ggufTotalFileSize =
        (ggufMeta is Map && ggufMeta['totalFileSize'] is num)
            ? (ggufMeta['totalFileSize'] as num).toInt()
            : null;

    // Estimate or calculate download size in MB
    final double paramNum = double.tryParse(paramSize) ?? 1.0;
    int downloadSizeMb;
    if (detectedSizeBytes != null && detectedSizeBytes > 0) {
      downloadSizeMb = (detectedSizeBytes / (1024 * 1024)).round();
    } else if (!hasKnownParams &&
        ggufTotalFileSize != null &&
        ggufTotalFileSize > 0) {
      downloadSizeMb = (ggufTotalFileSize / (1024 * 1024)).round().clamp(
        1,
        2000000,
      );
    } else {
      final mbPerB = estimatedMbPerBillionParams(quantization);
      downloadSizeMb = (paramNum * mbPerB + 150).round().clamp(200, 2000000);
    }

    // Minimum RAM required calculation
    final minRamGb = ((downloadSizeMb / 1024) * 1.5).ceil() + 1;
    final clampedRamGb = minRamGb.clamp(2, 2048);

    // Leave downloadUrl empty if no direct .gguf file was listed in siblings so
    // ModelManagerService resolves the actual file list before downloading.
    final downloadUrl = primaryVariant?.downloadUrl ?? '';

    final downloads = (json['downloads'] as num?)?.toInt() ?? 0;
    final likes = (json['likes'] as num?)?.toInt() ?? 0;
    final gatedRaw = json['gated'];
    final isGated =
        gatedRaw != null && gatedRaw != false && gatedRaw != 'false';
    final rawDate = json['createdAt'] ?? json['lastModified'];
    final createdAt = rawDate != null ? DateTime.tryParse(rawDate.toString()) : null;

    final cardData = json['cardData'];
    String? baseModel;
    String? license;
    if (cardData is Map) {
      final rawBase = cardData['base_model'];
      if (rawBase is String && rawBase.trim().isNotEmpty) {
        baseModel = rawBase.trim();
      } else if (rawBase is List && rawBase.isNotEmpty) {
        baseModel = rawBase.first.toString().trim();
      }
      final rawLicense = cardData['license'];
      if (rawLicense is String && rawLicense.trim().isNotEmpty) {
        license = rawLicense.trim();
      }
    }
    if (baseModel == null && json['baseModels'] is Map) {
      final modelsList = (json['baseModels'] as Map)['models'];
      if (modelsList is List && modelsList.isNotEmpty) {
        final first = modelsList.first;
        if (first is Map && first['id'] is String) {
          baseModel = (first['id'] as String).trim();
        }
      }
    }

    final informativeTags = tags
        .map((t) => t.toString())
        .where((t) {
          final lower = t.toLowerCase();
          return lower.isNotEmpty &&
              lower != 'gguf' &&
              lower != 'text-generation' &&
              lower != 'endpoints_compatible' &&
              !lower.startsWith('region:') &&
              !lower.startsWith('license:');
        })
        .take(4)
        .toList();

    final summaryParts = <String>[
      if (baseModel != null && baseModel.isNotEmpty) 'Based on $baseModel',
      if (license != null && license.isNotEmpty) 'License: $license',
      if (informativeTags.isNotEmpty) informativeTags.join(', '),
    ];
    final description = summaryParts.isNotEmpty
        ? summaryParts.join(' • ')
        : 'GGUF weights published by $author on Hugging Face.';

    return OpenModel(
      id: rawId,
      name: cleanName,
      publisher: publisher,
      parameterSizeB: paramSize,
      format: 'GGUF',
      quantization: quantization,
      downloadSizeMb: downloadSizeMb,
      minRamGb: clampedRamGb,
      downloadUrl: downloadUrl,
      description: description,
      repoUrl: 'https://huggingface.co/$rawId',
      variants: variants,
      createdAt: createdAt,
      downloads: downloads,
      likes: likes,
      isGated: isGated,
      hasFetchedDescription: false,
      baseModel: baseModel,
      license: license,
    );
  }

  /// Estimated megabytes per billion parameters for common GGUF quantizations
  /// when exact per-file byte sizes have not yet been fetched from HF blobs.
  static double estimatedMbPerBillionParams(String quantization) {
    final q = quantization.toUpperCase();
    if (q.startsWith('IQ1')) return 220.0;
    if (q.startsWith('IQ2') || q.startsWith('Q2')) return 330.0;
    if (q.startsWith('IQ3') || q.startsWith('Q3')) return 450.0;
    if (q.startsWith('IQ4') || q.startsWith('Q4')) return 560.0;
    if (q.startsWith('Q5')) return 700.0;
    if (q.startsWith('Q6')) return 820.0;
    if (q.startsWith('Q8')) return 1060.0;
    if (q == 'FP16' || q == 'BF16' || q == 'F16') return 2000.0;
    if (q == 'F32') return 4000.0;
    return 560.0;
  }

  /// True when at least one variant already carries an exact byte count.
  bool get hasExactSizes =>
      variants.any((v) => v.sizeBytes != null && v.sizeBytes! > 0);

  double get paramSizeNum => double.tryParse(parameterSizeB) ?? 1.0;

  GgufVariant? get primaryVariant =>
      variants.isNotEmpty ? variants.first : null;

  int get partCount => primaryVariant?.partCount ?? 1;

  bool get isSplit => partCount > 1;

  /// True when the model exceeds available device RAM or the >12 GB mobile limit.
  bool isTooLargeForPhone({double deviceRamGb = 8.0}) =>
      minRamGb > deviceRamGb || minRamGb > 12;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'publisher': publisher,
    'parameter_size_b': parameterSizeB,
    'format': format,
    'quantization': quantization,
    'download_size_mb': downloadSizeMb,
    'min_ram_gb': minRamGb,
    'download_url': downloadUrl,
    'description': description,
    'repo_url': repoUrl,
    if (variants.isNotEmpty)
      'variants': variants.map((v) => v.toJson()).toList(),
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    'downloads': downloads,
    'likes': likes,
    if (isGated) 'is_gated': isGated,
    if (hasFetchedDescription) 'has_fetched_description': hasFetchedDescription,
    if (baseModel != null) 'base_model': baseModel,
    if (license != null) 'license': license,
  };

  OpenModel copyWith({
    String? id,
    String? name,
    String? publisher,
    String? parameterSizeB,
    String? format,
    String? quantization,
    int? downloadSizeMb,
    int? minRamGb,
    String? downloadUrl,
    String? description,
    String? repoUrl,
    List<GgufVariant>? variants,
    DateTime? createdAt,
    int? downloads,
    int? likes,
    bool? isGated,
    bool? hasFetchedDescription,
    String? baseModel,
    String? license,
  }) {
    return OpenModel(
      id: id ?? this.id,
      name: name ?? this.name,
      publisher: publisher ?? this.publisher,
      parameterSizeB: parameterSizeB ?? this.parameterSizeB,
      format: format ?? this.format,
      quantization: quantization ?? this.quantization,
      downloadSizeMb: downloadSizeMb ?? this.downloadSizeMb,
      minRamGb: minRamGb ?? this.minRamGb,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      description: description ?? this.description,
      repoUrl: repoUrl ?? this.repoUrl,
      variants: variants ?? this.variants,
      createdAt: createdAt ?? this.createdAt,
      downloads: downloads ?? this.downloads,
      likes: likes ?? this.likes,
      isGated: isGated ?? this.isGated,
      hasFetchedDescription:
          hasFetchedDescription ?? this.hasFetchedDescription,
      baseModel: baseModel ?? this.baseModel,
      license: license ?? this.license,
    );
  }
}
