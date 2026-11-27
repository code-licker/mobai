import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// Bridges Flutter download state and lifecycle with Android's foreground
/// download service, notification actions, and back-to-background behavior.
class DownloadNotificationService {
  static final DownloadNotificationService _instance =
      DownloadNotificationService._internal();
  factory DownloadNotificationService() => _instance;
  DownloadNotificationService._internal();

  static const MethodChannel _methodChannel = MethodChannel(
    'com.example.mobai/download_notifications',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.example.mobai/download_notification_events',
  );

  bool _hasPendingOpenDownloads = false;
  late final StreamController<void> _openDownloadsController =
      StreamController<void>.broadcast(
    onListen: () {
      if (_hasPendingOpenDownloads) {
        _hasPendingOpenDownloads = false;
        scheduleMicrotask(() {
          if (!_openDownloadsController.isClosed) {
            _openDownloadsController.add(null);
          }
        });
      }
    },
  );

  Stream<void> get onOpenDownloadsRequested => _openDownloadsController.stream;

  Future<void> Function(String modelId)? _onPause;
  Future<void> Function(String modelId)? _onResume;
  Future<void> Function(String modelId)? _onCancel;
  Future<void> Function()? _onForceClose;

  StreamSubscription<dynamic>? _eventSubscription;
  AppLifecycleListener? _lifecycleListener;

  Future<void> initialize({
    required Future<void> Function(String modelId) onPause,
    required Future<void> Function(String modelId) onResume,
    required Future<void> Function(String modelId) onCancel,
    required Future<void> Function() onForceClose,
  }) async {
    _onPause = onPause;
    _onResume = onResume;
    _onCancel = onCancel;
    _onForceClose = onForceClose;

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    _lifecycleListener?.dispose();
    _lifecycleListener = null;

    try {
      _lifecycleListener = AppLifecycleListener(
        onResume: () => unawaited(_consumePendingAction()),
        // Pause and flush only when the engine is detaching (force-close),
        // never on inactive/paused/hidden so downloads continue in background.
        onDetach: () => unawaited(_handleForceClose()),
      );
    } catch (_) {
      // Safe no-op when WidgetsBinding is not initialized (e.g. unit tests).
    }

    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          unawaited(_handleNativeAction(event));
        },
        onError: (Object _) {
          // Safe no-op on non-Android platforms and inside unit/widget tests.
        },
        cancelOnError: false,
      );
    } on MissingPluginException {
      // Safe no-op on non-Android platforms and inside unit/widget tests.
    } catch (_) {
      // Safe no-op if ServicesBinding is unavailable.
    }

    await _consumePendingAction();
  }

  Future<void> ensureNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted && !status.isPermanentlyDenied) {
        await Permission.notification.request();
      }
    } on MissingPluginException {
      // Safe no-op in unit/widget tests without platform channels.
    } catch (_) {
      // Never block or crash downloads if permission check fails or is denied.
    }
  }

  Future<void> syncNotifications(List<ModelDownloadState> downloads) async {
    final payload = downloads
        .map(
          (s) => <String, dynamic>{
            'modelId': s.modelId,
            'title': s.modelName ?? s.fileName ?? s.modelId,
            'fileName': s.fileName,
            'progress': s.progress,
            'receivedBytes': s.receivedBytes,
            'totalBytes': s.totalBytes,
            'speedBytesPerSec': s.speedBytesPerSec,
            'isDownloading': s.isDownloading,
            'isPaused': s.isPaused,
            'errorMessage': s.errorMessage,
          },
        )
        .toList();

    try {
      await _methodChannel.invokeMethod<void>('syncDownloadNotifications', {
        'downloads': payload,
      });
    } on MissingPluginException {
      // Safe no-op on non-Android platforms and inside unit/widget tests.
    } catch (_) {
      // Ignore platform channel failures so downloads never crash.
    }
  }

  Future<void> cancelNotification(String modelId) async {
    try {
      await _methodChannel.invokeMethod<void>('cancelDownloadNotification', {
        'modelId': modelId,
      });
    } on MissingPluginException {
      // Safe no-op on non-Android platforms and inside unit/widget tests.
    } catch (_) {
      // Ignore platform channel failures.
    }
  }

  double? _cachedDeviceRamGb;

  Future<void> moveToBackground() async {
    try {
      await _methodChannel.invokeMethod<void>('moveToBackground');
    } on MissingPluginException {
      // Safe no-op on non-Android platforms and inside unit/widget tests.
    } catch (_) {
      // Ignore platform channel failures.
    }
  }

  /// Opens an external HTTP/HTTPS [url] in the system browser.
  Future<bool> openUrl(String url) async {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    try {
      final launched = await _methodChannel.invokeMethod<bool>('openUrl', {
        'url': trimmed,
      });
      return launched ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Queries physical device RAM in GB via the native channel, falling back to
  /// [fallbackGb] (default 8 GB) on unsupported platforms or inside unit tests.
  Future<double> getDeviceRamGb({double fallbackGb = 8.0}) async {
    final cached = _cachedDeviceRamGb;
    if (cached != null && cached > 0) return cached;
    try {
      final totalMb = await _methodChannel.invokeMethod<int>('getDeviceRamMb');
      if (totalMb != null && totalMb > 0) {
        final gb = totalMb / 1024.0;
        _cachedDeviceRamGb = gb;
        return gb;
      }
    } on MissingPluginException {
      // Safe fallback in unit/widget tests or non-Android runners.
    } catch (_) {}
    return fallbackGb;
  }

  Future<void> _consumePendingAction() async {
    try {
      final pending = await _methodChannel.invokeMethod<dynamic>(
        'consumePendingAction',
      );
      if (pending != null) {
        await _handleNativeAction(pending);
      }
    } on MissingPluginException {
      // Safe no-op on non-Android platforms and inside unit/widget tests.
    } catch (_) {
      // Ignore platform channel failures.
    }
  }

  Future<void> _handleNativeAction(dynamic event) async {
    if (event is! Map) return;
    final action = event['action']?.toString();
    final modelId = event['modelId']?.toString();

    switch (action) {
      case 'pause':
        if (modelId != null && modelId.isNotEmpty) {
          await _onPause?.call(modelId);
        }
      case 'resume':
        if (modelId != null && modelId.isNotEmpty) {
          await _onResume?.call(modelId);
        }
      case 'cancel':
        if (modelId != null && modelId.isNotEmpty) {
          await _onCancel?.call(modelId);
        }
      case 'open_downloads':
        if (_openDownloadsController.hasListener) {
          _openDownloadsController.add(null);
        } else {
          _hasPendingOpenDownloads = true;
        }
      case 'force_close':
        await _handleForceClose();
    }
  }

  Future<void> _handleForceClose() async {
    try {
      await _onForceClose?.call();
    } catch (_) {
      // Best-effort flush during app teardown.
    }
  }
}
