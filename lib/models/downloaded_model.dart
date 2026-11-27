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
  final List<String> partFileNames;

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
    this.partFileNames = const [],
  });

  double get sizeMb => sizeBytes / (1024 * 1024);

  /// All shard filenames belonging to this model (single-item list for normal models).
  List<String> get allFileNames =>
      partFileNames.isNotEmpty ? partFileNames : [fileName];

  int get partCount => allFileNames.length;

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
    if (partFileNames.isNotEmpty) 'partFileNames': partFileNames,
  };

  factory DownloadedModel.fromJson(Map<String, dynamic> json) {
    final rawParts = json['partFileNames'];
    final parts = rawParts is List
        ? rawParts.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
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
      partFileNames: parts,
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
    List<String>? partFileNames,
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
      partFileNames: partFileNames ?? this.partFileNames,
    );
  }
}
