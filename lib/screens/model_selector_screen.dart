import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/screens/chat_screen.dart';
import 'package:mobai/screens/widgets/model_filter_bottom_sheet.dart';
import 'package:mobai/services/chat_session_service.dart';
import 'package:mobai/services/model_manager_service.dart';

class ModelSelectorScreen extends StatefulWidget {
  const ModelSelectorScreen({super.key});

  @override
  State<ModelSelectorScreen> createState() => _ModelSelectorScreenState();
}

class _ModelSelectorScreenState extends State<ModelSelectorScreen> {
  final ModelManagerService _managerService = ModelManagerService();
  final ChatSessionService _chatService = ChatSessionService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  String? _selectedModelId;

  @override
  void initState() {
    super.initState();
    _managerService.addListener(_onServiceUpdate);
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
    _searchController.dispose();
    _managerService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      final filtered = _managerService.filteredModels;
      if (_selectedModelId == null && filtered.isNotEmpty) {
        _selectedModelId = filtered.first.id;
      } else if (_selectedModelId != null && !filtered.any((m) => m.id == _selectedModelId)) {
        _selectedModelId = filtered.isNotEmpty ? filtered.first.id : null;
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

  String _formatMb(double mb) {
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toInt()} MB';
  }

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
      _showDownloadAndProceedSheet(model);
    }
  }

  void _navigateToChat(OpenModel model) {
    final session = _chatService.createSession(
      modelId: model.id,
      modelName: model.name,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(sessionId: session.id),
      ),
    );
  }

  void _showDownloadAndProceedSheet(OpenModel model) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isDownloading = _managerService.isModelDownloading(model.id);
            final progress = _managerService.getDownloadProgress(model.id);
            final isDownloaded = _managerService.isModelDownloaded(model.id);

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
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.downloading_rounded,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Downloading Model Weights',
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
                  LinearProgressIndicator(
                    value: isDownloaded
                        ? 1.0
                        : (isDownloading ? progress : null),
                    borderRadius: BorderRadius.circular(6),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isDownloaded
                            ? 'Ready for inference!'
                            : '${(progress * 100).toInt()}% • ${(progress * model.downloadSizeMb).toInt()} / ${model.downloadSizeMb} MB',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Format: ${model.format}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (!isDownloading && !isDownloaded)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Start Download'),
                        onPressed: () async {
                          setSheetState(() {});
                          await _managerService.downloadModel(
                            model.id,
                            onProgress: (_) {
                              setSheetState(() {});
                            },
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            _navigateToChat(model);
                          }
                        },
                      ),
                    ),
                  if (isDownloading)
                    Center(
                      child: Text(
                        'Please keep the app open while preparing weights...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );

    // Auto-trigger download when sheet opens
    if (!_managerService.isModelDownloading(model.id)) {
      _managerService.downloadModel(model.id).then((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
          _navigateToChat(model);
        }
      });
    }
  }

  void _showAddCustomModelDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final sizeController = TextEditingController(text: '450');
    final publisherController = TextEditingController(text: 'Community');
    final descController = TextEditingController();
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_box_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Add New Model'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Model Name *',
                  hintText: 'e.g. Mistral 7B Instruct',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: publisherController,
                decoration: const InputDecoration(
                  labelText: 'Publisher / Author',
                  hintText: 'e.g. Mistral AI',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Hugging Face / GGUF URL *',
                  hintText: 'https://huggingface.co/...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sizeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Estimated Size (MB)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Model Description',
                  hintText: 'Notes or reasoning capabilities...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final newModel = OpenModel(
                id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                publisher: publisherController.text.trim().isEmpty
                    ? 'Community'
                    : publisherController.text.trim(),
                parameterSizeB: '1.5',
                format: 'GGUF',
                quantization: 'Q4_K_M',
                downloadSizeMb: int.tryParse(sizeController.text.trim()) ?? 500,
                minRamGb: 4,
                downloadUrl: urlController.text.trim(),
                description: descController.text.trim().isEmpty
                    ? 'Custom user-imported model for on-device inference.'
                    : descController.text.trim(),
                repoUrl: urlController.text.trim().isEmpty
                    ? 'https://huggingface.co'
                    : urlController.text.trim(),
              );

              _managerService.addCustomModel(newModel);
              setState(() {
                _selectedModelId = newModel.id;
              });

              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Added $name to catalog')));
            },
            child: const Text('Add Model'),
          ),
        ],
      ),
    );
  }

  void _showModelLinkDialog(OpenModel model) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.link_rounded),
            const SizedBox(width: 8),
            const Text('Model Link'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              model.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Repository: ${model.repoUrl}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              'Download URL: ${model.downloadUrl}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final models = _managerService.filteredModels;
    final isLoading = _managerService.isLoading;
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

            // Active Filter Chips Bar (scrollable horizontally)
            if (filterCriteria.isActive)
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: models.length,
                      itemBuilder: (context, index) {
                        final model = models[index];
                        final isSelected = _selectedModelId == model.id;
                        final isDownloaded = _managerService.isModelDownloaded(
                          model.id,
                        );
                        final isDownloading = _managerService
                            .isModelDownloading(model.id);
                        final downloadProgress = _managerService
                            .getDownloadProgress(model.id);

                        return _buildModelCard(
                          context: context,
                          model: model,
                          isSelected: isSelected,
                          isDownloaded: isDownloaded,
                          isDownloading: isDownloading,
                          downloadProgress: downloadProgress,
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
                isLabelVisible: criteria.isActive,
                label: Text(
                  '${criteria.activeFilterCount}',
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          if (criteria.isSizeFilterActive && criteria.sizeRangeMb != null)
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
          if (criteria.isParamsFilterActive && criteria.paramsRangeB != null)
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
          if (criteria.isRamFilterActive && criteria.ramRangeGb != null)
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

  Widget _buildHubStatusHeader(BuildContext context, int count) {
    final theme = Theme.of(context);
    final query = _managerService.searchQuery;

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
                query.isEmpty ? 'Hugging Face API' : 'HF Results for "$query"',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Text(
            '$count ${count == 1 ? "model" : "models"}',
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
  }) {
    final theme = Theme.of(context);
    final pubColor = _getPublisherColor(model.publisher);

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
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Size + Downloaded status indicator
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${model.downloadSizeMb} MB',
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
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Card Bottom Action Row: Download button & Selected Radio
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Download Button
                    if (isDownloaded)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green.shade700,
                          side: BorderSide(color: Colors.green.shade400),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Downloaded'),
                        onPressed: () {},
                      )
                    else if (isDownloading)
                      Row(
                        children: [
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
                          Text(
                            'Downloading ${(downloadProgress * 100).toInt()}%...',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Download'),
                        onPressed: () {
                          _managerService.downloadModel(model.id);
                        },
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
