import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/screens/chat_screen.dart';
import 'package:mobai/screens/widgets/active_downloads_sheet.dart';
import 'package:mobai/screens/widgets/add_custom_model_dialog.dart';
import 'package:mobai/screens/widgets/hf_token_dialog.dart';
import 'package:mobai/screens/widgets/model_filter_bottom_sheet.dart';
import 'package:mobai/services/chat_session_service.dart';
import 'package:mobai/services/download_notification_service.dart';
import 'package:mobai/services/model_catalog_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/utils/format_utils.dart';

class ModelSelectorScreen extends StatefulWidget {
  const ModelSelectorScreen({super.key});

  @override
  State<ModelSelectorScreen> createState() => _ModelSelectorScreenState();
}

class _ModelSelectorScreenState extends State<ModelSelectorScreen> {
  final ModelManagerService _managerService = ModelManagerService();
  final ChatSessionService _chatService = ChatSessionService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;

  String? _selectedModelId;
  bool get _showMyModelsOnly => _managerService.filterCriteria.downloadedOnly;

  List<OpenModel> get _visibleModels {
    if (!_showMyModelsOnly) {
      return _managerService.filteredModels;
    }
    final q = _searchController.text.trim().toLowerCase();
    final myList = _managerService.myModels;
    if (q.isEmpty) return myList;
    return myList
        .where(
          (m) =>
              m.name.toLowerCase().contains(q) ||
              m.publisher.toLowerCase().contains(q) ||
              m.id.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _managerService.addListener(_onServiceUpdate);
    _scrollController.addListener(_onScroll);
    if (_managerService.models.isEmpty) {
      _managerService.loadModels();
    } else {
      final list = _managerService.filteredModels;
      if (list.isNotEmpty) {
        _selectedModelId = list.first.id;
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _managerService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onScroll() {
    if (_showMyModelsOnly || !_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 300 &&
        _managerService.hasMoreModels &&
        !_managerService.isLoadingMore) {
      _managerService.loadMoreModels();
    }
  }

  void _onServiceUpdate() {
    if (mounted) {
      final visible = _visibleModels;
      if (_selectedModelId == null && visible.isNotEmpty) {
        _selectedModelId = visible.first.id;
      } else if (_selectedModelId != null && !visible.any((m) => m.id == _selectedModelId)) {
        _selectedModelId = visible.isNotEmpty ? visible.first.id : null;
      }
      setState(() {});
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _managerService.searchModels(query);
    });
  }

  void _openFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ModelFilterBottomSheet(
          initialCriteria: _managerService.filterCriteria,
          allModels: _managerService.models,
          availableProviders: _managerService.availableProviders,
          deviceRamGb: _managerService.deviceRamGb,
          onApply: (newCriteria) {
            _managerService.updateFilterCriteria(newCriteria);
          },
          onReset: () {
            _managerService.clearFilters();
          },
        );
      },
    );
  }

  String _formatMb(double mb) => formatSizeMb(mb);

  Color _getPublisherColor(String publisher) {
    switch (publisher.toLowerCase()) {
      case 'google':
        return Colors.blue.shade700;
      case 'meta':
        return Colors.deepPurple.shade600;
      case 'qwen':
        return Colors.teal.shade700;
      default:
        return Colors.indigo.shade600;
    }
  }

  OpenModel? get _selectedModel {
    if (_selectedModelId == null) return null;
    for (final m in _managerService.myModels) {
      if (m.id == _selectedModelId) return m;
    }
    try {
      return _managerService.models.firstWhere((m) => m.id == _selectedModelId);
    } catch (_) {
      return null;
    }
  }

  void _onChatPressed() {
    final model = _selectedModel;
    if (model == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a model first')),
      );
      return;
    }

    final isDownloaded = _managerService.isModelDownloaded(model.id);

