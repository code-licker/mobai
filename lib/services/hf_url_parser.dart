class ParsedModelUrl {
  final String originalUrl;
  final String? repoId;
  final String? repoUrl;
  final String? directDownloadUrl;
  final String? fileName;
  final String? filePathInRepo;
  final String? revision;

  const ParsedModelUrl({
    required this.originalUrl,
    this.repoId,
    this.repoUrl,
    this.directDownloadUrl,
    this.fileName,
    this.filePathInRepo,
    this.revision,
  });

  bool get isHuggingFace => repoId != null;
  bool get hasDirectFile =>
      directDownloadUrl != null && directDownloadUrl!.isNotEmpty;
}

/// Parses Hugging Face repository URLs, `/blob/` or `/resolve/` file links,
/// `hf://` URIs, and direct `.gguf` HTTP(S) download URLs.
class HfUrlParser {
  static ParsedModelUrl parse(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Please enter a model URL.');
    }

    if (trimmed.startsWith('hf://')) {
      return _parseHfScheme(trimmed);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'Enter a valid http://, https://, or hf:// URL.',
      );
    }

    final host = uri.host.toLowerCase();
    if (host == 'huggingface.co' || host == 'www.huggingface.co' || host == 'hf.co') {
      return _parseHuggingFaceHttpUri(trimmed, uri);
    }

    final fileName = _extractFileNameFromSegments(uri.pathSegments);
    return ParsedModelUrl(
      originalUrl: trimmed,
      repoUrl: '${uri.scheme}://${uri.authority}',
      directDownloadUrl: trimmed,
      fileName: fileName,
    );
  }

  static ParsedModelUrl _parseHfScheme(String rawInput) {
    final withoutScheme = rawInput.substring('hf://'.length);
    final clean = withoutScheme.split('?').first.split('#').first;
    final parts = clean.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length < 2) {
      throw const FormatException(
        'hf:// URL must include owner and repository (e.g. hf://owner/repo).',
      );
    }

    final owner = parts[0];
    var repo = parts[1];
    var revision = 'main';
    if (repo.contains('@')) {
      final atIdx = repo.indexOf('@');
      revision = repo.substring(atIdx + 1);
      repo = repo.substring(0, atIdx);
      if (revision.isEmpty) revision = 'main';
    }

    final repoId = '$owner/$repo';
    final repoUrl = 'https://huggingface.co/$repoId';
    if (parts.length == 2) {
      return ParsedModelUrl(
        originalUrl: rawInput,
        repoId: repoId,
        repoUrl: repoUrl,
        revision: revision,
      );
    }

    final fileParts = parts.sublist(2);
    final filePath = fileParts.join('/');
    final fileName = fileParts.last;
    final encodedPath = fileParts.map(Uri.encodeComponent).join('/');
    return ParsedModelUrl(
      originalUrl: rawInput,
      repoId: repoId,
      repoUrl: repoUrl,
      revision: revision,
      filePathInRepo: filePath,
      fileName: fileName,
      directDownloadUrl:
          'https://huggingface.co/$repoId/resolve/$revision/$encodedPath',
    );
  }

  static ParsedModelUrl _parseHuggingFaceHttpUri(String rawInput, Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) {
      throw const FormatException(
        'Hugging Face URL must include owner and repository name.',
      );
    }

    final repoId = '${segments[0]}/${segments[1]}';
    final repoUrl = 'https://huggingface.co/$repoId';

    if (segments.length >= 5 &&
        (segments[2] == 'blob' ||
            segments[2] == 'resolve' ||
            segments[2] == 'raw')) {
      final revision = segments[3];
      final fileSegments = segments.sublist(4);
      final decodedSegments = fileSegments.map(Uri.decodeComponent).toList();
      final filePath = decodedSegments.join('/');
      final fileName = decodedSegments.last;
      final encodedSegments = decodedSegments.map(Uri.encodeComponent).join('/');
      final normalizedDownloadUrl =
          'https://huggingface.co/$repoId/resolve/$revision/$encodedSegments';

      return ParsedModelUrl(
        originalUrl: rawInput,
        repoId: repoId,
        repoUrl: repoUrl,
        revision: revision,
        filePathInRepo: filePath,
        fileName: fileName,
        directDownloadUrl: normalizedDownloadUrl,
      );
    }

    // Repo root or /tree/<branch> link
    return ParsedModelUrl(
      originalUrl: rawInput,
      repoId: repoId,
      repoUrl: repoUrl,
    );
  }

  static String _extractFileNameFromSegments(List<String> segments) {
    final nonEmpty = segments.where((s) => s.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return 'model.gguf';
    return Uri.decodeComponent(nonEmpty.last);
  }

  /// Derives a clean human-readable name from a filename or repo slug.
  static String inferDisplayName({String? fileName, String? repoId}) {
    var source = (fileName != null && fileName.isNotEmpty)
        ? fileName
        : (repoId ?? 'Custom Model');
    if (source.contains('/')) {
      source = source.split('/').last;
    }
    source = source
        .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'[-_.](Q[0-9]_[A-Z0-9_]+|IQ[0-9]_[A-Z0-9_]+|FP16|BF16)$',
              caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[-_]GGUF$', caseSensitive: false), '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();
    return source.isEmpty ? 'Custom Model' : source;
  }

  /// Extracts a quantization tag (e.g. `Q4_K_M`) from a filename.
  static String extractQuantization(String fileName) {
    final m = RegExp(
      r'(Q[0-9]_[A-Z0-9_]+|IQ[0-9]_[A-Z0-9_]+|FP16|BF16|F16)',
      caseSensitive: false,
    ).firstMatch(fileName);
    return m != null ? m.group(1)!.toUpperCase() : 'Q4_K_M';
  }
}
