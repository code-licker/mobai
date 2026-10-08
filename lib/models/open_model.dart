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