    if (isDownloaded) {
      _navigateToChat(model);
    } else {
      // Wireframe requirement: "Upon clicking chat Show download progress"
      _startDownloadWithChecks(model, openChatSheet: true);
    }
  }

  Future<bool> _confirmHeavyModelDownload(
    OpenModel model, {
    GgufVariant? variant,
  }) async {
    final estSizeMb = variant != null && variant.sizeMb > 0
        ? variant.sizeMb
        : model.downloadSizeMb;
    final estMinRamGb = variant != null && variant.sizeMb > 0
        ? (((estSizeMb / 1024) * 1.5).ceil() + 1).clamp(2, 2048)
        : model.minRamGb;
    final deviceRam = _managerService.deviceRamGb;
    final isTooLarge = estMinRamGb > deviceRam || estMinRamGb > 12;
    if (!isTooLarge) return true;

    final partCount = variant?.partCount ?? model.partCount;
    final sizeText = formatSizeWithParts(estSizeMb, partCount: partCount);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Not Recommended for Phone')),
          ],
        ),
        content: Text(
          '${model.name} ($sizeText) requires ~$estMinRamGb GB RAM, which exceeds safe phone memory (~${deviceRam.toStringAsFixed(0)} GB device RAM).\n\n'
          'Downloading or loading this model on a phone will likely cause errors or crash the app.\n\n'
          'Do you still want to download it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Download Anyway'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _startDownloadWithChecks(
    OpenModel model, {
    GgufVariant? variant,
    bool openChatSheet = false,
  }) async {
    final targetVariant = variant ?? model.primaryVariant;
    if (targetVariant != null && targetVariant.hasMissingParts) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Incomplete split model on Hugging Face: found ${targetVariant.parts.length} of ${targetVariant.partCount} parts.',
          ),
        ),
      );
      return;
    }

    if (!_managerService.isModelDownloading(model.id) &&
        !_managerService.isModelPaused(model.id)) {
      final confirmed = await _confirmHeavyModelDownload(
        model,
        variant: targetVariant,
      );
      if (!confirmed || !mounted) return;
    }

    if (openChatSheet) {
      _showDownloadAndProceedSheet(model, variant: targetVariant);
    } else {
      await _managerService.downloadModel(
        model.id,
        model: model,
        variant: targetVariant,
      );
    }
  }

  void _navigateToChat(OpenModel model) {
    final localPath = _managerService.getLocalModelPath(model.id);
    final session = _chatService.createSession(
      modelId: model.id,
      modelName: model.name,
      modelFilePath: localPath,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(sessionId: session.id),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirmDeleteModel(OpenModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model File?'),
        content: Text(
          'This will remove "${model.name}" from MobAI/models and free local storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _managerService.deleteDownloadedModel(model.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${model.name} from MobAI/models')),
        );
      }
    }
  }

  Future<void> _showVariantPickerSheet(OpenModel model) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return FutureBuilder<List<GgufVariant>>(
          future: _managerService.getVariantsForModel(model),
          builder: (context, snapshot) {
            final theme = Theme.of(context);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Choose GGUF Variant',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    Text(
                      model.name,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.hasError)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Could not load GGUF files from Hugging Face: ${snapshot.error}',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      )
                    else if ((snapshot.data ?? const []).isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No .gguf files found in this repository.'),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: snapshot.data!.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final variant = snapshot.data![idx];
                            final sizeLabel = variant.sizeBytes != null
                                ? '${_formatBytes(variant.sizeBytes!)}${variant.isSplit ? ' (${variant.partCount} parts)' : ''}'
                                : (variant.isSplit
                                      ? 'Size unknown (${variant.partCount} parts)'
                                      : 'Size unknown');
                            final estRamGb = variant.sizeMb > 0
                                ? (((variant.sizeMb / 1024) * 1.5).ceil() + 1)
                                : model.minRamGb;
                            final tooHeavy =
                                estRamGb > _managerService.deviceRamGb ||
                                estRamGb > 12;
                            final disabled =
                                variant.isAuxiliary || variant.hasMissingParts;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    variant.quantization,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  if (variant.isAuxiliary)
                                    _buildVariantTag(
                                      theme,
                                      'Auxiliary (not standalone)',
                                      theme.colorScheme.errorContainer,
                                      theme.colorScheme.onErrorContainer,
                                    )
                                  else if (variant.hasMissingParts)
                                    _buildVariantTag(
                                      theme,
                                      'Incomplete (${variant.parts.length}/${variant.partCount} parts)',
                                      theme.colorScheme.errorContainer,
                                      theme.colorScheme.onErrorContainer,
                                    )
                                  else if (tooHeavy)
                                    _buildVariantTag(
                                      theme,
                                      'Not recommended (~$estRamGb GB RAM)',
                                      theme.colorScheme.errorContainer,
                                      theme.colorScheme.onErrorContainer,
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                '${variant.fileName} • $sizeLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: FilledButton.tonal(
                                onPressed: disabled
                                    ? null
                                    : () {
                                        Navigator.pop(sheetContext);
                                        _startDownloadWithChecks(
                                          model,
                                          variant: variant,
                                        );
                                      },
                                child: Text(
                                  variant.isAuxiliary
                                      ? 'Unsupported'
                                      : (variant.hasMissingParts
                                            ? 'Incomplete'
                                            : 'Download'),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVariantTag(
    ThemeData theme,
    String label,
    Color bg,
    Color fg,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  void _showDownloadAndProceedSheet(
    OpenModel model, {
    GgufVariant? variant,
  }) {
    final theme = Theme.of(context);
    bool navigated = false;

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: _managerService,
          builder: (context, _) {
            final state = _managerService.getDownloadState(model.id);
            final isDownloading = state?.isDownloading ?? false;
            final isPaused = state?.isPaused ?? false;
            final progress = state?.progress ?? 0.0;
            final isDownloaded = _managerService.isModelDownloaded(model.id);
            final error = state?.errorMessage;

            final receivedLabel = state != null && state.receivedBytes > 0
                ? _formatBytes(state.receivedBytes)
                : '0 MB';
            final totalLabel = state != null && state.totalBytes > 0
                ? _formatBytes(state.totalBytes)
                : formatSizeMb(model.downloadSizeMb);
            final speedLabel = state != null && state.speedBytesPerSec > 0
                ? ' • ${_formatBytes(state.speedBytesPerSec.round())}/s'
                : '';

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: error != null
                              ? theme.colorScheme.errorContainer
                              : theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          error != null
                              ? Icons.error_outline_rounded
                              : (isPaused
                                    ? Icons.pause_circle_outline_rounded
                                    : Icons.downloading_rounded),
                          color: error != null
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              error != null
                                  ? 'Download Failed'
                                  : (isPaused
                                        ? 'Download Paused'
                                        : 'Downloading Model Weights'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              model.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (error == null) ...[
                    LinearProgressIndicator(
                      value: isDownloaded
                          ? 1.0
                          : ((isDownloading || isPaused) && progress > 0
                                ? progress
                                : null),
                      borderRadius: BorderRadius.circular(6),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isDownloaded
                              ? 'Ready in MobAI/models!'
                              : '${(progress * 100).toInt()}% • $receivedLabel / $totalLabel$speedLabel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          model.quantization,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withAlpha(120),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        error,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () async {
                          if (isDownloading || isPaused) {
                            await _managerService.cancelDownload(model.id);
                          } else {
                            _managerService.clearDownloadError(model.id);
                          }
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        child: Text(
                          (isDownloading || isPaused) ? 'Cancel' : 'Close',
                        ),
                      ),
                      if (isDownloading)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.pause_rounded, size: 18),
                          label: const Text('Pause'),
                          onPressed: () =>
                              _managerService.pauseDownload(model.id),
                        ),
                      if (isPaused) ...[
                        OutlinedButton(
                          onPressed: () {
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                          child: const Text('Keep Paused'),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('Resume'),
                          onPressed: () {
                            _managerService
                                .resumeDownload(model.id, model: model)
                                .then((downloaded) {
                              if (downloaded != null &&
                                  !navigated &&
                                  sheetContext.mounted) {
                                navigated = true;
                                Navigator.pop(sheetContext);
                                _navigateToChat(model);
                              }
                            });
                          },
                        ),
                      ],
                      if (error != null) ...[
                        if (state?.isGatedError == true)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.key_rounded, size: 16),
                            label: const Text('Add HF Token'),
                            onPressed: () async {
                              final saved = await showHfTokenDialog(context);
                              if (saved && sheetContext.mounted) {
                                _managerService
                                    .downloadModel(model.id, model: model)
                                    .then((downloaded) {
                                  if (downloaded != null &&
                                      !navigated &&
                                      sheetContext.mounted) {
                                    navigated = true;
                                    Navigator.pop(sheetContext);
                                    _navigateToChat(model);
                                  }
                                });
                              }
                            },
                          ),
                        FilledButton.icon(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                          onPressed: () {
                            _managerService
                                .downloadModel(model.id, model: model)
                                .then((downloaded) {
                              if (downloaded != null &&
                                  !navigated &&
                                  sheetContext.mounted) {
                                navigated = true;
                                Navigator.pop(sheetContext);
                                _navigateToChat(model);
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!_managerService.isModelDownloading(model.id) &&
        !_managerService.isModelPaused(model.id)) {
      _managerService
          .downloadModel(model.id, model: model, variant: variant)
          .then((downloaded) {
        if (downloaded != null && !navigated && mounted && Navigator.canPop(context)) {
          navigated = true;
          Navigator.pop(context);
          _navigateToChat(model);
        }
      });
    }
  }

  Future<void> _showAddCustomModelDialog() async {
    final result = await showAddCustomModelDialog(context);
    if (result == null || !mounted) return;

    setState(() {
      _selectedModelId = result.model.id;
    });

    if (result.downloadAndUse) {
      if (_managerService.isModelDownloaded(result.model.id)) {
        _navigateToChat(result.model);
      } else {
        _startDownloadWithChecks(result.model, openChatSheet: true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${result.model.name} to catalog')),
      );
    }
  }

  void _showModelLinkDialog(OpenModel model) {
    final repoUrl = model.repoUrl.trim();
    final downloadUrl = model.downloadUrl.trim();

    bool isHttpUrl(String url) {
      final uri = Uri.tryParse(url);
      return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    }

    Future<void> openInBrowser(BuildContext dialogContext, String url) async {
      final messenger = ScaffoldMessenger.of(dialogContext);
      final opened = await DownloadNotificationService().openUrl(url);
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open link in browser.')),
        );
      }
    }

    Future<void> copyLink(BuildContext dialogContext, String url) async {
      final messenger = ScaffoldMessenger.of(dialogContext);
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard')),
      );
    }

    Widget buildLinkBlock(
      BuildContext dialogContext, {
      required String label,
      required String url,
      required bool emphasizePrimary,
    }) {
      final theme = Theme.of(dialogContext);
      final hasUrl = isHttpUrl(url);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(110),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              url.isNotEmpty ? url : 'Not available',
              style: TextStyle(
                fontSize: 12,
                color: url.isNotEmpty
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.outline,
              ),
            ),
            if (hasUrl) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (emphasizePrimary)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Open in Browser'),
                      onPressed: () => openInBrowser(dialogContext, url),
                    )
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Open'),
                      onPressed: () => openInBrowser(dialogContext, url),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copy'),
                    onPressed: () => copyLink(dialogContext, url),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link_rounded),
            SizedBox(width: 8),
            Text('Model Link'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                model.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              buildLinkBlock(
                dialogContext,
                label: 'Repository',
                url: repoUrl,
                emphasizePrimary: true,
              ),
              const SizedBox(height: 10),
              buildLinkBlock(
                dialogContext,
                label: 'Download URL',
                url: downloadUrl,
                emphasizePrimary: !isHttpUrl(repoUrl),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final models = _visibleModels;
    final myCount = _managerService.myModels.length;
    final isLoading = !_showMyModelsOnly && _managerService.isLoading;
    final filterCriteria = _managerService.filterCriteria;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Model Catalog'),
        centerTitle: true,
        actions: [
          const DownloadIndicatorButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Models',
            onPressed: () {
              if (_searchController.text.isNotEmpty) {
                _managerService.searchModels(_searchController.text);
              } else {
                _managerService.loadModels();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar with Filter Icon
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: _buildSearchBar(context),
            ),

            // Catalog Scope (All / My Models) & Rescan
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('All', style: TextStyle(fontSize: 12)),
                            selected: !_showMyModelsOnly,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) {
                              _managerService.setDownloadedOnly(false);
                              _onServiceUpdate();
                            },
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text(
                              'My Models ($myCount)',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _showMyModelsOnly,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) {
                              _managerService.setDownloadedOnly(true);
                              _onServiceUpdate();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, size: 19),
                    tooltip: 'Rescan MobAI/models folder',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await _managerService.syncWithStorage();
                      if (context.mounted) {
                        final count = _managerService.downloadedModels.length;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Rescanned MobAI/models ($count local model${count == 1 ? '' : 's'})',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),

            // Active Filter Chips Bar (scrollable horizontally)
            if (filterCriteria.isActiveWithBounds(
              maxSizeMb: _managerService.effectiveMaxSizeMb,
              maxParamsB: _managerService.effectiveMaxParamsB,
              maxRamGb: _managerService.effectiveMaxRamGb,
            ))
              _buildActiveFiltersBar(context),

            // Error Banner (if any)
            if (_managerService.error != null)
              _buildErrorBanner(context),

            // Hugging Face Status Header
            _buildHubStatusHeader(context, models.length),

            // List of models or loading/empty state
            Expanded(
              child: isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isNotEmpty
                                ? 'Searching Hugging Face for "${_searchController.text}"...'
                                : 'Fetching models from Hugging Face...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : models.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              filterCriteria.isActive
                                  ? Icons.filter_alt_off_outlined
                                  : Icons.cloud_off_outlined,
                              size: 54,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              filterCriteria.isActive
                                  ? 'No models match current filters'
                                  : (_searchController.text.isNotEmpty
                                      ? 'No models found for "${_searchController.text}"'
                                      : 'No models available'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              filterCriteria.isActive
                                  ? 'Try relaxing your size, params, or RAM sliders, or reset all filters.'
                                  : 'Try a different search term on Hugging Face or add a model manually.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              children: [
                                if (filterCriteria.isActive)
                                  FilledButton.tonalIcon(
                                    onPressed: () => _managerService.clearFilters(),
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Reset Filters'),
                                  ),
                                if (_searchController.text.isNotEmpty)
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      _searchController.clear();
                                      _managerService.searchModels('');
                                    },
                                    icon: const Icon(Icons.clear, size: 18),
                                    label: const Text('Clear Search'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: _showAddCustomModelDialog,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add Model'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: models.length +
                          (!_showMyModelsOnly &&
                                  (_managerService.hasMoreModels ||
                                      _managerService.isLoadingMore)
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        if (index >= models.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: _managerService.isLoadingMore
                                  ? const CircularProgressIndicator()
                                  : OutlinedButton.icon(
                                      icon: const Icon(Icons.expand_more_rounded),
                                      label: const Text('Load more models'),
                                      onPressed: () =>
                                          _managerService.loadMoreModels(),
                                    ),
                            ),
                          );
                        }
                        final model = models[index];
                        final isSelected = _selectedModelId == model.id;
                        final isDownloaded = _managerService.isModelDownloaded(
                          model.id,
                        );
                        final isDownloading = _managerService
                            .isModelDownloading(model.id);
                        final downloadProgress = _managerService
                            .getDownloadProgress(model.id);

                        final downloadState =
                            _managerService.getDownloadState(model.id);

                        return _buildModelCard(
                          context: context,
                          model: model,
                          isSelected: isSelected,
                          isDownloaded: isDownloaded,
                          isDownloading: isDownloading,
                          downloadProgress: downloadProgress,
                          downloadState: downloadState,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      // Floating Bottom Capsule with (+) Add new model and (>) Chat matching wireframe Page 2
      bottomSheet: _buildBottomActionBar(context),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    final criteria = _managerService.filterCriteria;
    final isSearching = _managerService.isLoading && _searchController.text.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          if (isSearching)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            )
          else
            Icon(
              Icons.search_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: (query) {
                _debounceTimer?.cancel();
                _managerService.searchModels(query);
              },
              decoration: InputDecoration(
                hintText: 'Search Hugging Face models...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18),
              tooltip: 'Clear search',
              onPressed: () {
                _searchController.clear();
                _debounceTimer?.cancel();
                _managerService.searchModels('');
              },
            ),
          Container(
            margin: const EdgeInsets.only(right: 4),
            child: PopupMenuButton<ModelSortOption>(
              tooltip: 'Sort (${_managerService.sortOption.label})',
              initialValue: _managerService.sortOption,
              onSelected: (option) => _managerService.setSortOption(option),
              itemBuilder: (context) => ModelSortOption.values
                  .map(
                    (opt) => PopupMenuItem<ModelSortOption>(
                      value: opt,
                      child: Row(
                        children: [
                          if (_managerService.sortOption == opt)
                            Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            )
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Text(opt.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _managerService.sortOption != ModelSortOption.popular
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Badge(
                  isLabelVisible:
                      _managerService.sortOption != ModelSortOption.popular,
                  smallSize: 6,
                  child: Icon(
                    Icons.sort_rounded,
                    size: 20,
                    color: _managerService.sortOption != ModelSortOption.popular
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 6),
            child: IconButton.filledTonal(
              style: IconButton.styleFrom(
                backgroundColor: criteria.isActive
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHigh,
                foregroundColor: criteria.isActive
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              icon: Badge(
                isLabelVisible: criteria.isActiveWithBounds(
                  maxSizeMb: _managerService.effectiveMaxSizeMb,
                  maxParamsB: _managerService.effectiveMaxParamsB,
                  maxRamGb: _managerService.effectiveMaxRamGb,
                ),
                label: Text(
                  '${criteria.activeFilterCountWithBounds(maxSizeMb: _managerService.effectiveMaxSizeMb, maxParamsB: _managerService.effectiveMaxParamsB, maxRamGb: _managerService.effectiveMaxRamGb)}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                child: const Icon(Icons.tune_rounded, size: 20),
              ),
              tooltip: 'Filter models',
              onPressed: _openFilterBottomSheet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersBar(BuildContext context) {
    final criteria = _managerService.filterCriteria;
    final maxSize = _managerService.effectiveMaxSizeMb;
    final maxParams = _managerService.effectiveMaxParamsB;
    final maxRam = _managerService.effectiveMaxRamGb;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          if (criteria.hideNotRecommended)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: const Text(
                  'Hide Not Recommended',
                  style: TextStyle(fontSize: 11),
                ),
                onDeleted: () {
                  _managerService.toggleHideNotRecommended();
                },
              ),
            ),
          if (criteria.downloadedOnly)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: const Text('Downloaded', style: TextStyle(fontSize: 11)),
                onDeleted: () {
                  _managerService.setDownloadedOnly(false);
                },
              ),
            ),
          if (criteria.isSizeFilterActiveWithMax(maxSize) &&
              criteria.sizeRangeMb != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text(
                  'Size: ${_formatMb(criteria.sizeRangeMb!.start)}–${_formatMb(criteria.sizeRangeMb!.end)}',
                  style: const TextStyle(fontSize: 11),
                ),
                onDeleted: () {
                  _managerService.updateFilterCriteria(
                    criteria.copyWith(clearSize: true),
                  );
                },
              ),
            ),
          if (criteria.isParamsFilterActiveWithMax(maxParams) &&
              criteria.paramsRangeB != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text(
                  'Params: ${criteria.paramsRangeB!.start.toStringAsFixed(1)}B–${criteria.paramsRangeB!.end.toStringAsFixed(1)}B',
                  style: const TextStyle(fontSize: 11),
                ),
                onDeleted: () {
                  _managerService.updateFilterCriteria(
                    criteria.copyWith(clearParams: true),
                  );
                },
              ),
            ),
          if (criteria.isRamFilterActiveWithMax(maxRam) &&
              criteria.ramRangeGb != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text(
                  'RAM: ${criteria.ramRangeGb!.start.toInt()}–${criteria.ramRangeGb!.end.toInt()} GB',
                  style: const TextStyle(fontSize: 11),
                ),
                onDeleted: () {
                  _managerService.updateFilterCriteria(
                    criteria.copyWith(clearRam: true),
                  );
                },
              ),
            ),
          for (final provider in criteria.selectedProviders)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text(
                  provider,
                  style: const TextStyle(fontSize: 11),
                ),
                onDeleted: () {
                  final updated = Set<String>.from(criteria.selectedProviders)..remove(provider);
                  _managerService.updateFilterCriteria(
                    criteria.copyWith(selectedProviders: updated),
                  );
                },
              ),
            ),
          ActionChip(
            label: const Text('Reset All', style: TextStyle(fontSize: 11)),
            avatar: const Icon(Icons.refresh, size: 14),
            onPressed: () {
              _managerService.clearFilters();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHubStatusHeader(BuildContext context, int visibleCount) {
    final theme = Theme.of(context);
    final query = _managerService.searchQuery;
    final loadedCount = _showMyModelsOnly
        ? _managerService.myModels.length
        : _managerService.models.length;
    final hasMore = !_showMyModelsOnly && _managerService.hasMoreModels;
    final suffix = hasMore ? '+' : '';
    final countText = visibleCount < loadedCount
        ? '$visibleCount / $loadedCount$suffix models'
        : '$visibleCount$suffix ${visibleCount == 1 && !hasMore ? "model" : "models"}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _showMyModelsOnly
                    ? (query.isEmpty
                        ? 'My Models & Downloads'
                        : 'My Models matching "$query"')
                    : (query.isEmpty
                        ? 'Hugging Face API'
                        : 'HF Results for "$query"'),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Text(
            countText,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline or network issue. Showing local models.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: () => _managerService.loadModels(),
            child: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard({
    required BuildContext context,
    required OpenModel model,
    required bool isSelected,
    required bool isDownloaded,
    required bool isDownloading,
    required double downloadProgress,
    ModelDownloadState? downloadState,
  }) {
    final theme = Theme.of(context);
    final pubColor = _getPublisherColor(model.publisher);
    final downloadError = downloadState?.errorMessage;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Card(
        elevation: isSelected ? 3 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _selectedModelId = model.id;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Name of model + Link + Size & Downloaded status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Model name & Publisher
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  model.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Link icon
                              IconButton(
                                icon: const Icon(Icons.link, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'View Model Link',
                                color: theme.colorScheme.primary,
                                onPressed: () => _showModelLinkDialog(model),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: pubColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  model.publisher,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: pubColor,
                                  ),
                                ),
                              ),
                              if (model.isGated)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.lock_outline_rounded,
                                        size: 11,
                                        color: Colors.amber.shade900,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Gated',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (model.isTooLargeForPhone(
                                deviceRamGb: _managerService.deviceRamGb,
                              ))
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        size: 11,
                                        color:
                                            theme.colorScheme.onErrorContainer,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Not recommended',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: theme
                                              .colorScheme.onErrorContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Size + Downloaded status indicator
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatSizeWithParts(
                            model.downloadSizeMb,
                            partCount: model.partCount,
                          ),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDownloaded
                                ? Colors.green.shade50
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isDownloaded
                                  ? Colors.green.shade300
                                  : theme.colorScheme.outlineVariant,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDownloaded
                                    ? Icons.check_circle
                                    : Icons.cloud_download_outlined,
                                size: 12,
                                color: isDownloaded
                                    ? Colors.green.shade700
                                    : theme.colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isDownloaded ? "Downloaded" : 'Download',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isDownloaded
                                      ? Colors.green.shade800
                                      : theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Description Box (middle of card from wireframe)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                      50,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(60),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildDetailPill(
                            context,
                            '${model.parameterSizeB}B Params',
                            Icons.auto_awesome,
                          ),
                          _buildDetailPill(
                            context,
                            model.format,
                            Icons.extension_outlined,
                          ),
                          _buildDetailPill(
                            context,
                            model.quantization,
                            Icons.tune,
                          ),
                          _buildDetailPill(
                            context,
                            'Min ${model.minRamGb} GB RAM',
                            Icons.memory_rounded,
                          ),
                          if (model.isSplit)
                            _buildDetailPill(
                              context,
                              '${model.partCount} Parts',
                              Icons.layers_rounded,
                            ),
                          if (model.createdAt != null)
                            _buildDetailPill(
                              context,
                              formatRelativeReleaseDate(model.createdAt!),
                              Icons.calendar_today_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Card Bottom Action Row: Download / Pause / Resume / Delete & Selected Radio
                if (downloadError != null && !isDownloading && !isDownloaded) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withAlpha(120),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          downloadError,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                        if (downloadState?.isGatedError == true) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              ActionChip(
                                avatar: const Icon(Icons.key_rounded, size: 14),
                                label: const Text(
                                  'Add HF Token',
                                  style: TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () async {
                                  final saved = await showHfTokenDialog(context);
                                  if (saved && mounted) {
                                    _managerService.downloadModel(
                                      model.id,
                                      model: model,
                                    );
                                  }
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.search_rounded, size: 14),
                                label: const Text(
                                  'Find ungated',
                                  style: TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  final query = '${model.name} gguf';
                                  setState(() {
                                    _searchController.text = query;
                                  });
                                  _managerService.setDownloadedOnly(false);
                                  _managerService.searchModels(query);
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Download / Progress / Pause / Resume / Retry / Delete Controls
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isDownloaded) ...[
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green.shade700,
                                side: BorderSide(color: Colors.green.shade400),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text('Downloaded'),
                              onPressed: () {
                                setState(() {
                                  _selectedModelId = model.id;
                                });
                              },
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: theme.colorScheme.error,
                              ),
                              tooltip: 'Delete downloaded file',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _confirmDeleteModel(model),
                            ),
                          ] else if (isDownloading) ...[
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                value: downloadProgress > 0
                                    ? downloadProgress
                                    : null,
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                downloadState != null && downloadState.totalBytes > 0
                                    ? '${downloadState.totalParts > 1 ? 'Part ${downloadState.currentPartIndex + 1}/${downloadState.totalParts} • ' : ''}${(downloadProgress * 100).toInt()}% (${_formatBytes(downloadState.receivedBytes)}${downloadState.speedBytesPerSec > 0 ? ' • ${_formatBytes(downloadState.speedBytesPerSec.round())}/s' : ''})'
                                    : 'Downloading ${(downloadProgress * 100).toInt()}%...',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: const Icon(Icons.pause_rounded, size: 18),
                              tooltip: 'Pause download',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _managerService.pauseDownload(model.id),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: 'Cancel download',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _managerService.cancelDownload(model.id),
                            ),
                          ] else if (downloadState?.isPaused == true) ...[
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, size: 16),
                              label: Text(
                                'Resume ${(downloadProgress * 100).toInt()}%',
                              ),
                              onPressed: () => _managerService.resumeDownload(
                                model.id,
                                model: model,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: 'Cancel paused download',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _managerService.cancelDownload(model.id),
                            ),
                          ] else ...[
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                              ),
                              icon: Icon(
                                downloadError != null
                                    ? Icons.refresh_rounded
                                    : Icons.download_rounded,
                                size: 16,
                              ),
                              label: Text(
                                downloadError != null ? 'Retry' : 'Download',
                              ),
                              onPressed: () => _startDownloadWithChecks(model),
                            ),
                            if (!model.id.startsWith('local:')) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.layers_outlined, size: 18),
                                tooltip: 'Choose quantization',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _showVariantPickerSheet(model),
                              ),
                            ],
                            if (_managerService.isCustomModel(model.id)) ...[
                              const SizedBox(width: 2),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: theme.colorScheme.outline,
                                ),
                                tooltip: 'Remove custom model',
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    _managerService.removeCustomModel(model.id),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),

                    // Selected Radio indicator matching wireframe
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedModelId = model.id;
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isSelected ? 'Selected' : 'Select',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 20,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPill(BuildContext context, String text, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // (+) Add new model button from wireframe
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: Icon(
                  Icons.add_circle,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                label: const Text(
                  'Add new model',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                onPressed: _showAddCustomModelDialog,
              ),

              // (>) Chat button from wireframe
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                icon: const Text(
                  'Chat',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                label: const Icon(Icons.arrow_forward_rounded, size: 18),
                onPressed: _onChatPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
