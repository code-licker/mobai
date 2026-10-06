import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobai/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen renders title and New chat button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    expect(find.text('MobAI'), findsOneWidget);
    expect(find.text('New chat'), findsOneWidget);
    expect(find.text('Recent Chats'), findsOneWidget);
  });
}
