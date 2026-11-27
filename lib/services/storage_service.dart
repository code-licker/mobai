import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageOperationResult {
  final bool success;
  final String? errorMessage;

  const StorageOperationResult({
    required this.success,
    this.errorMessage,
  });

  static const ok = StorageOperationResult(success: true);
}

/// Manages the parent `MobAI` folder containing `MobAI/models` and `MobAI/chats`.
class StorageService extends ChangeNotifier {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _prefRootPathKey = 'mobai_storage_root_path';
  static const String _prefConfiguredKey = 'mobai_storage_configured';
  static const String _prefIsDefaultKey = 'mobai_storage_is_default';
  static const String _prefHfTokenKey = 'mobai_hf_token';

  bool _isInitialized = false;
  bool _isConfigured = false;
  bool _isUsingDefault = true;
  String? _defaultRootPath;
  String? _hfToken;
  late Directory _rootDirectory;

  bool get isInitialized => _isInitialized;
  bool get isConfigured => _isConfigured;
  bool get isUsingDefault => _isUsingDefault;
  String? get hfToken {
    final t = _hfToken?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  bool get hasHfToken => hfToken != null;

  static bool isHuggingFaceHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'huggingface.co' ||
        host.endsWith('.huggingface.co') ||
        host == 'hf.co' ||
        host.endsWith('.hf.co');
  }

  String get rootPath {
    if (!_isInitialized) {
      throw StateError('StorageService.init() must be called before accessing paths.');
    }
    return _rootDirectory.path;
  }

  Directory get rootDirectory {
    if (!_isInitialized) {
      throw StateError('StorageService.init() must be called before accessing directories.');
    }
    return _rootDirectory;
  }

  Directory get modelsDirectory =>
      Directory(_joinPath(rootDirectory.path, 'models'));

  Directory get chatsDirectory =>
      Directory(_joinPath(rootDirectory.path, 'chats'));

  String get modelsPath => modelsDirectory.path;
  String get chatsPath => chatsDirectory.path;

  String get defaultRootPath => _defaultRootPath ?? rootPath;

  /// Resolves a [Uri] returned by `FilePicker.pickDirectory` into a POSIX path
  /// when possible (including Android `primary:` external storage tree URIs).
  static String resolveDirectoryUri(Uri uri) {
    if (uri.scheme == 'file') {
      return uri.toFilePath();
    }
    if (uri.scheme == 'content' &&
        uri.authority == 'com.android.externalstorage.documents') {
      final decodedSegments = uri.pathSegments.map(Uri.decodeComponent).toList();
      final treeIdx = decodedSegments.indexOf('tree');
      if (treeIdx != -1 && treeIdx + 1 < decodedSegments.length) {
        final docId = decodedSegments[treeIdx + 1];
        if (docId.startsWith('primary:')) {
          final rel = docId.substring('primary:'.length);
          return rel.isEmpty
              ? '/storage/emulated/0'
              : '/storage/emulated/0/$rel';
        }
      }
    }
    return uri.toString();
  }

  /// Normalizes a user-selected directory so its MobAI root is `<dir>/MobAI`,
  /// avoiding duplicate `MobAI/MobAI` nesting if the user picked a folder named `MobAI`.
  static String normalizeMobaiRoot(String selectedParentPath) {
    var trimmed = selectedParentPath.trim();
    while (trimmed.length > 1 &&
        (trimmed.endsWith('/') || trimmed.endsWith('\\'))) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final sep = Platform.pathSeparator;
    final parts = trimmed.split(RegExp(r'[/\\]'));
    final lastSegment = parts.isNotEmpty ? parts.last : '';
    if (lastSegment.toLowerCase() == 'mobai') {
      return trimmed;
    }
    return '$trimmed${sep}MobAI';
  }

  static String _joinPath(String parent, String child) {
    final sep = Platform.pathSeparator;
    if (parent.endsWith(sep) || parent.endsWith('/')) {
      return '$parent$child';
    }
    return '$parent$sep$child';
  }

  Future<void> init() async {
    if (_isInitialized) return;

    final docsDir = await getApplicationDocumentsDirectory();
    _defaultRootPath = normalizeMobaiRoot(docsDir.path);

    final prefs = await SharedPreferences.getInstance();
    final savedRoot = prefs.getString(_prefRootPathKey);
    _isConfigured = prefs.getBool(_prefConfiguredKey) ?? false;
    _isUsingDefault = prefs.getBool(_prefIsDefaultKey) ?? true;
    _hfToken = prefs.getString(_prefHfTokenKey);

    String candidateRoot =
        (savedRoot != null && savedRoot.isNotEmpty) ? savedRoot : _defaultRootPath!;

    try {
      await _ensureDirectoriesExist(Directory(candidateRoot));
      final writable = await _probeDirectoryWritable(Directory(candidateRoot));
      if (!writable && candidateRoot != _defaultRootPath) {
        candidateRoot = _defaultRootPath!;
        _isUsingDefault = true;
        await _ensureDirectoriesExist(Directory(candidateRoot));
      }
    } catch (_) {
      candidateRoot = _defaultRootPath!;
      _isUsingDefault = true;
      await _ensureDirectoriesExist(Directory(candidateRoot));
    }

    _rootDirectory = Directory(candidateRoot);
    _isInitialized = true;
    notifyListeners();
  }

