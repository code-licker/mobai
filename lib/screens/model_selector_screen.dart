import 'package:flutter/material.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/screens/chat_screen.dart';
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

  String? _selectedModelId;

  @override
  void initState() {
    super.initState();
    _managerService.addListener(_onServiceUpdate);
    if (_managerService.models.isEmpty) {
      _managerService.loadModels();
    } else {
      _selectedModelId = _managerService.models.first.id;
    }
  }

  @override
  void dispose() {
    _managerService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      if (_selectedModelId == null && _managerService.models.isNotEmpty) {
        _selectedModelId = _managerService.models.first.id;
      }
      setState(() {});
    }
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
                    value: isDownloaded ? 1.0 : (isDownloading ? progress : null),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Added $name to catalog')),
              );
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
    final models = _managerService.models;
    final isLoading = _managerService.isLoading;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Select a model'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Models',
            onPressed: () => _managerService.loadModels(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // List of models
            Expanded(
              child: isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading model catalog...'),
                        ],
                      ),
                    )
                  : models.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              const Text('No models found'),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _showAddCustomModelDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Model'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          itemCount: models.length,
                          itemBuilder: (context, index) {
                            final model = models[index];
                            final isSelected = _selectedModelId == model.id;
                            final isDownloaded = _managerService.isModelDownloaded(model.id);
                            final isDownloading = _managerService.isModelDownloading(model.id);
                            final downloadProgress = _managerService.getDownloadProgress(model.id);

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
                                isDownloaded ? "DL'ed ✓" : 'Not DL',
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
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                              value: downloadProgress > 0 ? downloadProgress : null,
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
