import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/services/model_catalog_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';
import 'package:mobai/utils/format_utils.dart';

class CustomModelDialogResult {
  final OpenModel model;
  final bool downloadAndUse;

  const CustomModelDialogResult({
    required this.model,
    this.downloadAndUse = false,
  });
}

Future<CustomModelDialogResult?> showAddCustomModelDialog(BuildContext context) {
  return showDialog<CustomModelDialogResult>(
    context: context,
    builder: (_) => const _AddCustomModelDialog(),
  );
}

class _AddCustomModelDialog extends StatefulWidget {
  const _AddCustomModelDialog();

  @override
  State<_AddCustomModelDialog> createState() => _AddCustomModelDialogState();
}

class _AddCustomModelDialogState extends State<_AddCustomModelDialog> {
  final ModelCatalogService _catalogService = ModelCatalogService();
  final ModelManagerService _managerService = ModelManagerService();
  final StorageService _storageService = StorageService();

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _publisherController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  int _modeIndex = 0; // 0 = From URL, 1 = Local .gguf
  bool _isResolving = false;
  bool _isImporting = false;
  double _importProgress = 0.0;
  String? _errorMessage;
  String? _statusMessage;
  String? _lastResolvedUrl;
  OpenModel? _resolvedModel;
  GgufVariant? _selectedVariant;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _publisherController.dispose();
    _sizeController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<OpenModel?> _resolveUrl({bool force = false}) async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a Hugging Face or direct .gguf URL.';
      });
      return null;
    }

    if (!force && _resolvedModel != null && _lastResolvedUrl == rawUrl) {
      return _resolvedModel;
    }

    setState(() {
      _isResolving = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final resolved = await _catalogService.resolveCustomModelFromUrl(rawUrl);
      if (!mounted) return null;

      GgufVariant? selected;
      if (resolved.variants.isNotEmpty) {
        selected = resolved.variants.firstWhere(
          (v) =>
              v.downloadUrl == resolved.downloadUrl ||
              v.parts.any((p) => p.downloadUrl == resolved.downloadUrl),
          orElse: () => resolved.variants.first,
        );
      }

      setState(() {
        _resolvedModel = resolved;
        _selectedVariant = selected;
        _lastResolvedUrl = rawUrl;
        _nameController.text = resolved.name;
        _publisherController.text = resolved.publisher;
        _sizeController.text = '${resolved.downloadSizeMb}';
        _descController.text = resolved.description;
        _isResolving = false;
        _statusMessage = resolved.variants.isNotEmpty
            ? 'Detected ${resolved.variants.length} GGUF file(s).'
            : 'Resolved URL metadata.';
      });
      return resolved;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _isResolving = false;
        _errorMessage = e.toString().replaceFirst('FormatException: ', '');
      });
      return null;
    }
  }

  Future<void> _submitUrlModel({required bool downloadAndUse}) async {
    final resolved = await _resolveUrl();
    if (resolved == null || !mounted) return;

    final name = _nameController.text.trim().isEmpty
        ? resolved.name
        : _nameController.text.trim();
    final publisher = _publisherController.text.trim().isEmpty
        ? resolved.publisher
        : _publisherController.text.trim();
    final sizeMb =
        int.tryParse(_sizeController.text.trim()) ?? resolved.downloadSizeMb;
    final desc = _descController.text.trim().isEmpty
        ? resolved.description
        : _descController.text.trim();

    final variant = _selectedVariant;
    final resolvedSizeMb = variant != null && variant.sizeMb > 0
        ? variant.sizeMb
        : sizeMb;
    final reorderedVariants = variant != null
        ? [variant, ...resolved.variants.where((v) => v != variant)]
        : resolved.variants;
    final finalModel = resolved.copyWith(
      name: name,
      publisher: publisher,
      downloadSizeMb: resolvedSizeMb,
      minRamGb: (((resolvedSizeMb / 1024) * 1.5).ceil() + 1).clamp(2, 2048),
      quantization: variant?.quantization ?? resolved.quantization,
      downloadUrl: variant?.downloadUrl ?? resolved.downloadUrl,
      variants: reorderedVariants,
      description: desc,
    );

    _managerService.addCustomModel(finalModel);
    if (!mounted) return;
    Navigator.pop(
      context,
      CustomModelDialogResult(
        model: finalModel,
        downloadAndUse: downloadAndUse,
      ),
    );
  }

  Future<void> _pickAndImportLocalFile() async {
    setState(() {
      _errorMessage = null;
      _statusMessage = null;
    });

    final picked = await FilePicker.pickFile(
      dialogTitle: 'Select a .gguf model file',
      type: FileType.any,
    );
    if (picked == null || picked.path == null || picked.path!.isEmpty) {
      return;
    }

    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
    });

    try {
      final downloaded = await _managerService.importLocalGgufFile(
        picked.path!,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _importProgress = p;
            });
          }
        },
      );
      if (!mounted) return;
      final model = _managerService.models.firstWhere(
        (m) => m.id == downloaded.modelId,
      );
      Navigator.pop(
        context,
        CustomModelDialogResult(model: model, downloadAndUse: false),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _errorMessage = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _rescanModelsFolder() async {
    setState(() {
      _isImporting = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    await _managerService.syncWithStorage();
    if (!mounted) return;
    final count = _managerService.downloadedModels.length;
    setState(() {
      _isImporting = false;
      _statusMessage =
          'Scanned MobAI/models: $count local model${count == 1 ? '' : 's'} ready.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _isResolving || _isImporting;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.add_box_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Add Custom Model')),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.link_rounded, size: 16),
                      label: Text('From URL'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.folder_open_rounded, size: 16),
                      label: Text('Local .gguf'),
                    ),
                  ],
                  selected: {_modeIndex},
                  onSelectionChanged: busy
                      ? null
                      : (sel) {
                          setState(() {
                            _modeIndex = sel.first;
                            _errorMessage = null;
                            _statusMessage = null;
                          });
                        },
                ),
              ),
              const SizedBox(height: 14),
              if (_modeIndex == 0) _buildUrlForm(theme) else _buildLocalImport(theme),
              if (_statusMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(110),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_modeIndex == 0) ...[
          OutlinedButton(
            onPressed: busy ? null : () => _submitUrlModel(downloadAndUse: false),
            child: const Text('Add to Catalog'),
          ),
          FilledButton.icon(
            icon: _isResolving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download & Use'),
            onPressed: busy ? null : () => _submitUrlModel(downloadAndUse: true),
          ),
        ],
      ],
    );
  }

  Widget _buildUrlForm(ThemeData theme) {
    final variants = _resolvedModel?.variants ?? const <GgufVariant>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paste a Hugging Face repo link, /blob/ or /resolve/ link, or any direct .gguf URL.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                enabled: !_isResolving,
                onSubmitted: (_) => _resolveUrl(force: true),
                decoration: const InputDecoration(
                  labelText: 'Model or Hugging Face URL *',
                  hintText: 'https://huggingface.co/owner/repo...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 54,
              child: FilledButton.tonal(
                onPressed: _isResolving ? null : () => _resolveUrl(force: true),
                child: _isResolving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Fetch'),
              ),
            ),
          ],
        ),
        if (variants.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<GgufVariant>(
            initialValue: _selectedVariant,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'GGUF File / Quantization',
              border: OutlineInputBorder(),
            ),
            items: variants.map((v) {
              final sizeLabel = v.sizeMb > 0
                  ? ' (${formatSizeWithParts(v.sizeMb, partCount: v.partCount)})'
                  : (v.isSplit ? ' (${v.partCount} parts)' : '');
              return DropdownMenuItem<GgufVariant>(
                value: v,
                child: Text(
                  '${v.quantization} — ${v.fileName}$sizeLabel',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                _selectedVariant = val;
                if (val.sizeMb > 0) {
                  _sizeController.text = '${val.sizeMb}';
                }
              });
            },
          ),
          Builder(
            builder: (context) {
              final sizeMb = int.tryParse(_sizeController.text.trim()) ??
                  _selectedVariant?.sizeMb ??
                  _resolvedModel?.downloadSizeMb ??
                  0;
              final estRamGb = sizeMb > 0
                  ? (((sizeMb / 1024) * 1.5).ceil() + 1)
                  : (_resolvedModel?.minRamGb ?? 0);
              final tooHeavy =
                  estRamGb > _managerService.deviceRamGb || estRamGb > 12;
              if (!tooHeavy) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withAlpha(140),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Not recommended for phone (~$estRamGb GB RAM required). Likely to crash or fail with OOM.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Model Name',
            hintText: 'Auto-filled on Fetch',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _publisherController,
                decoration: const InputDecoration(
                  labelText: 'Publisher',
                  hintText: 'Community',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _sizeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Size (MB)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLocalImport(ThemeData theme) {
    final modelsPath = _storageService.isInitialized
        ? _storageService.modelsPath
        : 'MobAI/models';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Import a manually downloaded .gguf file from your device into MobAI/models, or rescan files placed directly in:',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            modelsPath,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        const SizedBox(height: 14),
        if (_isImporting) ...[
          LinearProgressIndicator(
            value: _importProgress > 0 ? _importProgress : null,
            borderRadius: BorderRadius.circular(6),
            minHeight: 8,
          ),
          const SizedBox(height: 8),
          Text(
            'Copying & validating GGUF... ${(_importProgress * 100).toInt()}%',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: const Text('Choose .gguf File from Device'),
            onPressed: _isImporting ? null : _pickAndImportLocalFile,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Rescan MobAI/models Folder'),
            onPressed: _isImporting ? null : _rescanModelsFolder,
          ),
        ),
      ],
    );
  }
}
