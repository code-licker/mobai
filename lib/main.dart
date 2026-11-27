import 'dart:async';

import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobai/screens/home_screen.dart';
import 'package:mobai/services/chat_session_service.dart';
import 'package:mobai/services/download_notification_service.dart';
import 'package:mobai/services/local_inference_service.dart';
import 'package:mobai/services/model_manager_service.dart';
import 'package:mobai/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final modelManager = ModelManagerService();
  final inferenceService = LocalInferenceService();
  modelManager.onBeforeDeleteModel = (filePath) async {
    if (inferenceService.loadedModelPath == filePath) {
      await inferenceService.unloadModel();
    }
  };

  await StorageService().init();
  await modelManager.syncWithStorage();
  await DownloadNotificationService().initialize(
    onPause: modelManager.pauseDownload,
    onResume: (modelId) async {
      unawaited(modelManager.resumeDownload(modelId));
    },
    onCancel: modelManager.cancelDownload,
    onForceClose: modelManager.pauseAllActiveDownloads,
  );
  await ChatSessionService().loadSessionsFromStorage();

  runApp(
    MaterialApp(
      home: const HomeScreen(),
      title: 'MobAI App',
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(),
      ),
    ),
  );
}
