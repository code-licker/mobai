import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:mobai/models/chat_session.dart';
import 'package:mobai/screens/chat_screen.dart';
import 'package:mobai/screens/model_selector_screen.dart';
import 'package:mobai/screens/widgets/active_downloads_sheet.dart';
import 'package:mobai/screens/widgets/hf_token_dialog.dart';
import 'package:mobai/screens/widgets/storage_setup_dialog.dart';
import 'package:mobai/services/chat_session_service.dart';
import 'package:mobai/services/download_notification_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ChatSessionService _chatService = ChatSessionService();
  final StorageService _storageService = StorageService();
  final ModelManagerService _modelManager = ModelManagerService();
  String _selectedFilter = 'all'; // 'all' or 'history'
  bool _promptShownThisSession = false;
  String _lastDownloadedIdsSig = '';
  bool _lastHasActiveDownloads = false;
  StreamSubscription<void>? _openDownloadsSub;
  bool _isDownloadsSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _lastDownloadedIdsSig = _downloadedSignature();
    _lastHasActiveDownloads = _modelManager.hasActiveDownloads;
    _chatService.addListener(_onServiceUpdate);
    _storageService.addListener(_onServiceUpdate);
    _modelManager.addListener(_onModelManagerUpdate);
    _openDownloadsSub = DownloadNotificationService().onOpenDownloadsRequested
        .listen((_) => _openDownloadsSheetFromNotification());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_promptShownThisSession &&
          _storageService.isInitialized &&
          !_storageService.isConfigured) {
        _promptShownThisSession = true;
        showFirstLaunchStoragePrompt(context);
      }
    });
  }

  @override
  void dispose() {
    _openDownloadsSub?.cancel();
    _chatService.removeListener(_onServiceUpdate);
    _storageService.removeListener(_onServiceUpdate);
    _modelManager.removeListener(_onModelManagerUpdate);
    super.dispose();
  }

  void _openDownloadsSheetFromNotification() {
    if (!mounted || _isDownloadsSheetOpen) return;
    _isDownloadsSheetOpen = true;
    showActiveDownloadsSheet(context).whenComplete(() {
      if (mounted) {
        _isDownloadsSheetOpen = false;
      }
    });
  }

  String _downloadedSignature() =>
      _modelManager.downloadedModels.map((m) => m.modelId).join('|');

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _onModelManagerUpdate() {
    if (!mounted) return;
    final nextSig = _downloadedSignature();
    final nextHasActive = _modelManager.hasActiveDownloads;
    if (nextSig != _lastDownloadedIdsSig ||
        nextHasActive != _lastHasActiveDownloads) {
      _lastDownloadedIdsSig = nextSig;
      _lastHasActiveDownloads = nextHasActive;
      setState(() {});
    }
  }

  void _navigateToModelSelector() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ModelSelectorScreen(),
      ),
    );
  }

  void _openChat(ChatSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(sessionId: session.id),
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  void _confirmDeleteChat(ChatSession session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat?'),
        content: Text('Are you sure you want to delete "${session.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              _chatService.deleteSession(session.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmClearAllChats() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat History?'),
        content: const Text('This will delete all conversations. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              _chatService.clearAllSessions();
              Navigator.pop(context);
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = _chatService.sessions;

    return PopScope(
      canPop: !_modelManager.hasActiveDownloads,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _modelManager.hasActiveDownloads) {
          DownloadNotificationService().moveToBackground();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'MobAI',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          centerTitle: false,
          actions: [
            const DownloadIndicatorButton(),
            IconButton(
              icon: const Icon(Icons.hub_outlined),
              tooltip: 'Model Catalog',
              onPressed: _navigateToModelSelector,
            ),
          ],
        ),
        // Sidebar menu with (New chat - Chat history) from requirements
        drawer: _buildSidebarMenu(context),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header: Recent chats
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFilter == 'history' ? 'Chat History' : 'Recent Chats',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${sessions.length} conversation${sessions.length == 1 ? '' : 's'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (sessions.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: theme.colorScheme.error,
                        ),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Clear', style: TextStyle(fontSize: 12)),
                        onPressed: _confirmClearAllChats,
                      ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Recent chats list
              Expanded(
                child: sessions.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          return _buildChatSessionCard(context, session);
                        },
                      ),
              ),
            ],
          ),
        ),
        // New chat button at bottom matching wireframe Page 2
        bottomSheet: _buildBottomNewChatBar(context),
      ),
    );
  }

  Widget _buildSidebarMenu(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(50),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.colorScheme.primary,
                    child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'MobAI On-Device',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Private edge intelligence',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Sidebar items specified in PDF requirements: (New chat - Chat history)
            ListTile(
              leading: Icon(Icons.add_comment_rounded, color: theme.colorScheme.primary),
              title: const Text('New chat', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context); // close drawer
                _navigateToModelSelector();
              },
            ),
            ListTile(
              leading: Icon(Icons.history_rounded, color: theme.colorScheme.onSurfaceVariant),
              title: const Text('Chat history', style: TextStyle(fontWeight: FontWeight.w600)),
              selected: _selectedFilter == 'history',
              onTap: () {
                setState(() {
                  _selectedFilter = 'history';
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.dashboard_customize_outlined, color: theme.colorScheme.onSurfaceVariant),
              title: const Text('Model catalog', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _navigateToModelSelector();
              },
            ),
            ListTile(
              leading: Icon(Icons.folder_copy_outlined, color: theme.colorScheme.onSurfaceVariant),
              title: const Text('Storage location', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: _storageService.isInitialized
                  ? Text(
                      _storageService.rootPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (_storageService.isInitialized) {
                  showStorageSettingsSheet(context);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.key_rounded, color: theme.colorScheme.onSurfaceVariant),
              title: const Text('Hugging Face token', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                _storageService.hasHfToken
                    ? 'Configured (for gated models)'
                    : 'Not set (optional)',
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(context);
                showHfTokenDialog(context);
              },
            ),

            const Spacer(),
            const Divider(),

            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
              title: Text(
                'Clear chat history',
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmClearAllChats();
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'v1.0.0 • Offline Ready',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No recent chats',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "New chat" below to choose an open-weight AI model and start a conversation.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatSessionCard(BuildContext context, ChatSession session) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(90),
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openChat(session),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Title + Time + Options
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatRelativeTime(session.updatedAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _confirmDeleteChat(session),
                      child: Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Last message snippet
                Text(
                  session.lastMessagePreview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 10),

                // Model tag pill + missing-file warning if model is not on disk
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 11,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            session.modelName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_chatService.resolveModelFilePath(session) == null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withAlpha(140),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 11,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Model missing',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.error,
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
        ),
      ),
    );
  }

  Widget _buildBottomNewChatBar(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text(
              'New chat',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: _navigateToModelSelector,
          ),
        ),
      ),
    );
  }
}