  /// Initializes [StorageService] against an explicit directory for unit/widget tests.
  @visibleForTesting
  Future<void> initForTesting(
    Directory rootDir, {
    bool configured = true,
    bool isDefault = true,
    String? hfToken,
  }) async {
    _defaultRootPath = rootDir.path;
    _rootDirectory = rootDir;
    _isConfigured = configured;
    _isUsingDefault = isDefault;
    _hfToken = hfToken;
    await _ensureDirectoriesExist(_rootDirectory);
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setHfToken(String? token) async {
    final cleaned = token?.trim();
    _hfToken = (cleaned == null || cleaned.isEmpty) ? null : cleaned;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_hfToken == null) {
        await prefs.remove(_prefHfTokenKey);
      } else {
        await prefs.setString(_prefHfTokenKey, _hfToken!);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> markConfiguredAsDefault() async {
    if (!_isInitialized) {
      await init();
    }
    final target = Directory(_defaultRootPath ?? _rootDirectory.path);
    await _ensureDirectoriesExist(target);
    _rootDirectory = target;
    _isUsingDefault = true;
    _isConfigured = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefRootPathKey, _rootDirectory.path);
      await prefs.setBool(_prefConfiguredKey, true);
      await prefs.setBool(_prefIsDefaultKey, true);
    } catch (_) {
      // Ignore SharedPreferences errors in pure unit tests.
    }
    notifyListeners();
  }

