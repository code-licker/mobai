import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobai/services/chat_session_service.dart';
import 'package:mobai/services/local_inference_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';
import 'package:mobai/utils/format_utils.dart';

/// First-launch modal prompting the user to pick a parent folder for
/// `MobAI/models` and `MobAI/chats`, or fall back to App Documents.
Future<void> showFirstLaunchStoragePrompt(BuildContext context) async {
  final storage = StorageService();
  String? errorMessage;
  bool isBusy = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.folder_special_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Choose MobAI Folder')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MobAI stores downloaded GGUF models in MobAI/models and conversations in MobAI/chats.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Default folder:',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          storage.defaultRootPath,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        errorMessage!,
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
            actions: [
              TextButton(
                onPressed: isBusy
                    ? null
                    : () async {
                        setDialogState(() {
                          isBusy = true;
                          errorMessage = null;
                        });
                        await storage.markConfiguredAsDefault();
                        await ModelManagerService().syncWithStorage();
                        await ChatSessionService().loadSessionsFromStorage();
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      },
                child: const Text('Use Default'),
              ),
              FilledButton.icon(
                icon: isBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('Choose Folder'),
                onPressed: isBusy
                    ? null
                    : () async {
                        final pickedUri = await FilePicker.pickDirectory(
                          dialogTitle: 'Select parent folder for MobAI',
                        );
                        if (pickedUri == null) return;
                        final picked = StorageService.resolveDirectoryUri(pickedUri);

                        setDialogState(() {
                          isBusy = true;
                          errorMessage = null;
                        });

                        final result = await storage.setCustomFolder(picked);
                        if (result.success) {
                          await ModelManagerService().syncWithStorage();
                          await ChatSessionService().loadSessionsFromStorage();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } else {
                          setDialogState(() {
                            isBusy = false;
                            errorMessage = result.errorMessage;
                          });
                        }
                      },
              ),
            ],
          );
        },
      );
    },
  );
}

/// Bottom sheet showing current `MobAI/models` & `MobAI/chats` paths and
/// allowing the user to change folders (with optional data migration).
Future<void> showStorageSettingsSheet(BuildContext context) async {
  final storage = StorageService();
  int usedBytes = await storage.getModelsDiskUsageBytes();
  String? errorMessage;
  bool isBusy = false;

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final theme = Theme.of(context);

          Future<void> applyFolderChange({
            String? customPath,
            required bool resetToDefault,
          }) async {
            bool migrate = false;
            if (await storage.hasExistingData()) {
              if (!context.mounted) return;
              final choice = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Existing Models & Chats Found'),
                  content: const Text(
                    'Would you like to move your downloaded models and chat history into the new MobAI folder, or start fresh there?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, 'cancel'),
                      child: const Text('Cancel'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'fresh'),
                      child: const Text('Start Fresh'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'move'),
                      child: const Text('Move Existing'),
                    ),
                  ],
                ),
              );
              if (choice == null || choice == 'cancel') return;
              migrate = choice == 'move';
            }

            setSheetState(() {
              isBusy = true;
              errorMessage = null;
            });

            final result = resetToDefault
                ? await storage.resetToDefaultFolder(
                    migrateExisting: migrate,
                    beforeMigrate: () => LocalInferenceService().unloadModel(),
                  )
                : await storage.setCustomFolder(
                    customPath!,
                    migrateExisting: migrate,
                    beforeMigrate: () => LocalInferenceService().unloadModel(),
                  );

            if (result.success) {
              await ModelManagerService().syncWithStorage();
              await ChatSessionService().loadSessionsFromStorage();
              usedBytes = await storage.getModelsDiskUsageBytes();
              setSheetState(() {
                isBusy = false;
              });
            } else {
              setSheetState(() {
                isBusy = false;
                errorMessage = result.errorMessage;
              });
            }
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder_copy_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        'MobAI Storage Location',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: isBusy ? null : () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  _PathRow(label: 'Models folder', path: storage.modelsPath),
                  const SizedBox(height: 8),
                  _PathRow(label: 'Chats folder', path: storage.chatsPath),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.storage_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Models disk usage: ${formatBytes(usedBytes)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        errorMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (!storage.isUsingDefault) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isBusy
                                ? null
                                : () => applyFolderChange(resetToDefault: true),
                            child: const Text('Use Default'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          icon: isBusy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.folder_open_rounded, size: 18),
                          label: const Text('Change Folder'),
                          onPressed: isBusy
                              ? null
                              : () async {
                                  final pickedUri = await FilePicker.pickDirectory(
                                    dialogTitle: 'Select parent folder for MobAI',
                                  );
                                  if (pickedUri == null) return;
                                  final picked = StorageService.resolveDirectoryUri(
                                    pickedUri,
                                  );
                                  await applyFolderChange(
                                    customPath: picked,
                                    resetToDefault: false,
                                  );
                                },
                        ),
                      ),
                    ],
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

class _PathRow extends StatelessWidget {
  final String label;
  final String path;

  const _PathRow({
    required this.label,
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            path,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}
