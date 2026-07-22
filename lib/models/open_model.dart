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
  });

  factory OpenModel.fromJson(Map<String, dynamic> json) {
    return OpenModel(
      id: json['id'],
      name: json['name'],
      publisher: json['publisher'],
      parameterSizeB: json['parameter_size_b'],
      format: json['format'],
      quantization: json['quantization'],
      downloadSizeMb: json['download_size_mb'],
      minRamGb: json['min_ram_gb'],
      downloadUrl: json['download_url'],
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
  };
}
