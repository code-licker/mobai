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
  });

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
    );
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
    String quantization = 'Q4_K_M';
    String? ggufFileName;
    int? detectedSizeBytes;

    final siblings = json['siblings'];
    if (siblings is List && siblings.isNotEmpty) {
      final ggufFiles = <String>[];
      final fileSizes = <String, int>{};
      for (final s in siblings) {
        if (s is Map && s['rfilename'] is String) {
          final fname = s['rfilename'] as String;
          if (fname.toLowerCase().endsWith('.gguf')) {
            ggufFiles.add(fname);
            if (s['size'] is num) {
              fileSizes[fname] = (s['size'] as num).toInt();
            }
          }
        }
      }

      if (ggufFiles.isNotEmpty) {
        // Preferred quantization matching order
        const preferredQuants = ['Q4_K_M', 'q4_k_m', 'Q4_0', 'q4_0', 'Q5_K_M', 'Q8_0', 'IQ4_XS'];
        for (final q in preferredQuants) {
          final match = ggufFiles.firstWhere(
            (f) => f.contains(q),
            orElse: () => '',
          );
          if (match.isNotEmpty) {
            ggufFileName = match;
            quantization = q.toUpperCase();
            break;
          }
        }
        ggufFileName ??= ggufFiles.first;

        if (fileSizes.containsKey(ggufFileName)) {
          detectedSizeBytes = fileSizes[ggufFileName];
        }

        // Extract quant from file name if not yet matched
        final quantRegex = RegExp(r'(Q[0-9]_[A-Z0-9_]+|IQ[0-9]_[A-Z0-9_]+|FP16|BF16)', caseSensitive: false);
        final m = quantRegex.firstMatch(ggufFileName);
        if (m != null) {
          quantization = m.group(1)!.toUpperCase();
        }
      }
    }

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

    final downloadUrl = ggufFileName != null
        ? 'https://huggingface.co/$rawId/resolve/main/$ggufFileName'
        : 'https://huggingface.co/$rawId';

    final downloads = (json['downloads'] as num?)?.toInt() ?? 0;
    final likes = (json['likes'] as num?)?.toInt() ?? 0;
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
    );
  }
}
