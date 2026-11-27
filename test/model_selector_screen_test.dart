import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/screens/model_selector_screen.dart';
import 'package:mobai/services/model_manager_service.dart';

void main() {
  setUp(() {
    final service = ModelManagerService();
    service.clearFilters();
    // Pre-populate with dummy models for widget tests
    service.addCustomModel(
      OpenModel(
        id: 'test-meta/llama',
        name: 'Llama 3.2 1B Test',
        publisher: 'Meta',
        parameterSizeB: '1.0',
        format: 'GGUF',
        quantization: 'Q4_K_M',
        downloadSizeMb: 800,
        minRamGb: 4,
        downloadUrl: 'https://huggingface.co/test-meta/llama/resolve/main/model.gguf',
        description: 'Test Llama model',
        repoUrl: 'https://huggingface.co/test-meta/llama',
      ),
    );
    service.addCustomModel(
      OpenModel(
        id: 'test-qwen/qwen',
        name: 'Qwen 2.5 0.5B Test',
        publisher: 'Qwen',
        parameterSizeB: '0.5',
        format: 'GGUF',
        quantization: 'Q4_K_M',
        downloadSizeMb: 390,
        minRamGb: 3,
        downloadUrl: 'https://huggingface.co/test-qwen/qwen/resolve/main/model.gguf',
        description: 'Test Qwen model',
        repoUrl: 'https://huggingface.co/test-qwen/qwen',
      ),
    );
  });

  testWidgets('ModelSelectorScreen renders quick chips, sort/filter icons, and models', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ModelSelectorScreen(),
      ),
    );
    await tester.pump();

    // Verify search bar, sort, and filter buttons exist
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

    // Quick chips should only show All & My Models (no Phone <= 8B)
    expect(find.text('All'), findsOneWidget);
    expect(find.textContaining('My Models'), findsOneWidget);
    expect(find.textContaining('Phone <=8B'), findsNothing);

    // Verify models are displayed
    expect(find.text('Model Catalog'), findsOneWidget);
    expect(find.text('Llama 3.2 1B Test'), findsOneWidget);
    expect(find.text('Qwen 2.5 0.5B Test'), findsOneWidget);
  });

  testWidgets('Model Link dialog shows Open in Browser and Copy buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ModelSelectorScreen(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('View Model Link').first);
    await tester.pumpAndSettle();

    expect(find.text('Model Link'), findsOneWidget);
    expect(find.text('Open in Browser'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Copy'), findsNWidgets(2));
  });

  testWidgets('Filter bottom sheet shows Hide Not Recommended, Downloaded sync, Min/Max inputs, and searchable creators', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ModelSelectorScreen(),
      ),
    );
    await tester.pump();

    // Tap filter button
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    // Verify filter bottom sheet switches & sliders + min/max inputs
    expect(find.text('Filter Models'), findsOneWidget);
    expect(find.text('Hide "Not Recommended" models'), findsOneWidget);
    expect(find.text('Downloaded only (My Models)'), findsOneWidget);
    expect(find.text('Download Size'), findsOneWidget);
    expect(find.text('Parameters'), findsOneWidget);
    expect(find.text('Min'), findsWidgets);
    expect(find.text('Max'), findsWidgets);

    // Scroll outer ListView to Publishers & Creators
    final outerScrollable = find.byType(Scrollable).at(1);
    await tester.scrollUntilVisible(
      find.text('Search creators...'),
      120,
      scrollable: outerScrollable,
    );
    expect(find.text('Publishers & Creators'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search creators...'),
      'Qwen',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Qwen'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Meta'), findsNothing);
  });
}