  /// Sets a user-chosen parent folder. Creates `<selected>/MobAI/models` and
  /// `<selected>/MobAI/chats` and optionally migrates existing files.
  Future<StorageOperationResult> setCustomFolder(
    String selectedParentPath, {
    bool migrateExisting = false,
    Future<void> Function()? beforeMigrate,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    if (selectedParentPath.trim().isEmpty) {
      return const StorageOperationResult(
        success: false,
        errorMessage: 'No folder was selected.',
      );
    }

    if (selectedParentPath.startsWith('content://')) {
      return const StorageOperationResult(
        success: false,
        errorMessage:
            'This Android folder uses a SAF content:// URI that cannot be memory-mapped by llama.cpp. Please choose a folder on internal storage (e.g. Documents or Downloads) or use the default App Documents folder.',
      );
    }

    final normalizedRoot = normalizeMobaiRoot(selectedParentPath);
    return _switchRootDirectory(
      Directory(normalizedRoot),
      isDefault: false,
      migrateExisting: migrateExisting,
      beforeMigrate: beforeMigrate,
    );
  }

  /// Switches storage back to `<AppDocuments>/MobAI`.
  Future<StorageOperationResult> resetToDefaultFolder({
    bool migrateExisting = false,
    Future<void> Function()? beforeMigrate,
  }) async {
    if (!_isInitialized) {
      await init();
    }
    final target = Directory(_defaultRootPath ?? _rootDirectory.path);
    return _switchRootDirectory(
      target,
      isDefault: true,
      migrateExisting: migrateExisting,
      beforeMigrate: beforeMigrate,
    );
  }

  Future<StorageOperationResult> _switchRootDirectory(
    Directory targetRoot, {
    required bool isDefault,
    required bool migrateExisting,
    Future<void> Function()? beforeMigrate,
  }) async {
    final oldRoot = _rootDirectory;
    if (oldRoot.path == targetRoot.path) {
      await markConfiguredState(isDefault: isDefault);
      return StorageOperationResult.ok;
    }

    // Ensure permissions on Android when targeting shared storage outside app sandbox.
    if (!isDefault && Platform.isAndroid) {
      final hasAccess = await _ensureAndroidExternalStorageAccess(targetRoot);
      if (!hasAccess) {
        return const StorageOperationResult(
          success: false,
          errorMessage:
              'Storage permission is required to read and write GGUF models in a custom folder on Android. Grant All Files Access or choose the default App Documents folder.',
        );
      }
    }

    try {
      await _ensureDirectoriesExist(targetRoot);
      final writable = await _probeDirectoryWritable(targetRoot);
      if (!writable) {
        return StorageOperationResult(
          success: false,
          errorMessage:
              'Cannot write to "${targetRoot.path}". Please pick another folder or use the default location.',
        );
      }

      if (migrateExisting) {
        await beforeMigrate?.call();
        await _migrateData(oldRoot: oldRoot, newRoot: targetRoot);
      }

      _rootDirectory = targetRoot;
      _isUsingDefault = isDefault;
      _isConfigured = true;

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefRootPathKey, _rootDirectory.path);
        await prefs.setBool(_prefConfiguredKey, true);
        await prefs.setBool(_prefIsDefaultKey, isDefault);
      } catch (_) {
        // Ignore in headless tests.
      }

      notifyListeners();
      return StorageOperationResult.ok;
    } catch (e) {
      return StorageOperationResult(
        success: false,
        errorMessage: 'Failed to configure storage folder: $e',
      );
    }
  }

  Future<void> markConfiguredState({required bool isDefault}) async {
    _isConfigured = true;
    _isUsingDefault = isDefault;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefRootPathKey, _rootDirectory.path);
      await prefs.setBool(_prefConfiguredKey, true);
      await prefs.setBool(_prefIsDefaultKey, isDefault);
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> hasExistingData() async {
    if (!_isInitialized) return false;
    final modelsDir = modelsDirectory;
    final chatsDir = chatsDirectory;
    if (await modelsDir.exists()) {
      await for (final entity in modelsDir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
          return true;
        }
      }
    }
    if (await chatsDir.exists()) {
      await for (final entity in chatsDir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
          return true;
        }
      }
    }
    return false;
  }

  Future<int> getModelsDiskUsageBytes() async {
    if (!_isInitialized) return 0;
    final dir = modelsDirectory;
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<bool> _ensureAndroidExternalStorageAccess(Directory targetRoot) async {
    // Check direct write first in case app-specific external path is already writable.
    try {
      await _ensureDirectoriesExist(targetRoot);
      if (await _probeDirectoryWritable(targetRoot)) return true;
    } catch (_) {}

    try {
      var manageStatus = await Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted) {
        manageStatus = await Permission.manageExternalStorage.request();
      }
      if (manageStatus.isGranted) return true;

      var storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        storageStatus = await Permission.storage.request();
      }
      return storageStatus.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureDirectoriesExist(Directory root) async {
    final models = Directory(_joinPath(root.path, 'models'));
    final chats = Directory(_joinPath(root.path, 'chats'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    if (!await models.exists()) {
      await models.create(recursive: true);
    }
    if (!await chats.exists()) {
      await chats.create(recursive: true);
    }
  }

  Future<bool> _probeDirectoryWritable(Directory root) async {
    final modelsDir = Directory(_joinPath(root.path, 'models'));
    final chatsDir = Directory(_joinPath(root.path, 'chats'));
    final probe = File(_joinPath(modelsDir.path, '.mobai_write_probe'));
    try {
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      if (!await chatsDir.exists()) {
        await chatsDir.create(recursive: true);
      }
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) {
        await probe.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _migrateData({
    required Directory oldRoot,
    required Directory newRoot,
  }) async {
    final oldModels = Directory(_joinPath(oldRoot.path, 'models'));
    final newModels = Directory(_joinPath(newRoot.path, 'models'));
    final oldChats = Directory(_joinPath(oldRoot.path, 'chats'));
    final newChats = Directory(_joinPath(newRoot.path, 'chats'));

    await _ensureDirectoriesExist(newRoot);

    if (await oldModels.exists()) {
      await for (final entity in oldModels.list(followLinks: false)) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          if (fileName.endsWith('.part')) continue;
          final destPath = _joinPath(newModels.path, fileName);
          if (fileName == 'models_index.json') {
            await _migrateModelsIndex(entity, File(destPath), newModels.path);
          } else {
            await _copyAndRemove(entity, File(destPath));
          }
        }
      }
    }

    if (await oldChats.exists()) {
      await for (final entity in oldChats.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
          final fileName = entity.uri.pathSegments.last;
          final destFile = File(_joinPath(newChats.path, fileName));
          await _migrateChatFile(
            entity,
            destFile,
            oldModelsPath: oldModels.path,
            newModelsPath: newModels.path,
          );
        }
      }
    }
  }

  Future<void> _migrateModelsIndex(
    File source,
    File dest,
    String newModelsPath,
  ) async {
    try {
      final raw = await source.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final updated = decoded.map((item) {
          if (item is Map<String, dynamic>) {
            final copy = Map<String, dynamic>.from(item);
            final fname = (copy['fileName'] ?? '').toString();
            if (fname.isNotEmpty) {
              copy['filePath'] = _joinPath(newModelsPath, fname);
            }
            return copy;
          }
          return item;
        }).toList();
        await dest.writeAsString(jsonEncode(updated), flush: true);
        await source.delete();
        return;
      }
    } catch (_) {}
    await _copyAndRemove(source, dest);
  }

  Future<void> _migrateChatFile(
    File source,
    File dest, {
    required String oldModelsPath,
    required String newModelsPath,
  }) async {
    try {
      final raw = await source.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final modelFilePath = decoded['modelFilePath'] as String?;
        if (modelFilePath != null && modelFilePath.startsWith(oldModelsPath)) {
          final fileName = File(modelFilePath).uri.pathSegments.last;
          decoded['modelFilePath'] = _joinPath(newModelsPath, fileName);
        }
        await dest.writeAsString(jsonEncode(decoded), flush: true);
        await source.delete();
        return;
      }
    } catch (_) {}
    await _copyAndRemove(source, dest);
  }

  Future<void> _copyAndRemove(File source, File dest) async {
    if (source.path == dest.path) return;
    await source.copy(dest.path);
    await source.delete();
  }
}
