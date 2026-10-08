import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/screens/model_selector_screen.dart';
import 'package:mobai/services/model_manager_service.dart';

void main() {
  setUp(() {
    final service = ModelManagerService();
    service.clearFilters();
    // Pre-populate with dummy models for widget tests
    service.addCustomModel(OpenModel(
      id: 'test-meta/llama',
      name: 'Llama 3.2 1B Test',
      publisher: 'Meta',
      parameterSizeB: '1.0',
      format: 'GGUF',
      quantization: 'Q4_K_M',
      downloadSizeMb: 800,
      minRamGb: 4,
      downloadUrl: 'https://huggingface.co/test',
      description: 'Test Llama model',
      repoUrl: 'https://huggingface.co/test',
    ));
    service.addCustomModel(OpenModel(
      id: 'test-qwen/qwen',
      name: 'Qwen 2.5 0.5B Test',
      publisher: 'Qwen',
      parameterSizeB: '0.5',
      format: 'GGUF',
      quantization: 'Q4_K_M',
      downloadSizeMb: 390,
      minRamGb: 3,
      downloadUrl: 'https://huggingface.co/test',
      description: 'Test Qwen model',
      repoUrl: 'https://huggingface.co/test',
    ));
  });

  testWidgets('ModelSelectorScreen renders search bar and filter button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ModelSelectorScreen(),
      ),
    );
    await tester.pump();

    // Verify search bar exists
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);

    // Verify filter button exists
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

    // Verify models are displayed
    expect(find.text('Model Catalog'), findsOneWidget);
    expect(find.text('Llama 3.2 1B Test'), findsOneWidget);
    expect(find.text('Qwen 2.5 0.5B Test'), findsOneWidget);
  });

  testWidgets('Tapping filter button opens filter bottom sheet with sliders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ModelSelectorScreen(),
      ),
    );
    await tester.pump();

    // Tap filter button
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    // Verify filter bottom sheet contents
    expect(find.text('Filter Models'), findsOneWidget);
    expect(find.text('Download Size'), findsOneWidget);
    expect(find.text('Parameters'), findsOneWidget);

    // Scroll to find elements deeper in the sheet
    await tester.scrollUntilVisible(
      find.text('Publishers & Creators'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Publishers & Creators'), findsOneWidget);
  });
}
