class GgufVariant {
  final String fileName;
  final String quantization;
  final int? sizeBytes;
  final String downloadUrl;
  final bool isAuxiliary;

  const GgufVariant({
    required this.fileName,
    required this.quantization,
    this.sizeBytes,
    required this.downloadUrl,
    this.isAuxiliary = false,
  });

  int get sizeMb =>
      sizeBytes != null ? (sizeBytes! / (1024 * 1024)).round() : 0;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'quantization': quantization,
    'sizeBytes': sizeBytes,
    'downloadUrl': downloadUrl,
    'isAuxiliary': isAuxiliary,
  };

  factory GgufVariant.fromJson(Map<String, dynamic> json) {
    final fileName = (json['fileName'] ?? '').toString();
    return GgufVariant(
      fileName: fileName,
      quantization: (json['quantization'] ?? 'GGUF').toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
      isAuxiliary:
          (json['isAuxiliary'] as bool?) ??
          OpenModel.isAuxiliaryGgufFile(fileName),
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
  });

  /// Returns true for auxiliary GGUFs (MTP speculative heads, mmproj vision
  /// projectors, draft weights) that cannot run standalone chat inference.
  static bool isAuxiliaryGgufFile(String fileName) {
    final lower = fileName.split(RegExp(r'[/\\]')).last.toLowerCase();
    return RegExp(r'(^|[-_.])(mmproj|mtp|draft)([-_.]|$)').hasMatch(lower);
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
    );
  }

  /// Extracts all downloadable `.gguf` variants from a Hugging Face `siblings` list.
  static List<GgufVariant> parseGgufVariantsFromSiblings(
    String repoId,
    dynamic siblings,
  ) {
    if (siblings is! List || siblings.isEmpty) return const [];

    final rawVariants = <GgufVariant>[];
    final quantRegex = RegExp(
      r'(Q[0-9]_[A-Z0-9_]+|IQ[0-9]_[A-Z0-9_]+|FP16|BF16|F16|F32)',
      caseSensitive: false,
    );

    for (final s in siblings) {
      if (s is Map && s['rfilename'] is String) {
        final fname = s['rfilename'] as String;
        if (fname.toLowerCase().endsWith('.gguf')) {
          final size = (s['size'] as num?)?.toInt();
          final m = quantRegex.firstMatch(fname);
          final quant = m != null ? m.group(1)!.toUpperCase() : 'GGUF';
          final encodedPath = fname
              .split('/')
              .map(Uri.encodeComponent)
              .join('/');
          rawVariants.add(
            GgufVariant(
              fileName: fname,
              quantization: quant,
              sizeBytes: size,
              downloadUrl:
                  'https://huggingface.co/$repoId/resolve/main/$encodedPath',
              isAuxiliary: isAuxiliaryGgufFile(fname),
            ),
          );
        }
      }
    }

    if (rawVariants.isEmpty) return const [];

    // Filter out auxiliary files (mmproj, mtp-, draft-) if main model weights exist
    final primaryWeights = rawVariants
        .where((v) => !v.isAuxiliary)
        .toList();
    final candidates = primaryWeights.isNotEmpty ? primaryWeights : rawVariants;

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
    final safetensors = json['safetensors'];
    if (safetensors is Map && safetensors['total'] is num) {
      final totalParams = safetensors['total'] as num;
      paramSize = (totalParams / 1e9).toStringAsFixed(1);
    } else {
      final paramMatch = RegExp(r'(?:^|[\s\-_])([0-9]+(?:\.[0-9]+)?)[bB](?:[\s\-_]|$)').firstMatch(rawId);
      if (paramMatch != null && paramMatch.group(1) != null) {
        paramSize = paramMatch.group(1)!;
      }
    }

    // Scan siblings for GGUF files and preferred quantization
    final variants = parseGgufVariantsFromSiblings(rawId, json['siblings']);
    final primaryVariant = variants.isNotEmpty ? variants.first : null;
    final String quantization = primaryVariant?.quantization ?? 'Q4_K_M';
    final int? detectedSizeBytes = primaryVariant?.sizeBytes;

    // Estimate or calculate download size in MB
    final double paramNum = double.tryParse(paramSize) ?? 1.0;
    int downloadSizeMb;
    if (detectedSizeBytes != null && detectedSizeBytes > 0) {
      downloadSizeMb = (detectedSizeBytes / (1024 * 1024)).round();
    } else {
      // Realistic GGUF 4-bit size estimation: ~550 MB per 1B params + ~150 MB base
      downloadSizeMb = (paramNum * 550 + 150).round().clamp(200, 48000);
    }

    // Minimum RAM required calculation
    final minRamGb = ((downloadSizeMb / 1024) * 1.5).ceil() + 1;
    final clampedRamGb = minRamGb.clamp(2, 64);

    // Leave downloadUrl empty if no direct .gguf file was listed in siblings so
    // ModelManagerService resolves the actual file list before downloading.
    final downloadUrl = primaryVariant?.downloadUrl ?? '';

    final downloads = (json['downloads'] as num?)?.toInt() ?? 0;
    final likes = (json['likes'] as num?)?.toInt() ?? 0;
    final rawDate = json['createdAt'] ?? json['lastModified'];
    final createdAt = rawDate != null ? DateTime.tryParse(rawDate.toString()) : null;
    String stats = '';
    if (downloads > 0) {
      stats += downloads >= 1000 ? ' ${(downloads / 1000).toStringAsFixed(1)}k downloads •' : ' $downloads downloads •';
    }
    stats += ' $likes likes';

    final description = '${paramSize}B parameter GGUF model optimized for on-device inference via Hugging Face.$stats';

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
    );
  }

  double get paramSizeNum => double.tryParse(parameterSizeB) ?? 1.0;

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
    );
  }
}
