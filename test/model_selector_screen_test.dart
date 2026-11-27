import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/models/open_model.dart';
import 'package:mobai/screens/model_selector_screen.dart';
import 'package:mobai/screens/widgets/model_filter_bottom_sheet.dart';
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
        description: 'Compact Llama 3.2 1B test model card summary for mobile devices.',
        repoUrl: 'https://huggingface.co/test-meta/llama',
        createdAt: DateTime.utc(2026, 11, 15),
        downloads: 398,
        likes: 12,
        hasFetchedDescription: true,
        license: 'llama3.2',
        baseModel: 'meta-llama/Llama-3.2-1B',
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
        description: 'Compact Qwen 2.5 0.5B test model card summary.',
        repoUrl: 'https://huggingface.co/test-qwen/qwen',
        hasFetchedDescription: true,
      ),
    );
  });

  testWidgets('ModelSelectorScreen renders quick chips, sort/filter icons, stat badges, and models', (WidgetTester tester) async {
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

    // Verify stat badges appear above description beside publisher
    expect(find.text('398'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    // Verify models are displayed
    expect(find.text('Model Catalog'), findsOneWidget);
    expect(find.text('Llama 3.2 1B Test'), findsOneWidget);
    expect(find.text('Qwen 2.5 0.5B Test'), findsOneWidget);
  });

  testWidgets('Tapping model description opens full details popup with specs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ModelSelectorScreen(),
      ),
    );
    await tester.pump();

    final descFinder = find.text(
      'Compact Llama 3.2 1B test model card summary for mobile devices.',
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(descFinder);
    await tester.pumpAndSettle();

    expect(find.text('Description'), findsOneWidget);
    expect(find.text('398 downloads'), findsOneWidget);
    expect(find.text('12 likes'), findsOneWidget);
    expect(find.text('llama3.2'), findsOneWidget);
    expect(find.text('Base: meta-llama/Llama-3.2-1B'), findsOneWidget);
    expect(find.text('Model Links'), findsOneWidget);
  });

  testWidgets('Model Link dialog shows uniform Open and Copy buttons plus .gguf warning', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ModelSelectorScreen(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('View Model Link').first);
    await tester.pumpAndSettle();

    expect(find.text('Model Link'), findsOneWidget);
    expect(find.text('Open'), findsNWidgets(2));
    expect(find.text('Copy'), findsNWidgets(2));
    expect(
      find.text('Opening this .gguf URL in a browser will trigger a file download.'),
      findsOneWidget,
    );
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

    // Toggle "Downloaded only (My Models)" while visible at top of sheet
    await tester.tap(find.text('Downloaded only (My Models)'));
    await tester.pumpAndSettle();

    // Scroll outer vertical ListView inside ModelFilterBottomSheet to Publishers & Creators
    final outerScrollable = find
        .descendant(
          of: find.byType(ModelFilterBottomSheet),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Search creators...'),
      150,
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

    await tester.tap(find.textContaining('Apply Filters'));
    await tester.pumpAndSettle();
    expect(ModelManagerService().filterCriteria.downloadedOnly, isTrue);
  });
}
