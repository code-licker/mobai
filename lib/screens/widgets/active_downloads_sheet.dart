import 'package:material_ui/material_ui.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/utils/format_utils.dart';

/// Compact AppBar badge/pill showing active or paused model downloads.
///
/// Renders [SizedBox.shrink] when there are no active or paused downloads.
class DownloadIndicatorButton extends StatelessWidget {
  const DownloadIndicatorButton({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = ModelManagerService();
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final items = manager.activeAndPausedDownloads;
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final activeCount = manager.activeDownloadCount;
        final pausedCount = manager.pausedDownloadCount;
        final hasActive = activeCount > 0;
        final count = hasActive ? activeCount : pausedCount;

        final bgColor = hasActive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest;
        final fgColor = hasActive
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant;
        final borderColor = hasActive
            ? theme.colorScheme.primary.withAlpha(90)
            : theme.colorScheme.outlineVariant;

        final tooltip = hasActive
            ? '$activeCount active download${activeCount == 1 ? '' : 's'}'
            : '$pausedCount paused download${pausedCount == 1 ? '' : 's'}';

        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: tooltip,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => showActiveDownloadsSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasActive
                          ? Icons.downloading_rounded
                          : Icons.pause_circle_outline_rounded,
                      size: 16,
                      color: fgColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: fgColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens a live-updating bottom sheet displaying all active and paused downloads
/// regardless of current catalog filters, search queries, or active screen.
Future<void> showActiveDownloadsSheet(BuildContext context) {
  final manager = ModelManagerService();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          final theme = Theme.of(context);
          final downloads = manager.activeAndPausedDownloads;
          final activeCount = manager.activeDownloadCount;
          final pausedCount = manager.pausedDownloadCount;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        activeCount > 0
                            ? Icons.downloading_rounded
                            : Icons.download_for_offline_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Model Downloads',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (downloads.isNotEmpty)
                              Text(
                                _buildHeaderSubtitle(activeCount, pausedCount),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  if (downloads.isEmpty)
                    _buildEmptyState(context, () => Navigator.pop(sheetContext))
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.58,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: downloads.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return _ActiveDownloadCard(
                            state: downloads[index],
                            manager: manager,
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

String _buildHeaderSubtitle(int activeCount, int pausedCount) {
  final parts = <String>[];
  if (activeCount > 0) {
    parts.add('$activeCount downloading');
  }
  if (pausedCount > 0) {
    parts.add('$pausedCount paused');
  }
  return parts.join(' • ');
}

Widget _buildEmptyState(BuildContext context, VoidCallback onClose) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 36,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No active or paused downloads',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Finished models are ready in your catalog.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: onClose,
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}

class _ActiveDownloadCard extends StatelessWidget {
  final ModelDownloadState state;
  final ModelManagerService manager;

  const _ActiveDownloadCard({
    required this.state,
    required this.manager,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = state.modelName ?? state.fileName ?? state.modelId;
    final quant = state.quantization;
    final clampedProgress = state.progress.clamp(0.0, 1.0);
    final pct = (clampedProgress * 100).round();

    final partPrefix = state.totalParts > 1
        ? 'Part ${state.currentPartIndex + 1}/${state.totalParts} • '
        : '';
    final statusText = state.isDownloading
        ? (state.speedBytesPerSec > 0
              ? '${partPrefix}Downloading • ${formatBytes(state.speedBytesPerSec.round())}/s'
              : '${partPrefix}Downloading...')
        : '${partPrefix}Paused';

    final bytesLabel = state.totalBytes > 0
        ? '${formatBytes(state.receivedBytes)} / ${formatBytes(state.totalBytes)} • $pct%'
        : (state.receivedBytes > 0
              ? '${formatBytes(state.receivedBytes)} • $pct%'
              : 'Preparing...');

    final progressValue = state.totalBytes > 0
        ? clampedProgress
        : (state.isPaused ? clampedProgress : null);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(110),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (quant != null && quant.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              quant,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: state.isDownloading
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (state.isDownloading)
                IconButton.filledTonal(
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  tooltip: 'Pause download',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => manager.pauseDownload(state.modelId),
                )
              else
                IconButton.filledTonal(
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  tooltip: 'Resume download',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => manager.resumeDownload(state.modelId),
                ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                tooltip: 'Cancel download',
                visualDensity: VisualDensity.compact,
                onPressed: () => manager.cancelDownload(state.modelId),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progressValue,
            borderRadius: BorderRadius.circular(6),
            minHeight: 6,
          ),
          const SizedBox(height: 6),
          Text(
            bytesLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
