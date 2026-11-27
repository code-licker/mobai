import 'package:material_ui/material_ui.dart';
import 'package:mobai/services/storage_service.dart';

/// Prompts the user to save or clear an optional Hugging Face Access Token
/// (`hf_...`) used for gated models such as `google/gemma` or `meta-llama`.
Future<bool> showHfTokenDialog(BuildContext context) async {
  final storage = StorageService();
  final controller = TextEditingController(text: storage.hfToken ?? '');
  bool obscure = true;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.key_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(child: Text('Hugging Face Token')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Optional token for gated Hugging Face models (like official Google Gemma or Meta Llama repos). Make sure you also accept the model license on huggingface.co.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Access Token',
                      hintText: 'hf_...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscure = !obscure;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (storage.hasHfToken)
                TextButton(
                  onPressed: () async {
                    await storage.setHfToken(null);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  await storage.setHfToken(controller.text.trim());
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
  return result ?? false;
}
