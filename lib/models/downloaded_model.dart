class DownloadedModel {
  final String modelId;
  final String name;
  final String publisher;
  final String fileName;
  final String filePath;
  final String quantization;
  final int sizeBytes;
  final DateTime downloadedAt;
  final String sourceUrl;

  const DownloadedModel({
    required this.modelId,
    required this.name,
    required this.publisher,
    required this.fileName,
    required this.filePath,
    required this.quantization,
    required this.sizeBytes,
    required this.downloadedAt,
    required this.sourceUrl,
  });

  double get sizeMb => sizeBytes / (1024 * 1024);

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'name': name,
    'publisher': publisher,
    'fileName': fileName,
    'filePath': filePath,
    'quantization': quantization,
    'sizeBytes': sizeBytes,
    'downloadedAt': downloadedAt.toIso8601String(),
    'sourceUrl': sourceUrl,
  };

  factory DownloadedModel.fromJson(Map<String, dynamic> json) {
    return DownloadedModel(
      modelId: (json['modelId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      publisher: (json['publisher'] ?? 'Local').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      filePath: (json['filePath'] ?? '').toString(),
      quantization: (json['quantization'] ?? 'GGUF').toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      downloadedAt: json['downloadedAt'] != null
          ? DateTime.tryParse(json['downloadedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      sourceUrl: (json['sourceUrl'] ?? '').toString(),
    );
  }

  DownloadedModel copyWith({
    String? modelId,
    String? name,
    String? publisher,
    String? fileName,
    String? filePath,
    String? quantization,
    int? sizeBytes,
    DateTime? downloadedAt,
    String? sourceUrl,
  }) {
    return DownloadedModel(
      modelId: modelId ?? this.modelId,
      name: name ?? this.name,
      publisher: publisher ?? this.publisher,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      quantization: quantization ?? this.quantization,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }
}
